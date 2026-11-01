import 'dart:math';

import 'package:flutter/material.dart';

import '../models/daily_log.dart';

/// A Pearson correlation between two tracked factors.
class Correlation {
  const Correlation(this.a, this.b, this.r, this.n);

  final Metric a;
  final Metric b;
  final double r; // -1 … +1
  final int n; // number of days used

  String get strength {
    final v = r.abs();
    if (v >= 0.7) return 'Strong';
    if (v >= 0.4) return 'Moderate';
    if (v >= 0.2) return 'Weak';
    return 'No clear';
  }

  String get sentence {
    final x = a.label.toLowerCase(), y = b.label.toLowerCase();
    if (r.abs() < 0.2) return 'No clear link between $x and $y yet.';
    return 'When your $x is higher, your $y tends to be ${r > 0 ? 'higher' : 'lower'}.';
  }
}

/// A plain-language finding computed from the user's own data.
class Highlight {
  const Highlight(this.text, this.icon, {required this.positive, this.size = 0});
  final String text;
  final IconData icon;
  final bool positive;
  final double size; // magnitude, used for ranking
}

/// Pure functions — no Firebase here, so they are easy to unit test.
class Analytics {
  Analytics._();

  static double? pearson(List<double> x, List<double> y) {
    final n = x.length;
    if (n < 3 || n != y.length) return null;
    final mx = x.reduce((a, b) => a + b) / n;
    final my = y.reduce((a, b) => a + b) / n;
    double sxy = 0, sxx = 0, syy = 0;
    for (var i = 0; i < n; i++) {
      final dx = x[i] - mx, dy = y[i] - my;
      sxy += dx * dy;
      sxx += dx * dx;
      syy += dy * dy;
    }
    if (sxx == 0 || syy == 0) return null; // a factor never changed
    return sxy / sqrt(sxx * syy);
  }

  static Correlation? correlate(List<DailyLog> logs, Metric a, Metric b) {
    final r = pearson(logs.map((l) => l.valueOf(a)).toList(),
        logs.map((l) => l.valueOf(b)).toList());
    return r == null ? null : Correlation(a, b, r, logs.length);
  }

  /// Every pair of factors, strongest relationship first.
  static List<Correlation> correlations(List<DailyLog> logs,
      {int minDays = 5}) {
    if (logs.length < minDays) return [];
    final out = <Correlation>[];
    const ms = Metric.values;
    for (var i = 0; i < ms.length; i++) {
      for (var j = i + 1; j < ms.length; j++) {
        final c = correlate(logs, ms[i], ms[j]);
        if (c != null) out.add(c);
      }
    }
    out.sort((p, q) => q.r.abs().compareTo(p.r.abs()));
    return out;
  }

  static double? average(Iterable<DailyLog> logs, Metric m) {
    if (logs.isEmpty) return null;
    return logs.map((l) => l.valueOf(m)).reduce((a, b) => a + b) / logs.length;
  }

  static DateTime _today(DateTime? t) => DateUtils.dateOnly(t ?? DateTime.now());

  /// Logs from the last [n] days, including today.
  static List<DailyLog> lastNDays(List<DailyLog> logs, int n,
      {DateTime? today}) {
    final t = _today(today);
    final from = dayOffset(t, -(n - 1));
    return logs
        .where((l) => !l.date.isBefore(from) && !l.date.isAfter(t))
        .toList();
  }

  /// The [n]-day window immediately before [lastNDays].
  static List<DailyLog> previousNDays(List<DailyLog> logs, int n,
      {DateTime? today}) {
    final t = _today(today);
    final from = dayOffset(t, -(2 * n - 1));
    final to = dayOffset(t, -n);
    return logs
        .where((l) => !l.date.isBefore(from) && !l.date.isAfter(to))
        .toList();
  }

  /// Consecutive logged days ending today (or yesterday if today isn't logged yet).
  static int streak(List<DailyLog> logs, {DateTime? today}) {
    final days = logs.map((l) => l.date).toSet();
    var d = _today(today);
    if (!days.contains(d)) d = dayOffset(d, -1);
    var count = 0;
    while (days.contains(d)) {
      count++;
      d = dayOffset(d, -1);
    }
    return count;
  }

  /// A 0–100 composite "day score". Workload is inverted, sleep peaks at 8h.
  static int dayScore(DailyLog l) {
    final sleep = (10 - (l.sleepHours - 8).abs() * 2.5).clamp(0, 10);
    final activity = (l.activityMinutes / 45 * 10).clamp(0, 10);
    final workload = 11 - l.workload;
    final score = l.mood * 0.30 +
        l.energy * 0.20 +
        l.productivity * 0.20 +
        sleep * 0.15 +
        activity * 0.10 +
        workload * 0.05;
    return (score * 10).round().clamp(0, 100).toInt();
  }

  /// Splits days by [test] and compares the average [outcome] in each group.
  static (double, double)? _split(
      List<DailyLog> logs, bool Function(DailyLog) test, Metric outcome) {
    final yes = logs.where(test).toList();
    final no = logs.where((l) => !test(l)).toList();
    if (yes.length < 3 || no.length < 3) return null;
    return (average(yes, outcome)!, average(no, outcome)!);
  }

  static List<Highlight> highlights(List<DailyLog> logs) {
    final out = <Highlight>[];
    String f(double v) => v.toStringAsFixed(1);

    void compare(String condition, bool Function(DailyLog) test,
        Metric outcome, IconData icon) {
      final s = _split(logs, test, outcome);
      if (s == null) return;
      final (a, b) = s;
      final diff = a - b;
      if (diff.abs() < 0.5) return;
      final better = outcome.higherIsBetter ? diff > 0 : diff < 0;
      out.add(Highlight(
        'On days $condition, your ${outcome.label.toLowerCase()} averages '
        '${f(a)} vs ${f(b)} otherwise.',
        icon,
        positive: better,
        size: diff.abs(),
      ));
    }

    compare('with 7h+ sleep', (l) => l.sleepHours >= 7, Metric.productivity,
        Icons.bedtime_outlined);
    compare('with 7h+ sleep', (l) => l.sleepHours >= 7, Metric.energy,
        Icons.bolt);
    compare('with 30+ min of activity', (l) => l.activityMinutes >= 30,
        Metric.mood, Icons.directions_run);
    compare('with heavy workload (7+)', (l) => l.workload >= 7, Metric.mood,
        Icons.work_outline);

    // Best weekday for productivity (needs at least 2 weeks of data).
    if (logs.length >= 14) {
      final byDay = <int, List<DailyLog>>{};
      for (final l in logs) {
        byDay.putIfAbsent(l.date.weekday, () => []).add(l);
      }
      byDay.removeWhere((_, v) => v.length < 2);
      if (byDay.length >= 3) {
        final best = byDay.entries.reduce((a, b) =>
            average(a.value, Metric.productivity)! >=
                    average(b.value, Metric.productivity)!
                ? a
                : b);
        const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday',
            'Friday', 'Saturday', 'Sunday'];
        out.add(Highlight(
          '${names[best.key - 1]} is your most productive day '
          '(avg ${f(average(best.value, Metric.productivity)!)}/10).',
          Icons.calendar_today_outlined,
          positive: true,
          size: 0.4,
        ));
      }
    }

    out.sort((a, b) => b.size.compareTo(a.size));
    return out;
  }
}
