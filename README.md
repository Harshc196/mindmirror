# MindMirror 🪞
**See the patterns behind your days.**

MindMirror is a personalized behavioral-analytics app. You log six daily factors — **sleep, mood, energy, productivity, workload and physical activity** — and the app finds the patterns: interactive charts show how your choices relate to how you feel and perform, correlations reveal which factors move together, and an AI module (Gemini, via Firebase Cloud Functions) writes you a personal weekly reflection.

**Stack:** Flutter · Dart · Firebase Authentication · Cloud Firestore · Cloud Functions (2nd gen, Node 22) · Gemini API · FL Chart · Firebase Cloud Messaging · Local Notifications · Git/GitHub

---

## 1. Features

| Screen | What it does |
|---|---|
| **Sign in / Sign up** | Email + password auth, friendly error messages, password reset |
| **Today** | Greeting, streak counter, today's check-in with a 0–100 *day score* ring, this-week-vs-last-week table with ▲/▼ trend badges, 7-day productivity sparkline, top "pattern spotted" insight |
| **Check-in** | Six colour-coded sliders (mood shows emoji), optional note, pick any past date, edit or delete existing entries. One document per day, so re-logging updates instead of duplicating |
| **Trends** | Multi-line FL Chart with 7/14/30-day range and metric filter chips (all factors normalised to 0–10, tooltips show real values), range averages, tappable history list |
| **Insights** | AI weekly reflection (headline, summary, 3 trends, 2 suggestions), rule-based highlights ("On days with 7h+ sleep, productivity averages 7.6 vs 4.9"), strongest correlations with Pearson *r*, scatter-plot explorer for any two factors |
| **Profile** | Daily reminder toggle + time picker (local notifications), test notification, **load 30 days of sample data**, delete all data, sign out |
| **Background** | Every Sunday 8 PM IST a scheduled Cloud Function generates reflections and sends an FCM push: "Your weekly reflection is ready ✨" |

---

## 2. Architecture

```
┌──────────── Flutter app ────────────┐        ┌────────── Firebase ──────────┐
│ screens/  UI (Material 3)           │        │ Authentication (email/pwd)    │
│ widgets/  charts.dart (FL Chart)    │ ─────▶ │ Firestore                     │
│ services/ log_repository  ──────────┼──────▶ │   users/{uid}                 │
│           analytics (pure Dart)     │        │     logs/{yyyy-MM-dd}         │
│           insight_service ──────────┼──────▶ │     reflections/{date}        │
│           notification_service      │        │ Cloud Functions (asia-south1) │
│ models/   daily_log (Metric enum)   │ ◀───── │   generateWeeklyReflection ───┼──▶ Gemini API
└─────────────────────────────────────┘  FCM   │   weeklyReflectionJob (cron)  │
                                               └───────────────────────────────┘
```

**Key design decisions (good viva material):**
- **API key stays on the server.** The app never calls Gemini directly; it calls a Cloud Function that holds the key in Secret Manager. A key inside an APK can be extracted in minutes.
- **The server recomputes stats itself** from Firestore rather than trusting numbers sent by the client.
- **Graceful degradation:** if Gemini fails or times out, the function builds a rule-based reflection from the same stats, so the feature never breaks during a demo.
- **Structured AI output:** Gemini is called with `responseMimeType: application/json` + a response schema, so the app always receives `{headline, summary, trends[], suggestions[]}` — no fragile text parsing.
- **One live stream:** `HomeShell` holds a single Firestore snapshot stream (last 60 days) and passes the list to every tab — fewer reads, all screens update instantly, and Firestore's offline cache means the app works without internet.
- **Date as document ID** (`2026-10-16`) makes check-ins idempotent: one per day, edits overwrite.
- **Analytics are pure Dart** (no Firebase imports) → unit-tested in `test/analytics_test.dart`.
- **Security rules** ensure each user can only access their own data, validate every field's type and range, and block clients from writing reflections.
- **`Metric` enum** holds label, icon, colour, range and "higher is better" for each factor, so sliders, charts and analytics stay consistent from one place.

---

## 3. Setup (≈ 30 minutes)

### Prerequisites
- Flutter (latest stable) and Android Studio / an Android device
- Node.js 22 and the Firebase CLI: `npm install -g firebase-tools`
- FlutterFire CLI: `dart pub global activate flutterfire_cli`
- A Gemini API key from **Google AI Studio** (free tier is enough)

### Step 1 — Generate platform folders
```bash
cd mindmirror
flutter create . --org com.yourname --project-name mindmirror --platforms=android,ios
flutter pub get
```

### Step 2 — Create the Firebase project
1. [console.firebase.google.com](https://console.firebase.google.com) → **Add project** → `mindmirror`.
2. **Authentication** → Get started → enable **Email/Password**.
3. **Firestore Database** → Create database → production mode → location **asia-south1 (Mumbai)**.
4. Upgrade to the **Blaze** plan (required for Cloud Functions and outbound calls to Gemini). Usage for a student project stays within the free quota; set a budget alert of ₹100 to be safe.

### Step 3 — Connect the app
```bash
firebase login
flutterfire configure --project=<your-project-id>
```
This creates `lib/firebase_options.dart` and `android/app/google-services.json`.

### Step 4 — Android config for notifications
In `android/app/build.gradle.kts`:
```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    defaultConfig { minSdk = 23 }
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```
In `android/app/src/main/AndroidManifest.xml`, add above `<application>`:
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```
and inside `<application>`:
```xml
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
    </intent-filter>
</receiver>
```

### Step 5 — Deploy the backend
```bash
firebase use <your-project-id>
cd functions && npm install && npm test && cd ..
firebase functions:secrets:set GEMINI_API_KEY      # paste your key
firebase deploy --only firestore:rules,firestore:indexes,functions
```
`npm test` runs offline checks of the statistics and fallback logic.

### Step 6 — Run
```bash
flutter test        # analytics unit tests
flutter run
```
Create an account → **Profile → Load 30 days of sample data** → explore Today, Trends and Insights → tap **Generate my reflection**.

### Troubleshooting
| Problem | Fix |
|---|---|
| `firebase_options.dart` missing | Run `flutterfire configure` (Step 3) |
| Reflection says "AI service was unavailable" | Check `firebase functions:log`; usually the secret isn't set or the model name changed. Override with a `functions/.env` file containing `GEMINI_MODEL=<model-name>` |
| `failed-precondition` error | Need ≥3 check-ins in the last 7 days — load sample data |
| `PERMISSION_DENIED` on save | Rules not deployed, or a value out of range |
| Reminder never fires | Allow notifications in Android settings; disable battery optimisation for the app |
| Build error about desugaring | Step 4 Gradle changes |

---

## 4. Demo script (5 minutes)

1. **Problem (30 s):** "We all track steps or sleep, but data in separate apps never tells you *why* you had a good or bad day. MindMirror connects the factors."
2. **Sign up** live → show Firebase Auth console with the new user.
3. **Check-in:** move sliders, add a note, save → open Firestore console and show the `logs/2026-10-xx` document appear in real time.
4. **Load sample data** → **Today** tab: streak, day score, week-over-week arrows.
5. **Trends:** switch 7/14/30 days, toggle factors, tap a point for real values.
6. **Insights:** read a highlight; tap the strongest correlation (sleep ↔ energy) and show the scatter plot; explain *r*.
7. **AI reflection:** tap Generate → show the result, then show the function log and the `reflections` document. Mention the API key never leaves the server.
8. **Notifications:** enable reminder, send a test notification. Mention the Sunday FCM job.
9. **Close:** security rules + offline support + unit tests.

---

## 5. Viva preparation

**Why Flutter?** One Dart codebase for Android and iOS, hot reload, Material 3 widgets, first-party Firebase plugins (FlutterFire).

**Why Firestore instead of Realtime Database?** Documents and subcollections map naturally to users → logs → reflections; richer queries (`where date >= …orderBy date`); built-in offline cache; per-document security rules.

**How is a correlation calculated?** Pearson's *r* = Σ(x−x̄)(y−ȳ) / √(Σ(x−x̄)² · Σ(y−ȳ)²). It ranges from −1 to +1; |r| ≥ 0.7 strong, ≥ 0.4 moderate, ≥ 0.2 weak. We require at least 5 days. Correlation ≠ causation — the app says "tends to".

**Why normalise metrics in the trend chart?** Sleep (0–12 h) and activity (0–180 min) have different units; scaling to 0–10 lets them share one axis, and tooltips convert back to real values.

**How does the day score work?** Weighted average of all six factors scaled to 0–100: mood 30 %, energy 20 %, productivity 20 %, sleep 15 % (peaks at 8 h), activity 10 % (full at 45 min), workload 5 % (inverted).

**Why a Cloud Function for AI?** Keeps the API key secret, lets the server validate data and rate-limit (one generation per 30 s), and allows scheduled background generation with push notifications.

**What's the difference between FCM and local notifications?** Local notifications are scheduled on the device (daily reminder works offline). FCM is sent from the server (weekly reflection ready) and can reach the user even when the app is closed.

**How is the data secured?** Firebase Auth identifies the user; rules allow `users/{uid}/…` access only if `request.auth.uid == uid`, validate types/ranges of every log field, and forbid client writes to reflections.

**What happens offline?** Firestore caches data locally; writes are queued and synced when the connection returns. The AI reflection needs internet.

**What if the AI is down?** The function falls back to a deterministic, rule-based reflection built from the same statistics and labels it in the UI.

**Prompt engineering?** The prompt includes only aggregated statistics and the user's notes, sets a coaching persona, bans medical diagnoses, requires hedged language about correlations, fixes lengths, and enforces a JSON schema.

**Future scope:** Health Connect / Google Fit sync for automatic sleep & steps, home-screen widget, goals and challenges, lag analysis (does today's sleep affect *tomorrow's* mood?), data export to CSV, iOS release.

---

## 6. Project structure
```
mindmirror/
├── lib/
│   ├── main.dart                     # Firebase init, theme, auth gate
│   ├── models/daily_log.dart         # Metric enum + DailyLog model
│   ├── services/
│   │   ├── auth_service.dart
│   │   ├── log_repository.dart       # Firestore CRUD + sample data
│   │   ├── analytics.dart            # Pearson, streaks, highlights, day score
│   │   ├── insight_service.dart      # calls the Cloud Function
│   │   └── notification_service.dart # FCM + local notifications
│   ├── screens/  auth · home_shell · dashboard · log · trends · insights · profile
│   └── widgets/  common.dart · charts.dart
├── test/analytics_test.dart
├── functions/  index.js · test.js · package.json
├── firestore.rules · firestore.indexes.json · firebase.json
└── pubspec.yaml
```

## 7. Git workflow
```bash
git init && git add . && git commit -m "MindMirror: initial app"
git branch -M main
git remote add origin https://github.com/<you>/mindmirror.git
git push -u origin main
```
Commit as you go with clear messages (e.g. `feat: correlation explorer`, `fix: slider clamp`) — evaluators often look at the history.
