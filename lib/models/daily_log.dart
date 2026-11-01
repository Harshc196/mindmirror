import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Returns the calendar day [n] days after [d] (DST-safe, unlike Duration).
DateTime dayOffset(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Every factor the user tracks. Keeping all metadata in one enum means the
/// sliders, charts and analytics stay consistent automatically.
enum Metric {
  sleep('Sleep', Icons.bedtime_outlined, Color(0xFF5C6BC0), 0, 12, 24),
  mood('Mood', Icons.sentiment_satisfied_alt, Color(0xFFEC407A), 1, 10, 9),
  energy('Energy', Icons.bolt, Color(0xFFFFA000), 1, 10, 9),
  productivity('Productivity', Icons.task_alt, Color(0xFF26A69A), 1, 10, 9),
  workload('Workload', Icons.work_outline, Color(0xFF8D6E63), 1, 10, 9,
      higherIsBetter: false),
  activity('Activity', Icons.directions_run, Color(0xFF66BB6A), 0, 180, 36);

  const Metric(this.label, this.icon, this.color, this.min, this.max,
      this.divisions,
      {this.higherIsBetter = true});

  final String label;
  final IconData icon;
  final Color color;
  final double min;
  final double max;
  final int divisions;

  /// Workload is the only metric where "more" is not "better".
  final bool higherIsBetter;

  String format(double v) => switch (this) {
        Metric.sleep => '${v.toStringAsFixed(1)} h',
        Metric.activity => '${v.round()} min',
        _ => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)}/10',
      };

  /// Scales any metric to 0–10 so different units can share one chart.
  double normalize(double v) => (v / max * 10).clamp(0, 10).toDouble();
  double denormalize(double y) => y * max / 10;
}

/// One check-in per calendar day. The Firestore document id is the date
/// (yyyy-MM-dd), so saving twice on the same day updates instead of duplicating.
class DailyLog {
  DailyLog({
    required DateTime date,
    required this.sleepHours,
    required this.mood,
    required this.energy,
    required this.productivity,
    required this.workload,
    required this.activityMinutes,
    this.note = '',
  }) : date = DateUtils.dateOnly(date);

  final DateTime date;
  final double sleepHours;
  final int mood;
  final int energy;
  final int productivity;
  final int workload;
  final int activityMinutes;
  final String note;

  static String idFor(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String get id => idFor(date);

  double valueOf(Metric m) => switch (m) {
        Metric.sleep => sleepHours,
        Metric.mood => mood.toDouble(),
        Metric.energy => energy.toDouble(),
        Metric.productivity => productivity.toDouble(),
        Metric.workload => workload.toDouble(),
        Metric.activity => activityMinutes.toDouble(),
      };

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(date),
        'sleepHours': sleepHours,
        'mood': mood,
        'energy': energy,
        'productivity': productivity,
        'workload': workload,
        'activityMinutes': activityMinutes,
        'note': note,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory DailyLog.fromMap(Map<String, dynamic> m) => DailyLog(
        date: (m['date'] as Timestamp).toDate(),
        sleepHours: (m['sleepHours'] as num).toDouble(),
        mood: (m['mood'] as num).toInt(),
        energy: (m['energy'] as num).toInt(),
        productivity: (m['productivity'] as num).toInt(),
        workload: (m['workload'] as num).toInt(),
        activityMinutes: (m['activityMinutes'] as num).toInt(),
        note: (m['note'] ?? '') as String,
      );
}
