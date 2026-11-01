/**
 * MindMirror Cloud Functions (2nd gen, region asia-south1 / Mumbai)
 *
 *  generateWeeklyReflection  – callable from the app. Reads the user's last 14
 *                              days of logs, computes stats, asks Gemini for a
 *                              structured reflection, saves it to Firestore.
 *  weeklyReflectionJob       – runs every Sunday 8 PM IST, generates a
 *                              reflection for every user with enough data and
 *                              sends an FCM push notification.
 *
 * The Gemini API key is stored in Secret Manager — never shipped in the app.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions, logger } = require("firebase-functions/v2");
const { defineSecret, defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({ region: "asia-south1", maxInstances: 10 });

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const GEMINI_MODEL = defineString("GEMINI_MODEL", { default: "gemini-2.5-flash" });

const DAY_MS = 24 * 60 * 60 * 1000;

const METRICS = [
  { key: "sleepHours", label: "sleep", unit: "h", higherIsBetter: true },
  { key: "mood", label: "mood", unit: "/10", higherIsBetter: true },
  { key: "energy", label: "energy", unit: "/10", higherIsBetter: true },
  { key: "productivity", label: "productivity", unit: "/10", higherIsBetter: true },
  { key: "workload", label: "workload", unit: "/10", higherIsBetter: false },
  { key: "activityMinutes", label: "physical activity", unit: " min", higherIsBetter: true },
];

// ---------------------------------------------------------------- statistics

const round1 = (v) => Math.round(v * 10) / 10;

function average(logs, key) {
  if (!logs.length) return null;
  return round1(logs.reduce((s, l) => s + Number(l[key] || 0), 0) / logs.length);
}

function pearson(xs, ys) {
  const n = xs.length;
  if (n < 5) return null;
  const mx = xs.reduce((a, b) => a + b, 0) / n;
  const my = ys.reduce((a, b) => a + b, 0) / n;
  let sxy = 0, sxx = 0, syy = 0;
  for (let i = 0; i < n; i++) {
    const dx = xs[i] - mx, dy = ys[i] - my;
    sxy += dx * dy; sxx += dx * dx; syy += dy * dy;
  }
  if (!sxx || !syy) return null;
  return sxy / Math.sqrt(sxx * syy);
}

function computeStats(logs, now = Date.now()) {
  const thisWeek = logs.filter((l) => l.date.toMillis() > now - 7 * DAY_MS);
  const lastWeek = logs.filter(
    (l) => l.date.toMillis() <= now - 7 * DAY_MS && l.date.toMillis() > now - 14 * DAY_MS
  );

  const metrics = METRICS.map((m) => {
    const current = average(thisWeek, m.key);
    const previous = average(lastWeek, m.key);
    return {
      ...m,
      current,
      previous,
      change: current != null && previous != null ? round1(current - previous) : null,
    };
  });

  const correlations = [];
  for (let i = 0; i < METRICS.length; i++) {
    for (let j = i + 1; j < METRICS.length; j++) {
      const a = METRICS[i], b = METRICS[j];
      const r = pearson(logs.map((l) => Number(l[a.key])), logs.map((l) => Number(l[b.key])));
      if (r != null && Math.abs(r) >= 0.3) {
        correlations.push({ a: a.label, b: b.label, r: Math.round(r * 100) / 100 });
      }
    }
  }
  correlations.sort((p, q) => Math.abs(q.r) - Math.abs(p.r));

  const byProd = [...thisWeek].sort((p, q) => q.productivity - p.productivity);
  const fmtDay = (l) =>
    l.date.toDate().toLocaleDateString("en-IN", { weekday: "long", timeZone: "Asia/Kolkata" });

  return {
    daysThisWeek: thisWeek.length,
    daysLastWeek: lastWeek.length,
    metrics,
    correlations: correlations.slice(0, 4),
    bestDay: byProd[0] ? { day: fmtDay(byProd[0]), productivity: byProd[0].productivity } : null,
    worstDay: byProd.length > 1
      ? { day: fmtDay(byProd[byProd.length - 1]), productivity: byProd[byProd.length - 1].productivity }
      : null,
    notes: thisWeek.map((l) => String(l.note || "").slice(0, 200)).filter(Boolean),
  };
}

// ---------------------------------------------------------------- Gemini

function buildPrompt(name, stats) {
  const lines = stats.metrics.map((m) =>
    `- ${m.label}: this week ${m.current ?? "n/a"}${m.unit}` +
    (m.previous != null ? `, last week ${m.previous}${m.unit} (change ${m.change > 0 ? "+" : ""}${m.change})` : "") +
    (m.higherIsBetter ? "" : " [lower is better]")
  );
  return `You are MindMirror, a warm, insightful wellbeing coach inside a habit-tracking app.
Write a weekly reflection for ${name || "the user"} based ONLY on the data below.

Days logged: ${stats.daysThisWeek} this week, ${stats.daysLastWeek} last week.
Weekly averages:
${lines.join("\n")}
Correlations over the last 14 days (Pearson r, |r|>=0.3):
${stats.correlations.map((c) => `- ${c.a} & ${c.b}: r=${c.r}`).join("\n") || "- none strong enough yet"}
Most productive day: ${stats.bestDay ? `${stats.bestDay.day} (${stats.bestDay.productivity}/10)` : "n/a"}
Least productive day: ${stats.worstDay ? `${stats.worstDay.day} (${stats.worstDay.productivity}/10)` : "n/a"}
User's own notes this week: ${stats.notes.length ? stats.notes.map((n) => `"${n}"`).join("; ") : "none"}

Rules:
- Speak directly to the user ("you"), encouraging but honest. Reference specific numbers.
- Correlation is not causation: say "tends to", "seems linked", never claim certainty.
- No medical or clinical diagnosis. If mood is very low (avg < 3), gently suggest talking to someone they trust.
- headline: max 8 words. summary: 2-3 sentences, max 70 words.
- trends: exactly 3 short observations. suggestions: exactly 2 concrete, small actions for next week.`;
}

async function callGemini(prompt) {
  const model = GEMINI_MODEL.value();
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY.value() },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.7,
        responseMimeType: "application/json",
        responseSchema: {
          type: "OBJECT",
          properties: {
            headline: { type: "STRING" },
            summary: { type: "STRING" },
            trends: { type: "ARRAY", items: { type: "STRING" } },
            suggestions: { type: "ARRAY", items: { type: "STRING" } },
          },
          required: ["headline", "summary", "trends", "suggestions"],
        },
      },
    }),
    signal: AbortSignal.timeout(40000),
  });
  if (!res.ok) throw new Error(`Gemini ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const json = await res.json();
  const text = json?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error("Gemini returned no content");
  const out = JSON.parse(text);
  return {
    headline: String(out.headline || "Your week in review"),
    summary: String(out.summary || ""),
    trends: (out.trends || []).map(String).slice(0, 4),
    suggestions: (out.suggestions || []).map(String).slice(0, 3),
  };
}

/** Deterministic fallback so the feature still works if the AI call fails. */
function ruleBasedReflection(stats) {
  const changed = stats.metrics
    .filter((m) => m.change != null && m.change !== 0)
    .sort((a, b) => Math.abs(b.change) - Math.abs(a.change));
  const top = changed[0];
  const good = top && (top.higherIsBetter ? top.change > 0 : top.change < 0);
  const fmt = (m) => `${m.label} ${m.change > 0 ? "rose" : "fell"} by ${Math.abs(m.change)}${m.unit} (now ${m.current}${m.unit})`;
  return {
    headline: top ? `Your ${top.label} ${good ? "improved" : "slipped"} this week` : "Your week in review",
    summary: `You logged ${stats.daysThisWeek} days this week.` +
      (top ? ` The biggest shift: ${fmt(top)}.` : "") +
      (stats.bestDay ? ` Your most productive day was ${stats.bestDay.day}.` : ""),
    trends: changed.slice(0, 3).map(fmt),
    suggestions: stats.correlations.length
      ? stats.correlations.slice(0, 2).map((c) =>
        `Your ${c.a} and ${c.b} seem ${c.r > 0 ? "to rise together" : "to move in opposite directions"} — experiment with it this week.`)
      : ["Keep logging daily so stronger patterns can emerge."],
  };
}

// ---------------------------------------------------------------- core

async function generateFor(uid, { useAI = true } = {}) {
  const since = admin.firestore.Timestamp.fromMillis(Date.now() - 14 * DAY_MS);
  const [userSnap, logSnap] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.collection(`users/${uid}/logs`).where("date", ">=", since).orderBy("date").get(),
  ]);
  const logs = logSnap.docs.map((d) => d.data());
  const stats = computeStats(logs);

  if (stats.daysThisWeek < 3) {
    throw new HttpsError("failed-precondition",
      `Log at least 3 days this week to get a reflection (you have ${stats.daysThisWeek}).`);
  }

  let reflection, source = "gemini";
  if (useAI) {
    try {
      reflection = await callGemini(buildPrompt(userSnap.get("name"), stats));
    } catch (e) {
      logger.warn("Gemini failed, using rule-based fallback", { uid, error: String(e) });
    }
  }
  if (!reflection) {
    reflection = ruleBasedReflection(stats);
    source = "rules";
  }

  const id = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata" }).format(new Date());
  const doc = {
    ...reflection,
    source,
    daysLogged: stats.daysThisWeek,
    stats: { metrics: stats.metrics.map(({ key, current, previous, change }) => ({ key, current, previous, change })), correlations: stats.correlations },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  await db.doc(`users/${uid}/reflections/${id}`).set(doc);
  return { id, ...reflection, source };
}

// ---------------------------------------------------------------- exports

exports.generateWeeklyReflection = onCall(
  { secrets: [GEMINI_API_KEY], timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Please sign in.");
    const uid = request.auth.uid;

    // Simple rate limit: one generation per 30 seconds per user.
    const last = await db.collection(`users/${uid}/reflections`)
      .orderBy("createdAt", "desc").limit(1).get();
    const lastAt = last.docs[0]?.get("createdAt")?.toMillis?.();
    if (lastAt && Date.now() - lastAt < 30 * 1000) {
      throw new HttpsError("resource-exhausted", "Please wait a few seconds before regenerating.");
    }
    return generateFor(uid);
  }
);

exports.weeklyReflectionJob = onSchedule(
  { schedule: "0 20 * * 0", timeZone: "Asia/Kolkata", secrets: [GEMINI_API_KEY], timeoutSeconds: 540 },
  async () => {
    const users = await db.collection("users").where("fcmToken", "!=", null).get();
    logger.info(`Weekly job: ${users.size} users with push tokens`);

    for (const u of users.docs) {
      try {
        const r = await generateFor(u.id);
        await admin.messaging().send({
          token: u.get("fcmToken"),
          notification: { title: "Your weekly reflection is ready ✨", body: r.headline },
          data: { type: "weekly_reflection", id: r.id },
          android: { priority: "high" },
        });
      } catch (e) {
        // Skips users without enough data, invalid tokens, etc.
        logger.info(`Skipped ${u.id}: ${e.message}`);
      }
    }
  }
);

// Exported for unit tests.
exports._test = { pearson, computeStats, ruleBasedReflection, buildPrompt };
