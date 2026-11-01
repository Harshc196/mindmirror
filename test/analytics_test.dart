import 'package:flutter_test/flutter_test.dart';
import 'package:mindmirror/models/daily_log.dart';
import 'package:mindmirror/services/analytics.dart';

DailyLog log(DateTime d,
        {double sleep = 7, int mood = 6, int energy = 6, int prod = 6,
        int work = 5, int act = 30}) =>
    DailyLog(
        date: d,
        sleepHours: sleep,
        mood: mood,
        energy: energy,
        productivity: prod,
        workload: work,
        activityMinutes: act);

void main() {
  final today = DateTime(2026, 10, 16);

  test('pearson detects perfect positive and negative relationships', () {
    expect(Analytics.pearson([1, 2, 3, 4, 5], [2, 4, 6, 8, 10]), closeTo(1, 1e-9));
    expect(Analytics.pearson([1, 2, 3, 4, 5], [5, 4, 3, 2, 1]), closeTo(-1, 1e-9));
    expect(Analytics.pearson([3, 3, 3], [1, 2, 3]), isNull); // no variation
  });

  test('streak counts consecutive days, tolerating an unlogged today', () {
    final logs = [for (var i = 1; i <= 4; i++) log(dayOffset(today, -i))];
    expect(Analytics.streak(logs, today: today), 4);
    expect(Analytics.streak([...logs, log(today)], today: today), 5);
  });

  test('week windows do not overlap', () {
    final logs = [for (var i = 0; i < 14; i++) log(dayOffset(today, -i))];
    expect(Analytics.lastNDays(logs, 7, today: today).length, 7);
    expect(Analytics.previousNDays(logs, 7, today: today).length, 7);
  });

  test('sleep→productivity highlight appears when the pattern exists', () {
    final logs = [
      for (var i = 0; i < 10; i++)
        log(dayOffset(today, -i),
            sleep: i.isEven ? 8 : 5, prod: i.isEven ? 8 : 4),
    ];
    final h = Analytics.highlights(logs);
    expect(h.any((x) => x.text.contains('productivity')), isTrue);
    final c = Analytics.correlate(logs, Metric.sleep, Metric.productivity)!;
    expect(c.r, greaterThan(0.9));
    expect(c.strength, 'Strong');
  });

  test('day score stays in 0–100', () {
    expect(Analytics.dayScore(log(today, mood: 10, energy: 10, prod: 10, sleep: 8, act: 60, work: 1)),
        inInclusiveRange(90, 100));
    expect(Analytics.dayScore(log(today, mood: 1, energy: 1, prod: 1, sleep: 0, act: 0, work: 10)),
        inInclusiveRange(0, 20));
  });
}
