// Quick offline checks for the statistics + fallback logic (no Firebase needed).
// Run with: npm test
const assert = require("node:assert");
const { _test } = require("./index.js");
const { pearson, computeStats, ruleBasedReflection, buildPrompt } = _test;

const DAY = 86400000;
const ts = (ms) => ({ toMillis: () => ms, toDate: () => new Date(ms) });

assert.strictEqual(pearson([1, 2, 3, 4, 5], [2, 4, 6, 8, 10]).toFixed(2), "1.00");
assert.strictEqual(pearson([1, 2, 3, 4, 5], [10, 8, 6, 4, 2]).toFixed(2), "-1.00");
assert.strictEqual(pearson([1, 1, 1, 1, 1], [1, 2, 3, 4, 5]), null);

const now = Date.now();
const logs = Array.from({ length: 14 }, (_, i) => {
  const sleep = 5 + (i % 4);
  return {
    date: ts(now - (13 - i) * DAY - 1000),
    sleepHours: sleep, mood: 4 + (i % 4), energy: sleep - 1, productivity: sleep - 1 + (i >= 7 ? 1 : 0),
    workload: 5, activityMinutes: 20 + i * 2, note: i === 13 ? "Great day" : "",
  };
});
const stats = computeStats(logs, now);
assert.strictEqual(stats.daysThisWeek, 7);
assert.strictEqual(stats.daysLastWeek, 7);
assert.ok(stats.correlations.length > 0, "expected a sleep/energy correlation");
const r = ruleBasedReflection(stats);
assert.ok(r.headline && r.summary && r.trends.length && r.suggestions.length);
assert.ok(buildPrompt("Asha", stats).includes("Asha"));

console.log("All function tests passed ✔");
console.log(JSON.stringify(r, null, 2));
