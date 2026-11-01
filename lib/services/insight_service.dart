import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/daily_log.dart';
import 'analytics.dart';
import 'log_repository.dart';
import 'notification_service.dart';

/// Generates the weekly AI reflection with Gemini through **Firebase AI Logic**
/// (Gemini Developer API — free tier, works on the Spark plan).
///
/// Flow: compute stats from the user's own logs (pure Dart) → build a prompt →
/// Gemini returns structured JSON → save to Firestore → the Insights screen
/// updates live. No API key is stored in the app: Firebase AI Logic proxies the
/// request using the project's Firebase configuration.
///
/// If the AI call fails (offline, quota, model retired) a rule-based reflection
/// is built from the same stats, so the feature never breaks during a demo.
class InsightService {
  InsightService._();
  static final instance = InsightService._();

  /// Tried in order; if Google retires one model name the next is used.
  static const _models = ['gemini-3.5-flash-lite', 'gemini-3.8-flash', 'gemini-3.5-flash'];

  DateTime? _lastRun;

  Future<void> generateWeeklyReflection({
    required LogRepository repo,
    required List<DailyLog> logs,
    String? name,
  }) async {
    if (_lastRun != null &&
        DateTime.now().difference(_lastRun!) < const Duration(seconds: 20)) {
      throw InsightException('Please wait a few seconds before regenerating.');
    }

    final stats = WeeklyStats.from(logs);
    if (stats.daysThisWeek < 3) {
      throw InsightException(
          'Log at least 3 days this week to get a reflection (you have ${stats.daysThisWeek}).');
    }
    _lastRun = DateTime.now();

    Map<String, dynamic>? reflection;
    var source = 'gemini';
    try {
      reflection = await _askGemini(_buildPrompt(name, stats));
    } catch (e) {
      debugPrint('Gemini failed, using rule-based fallback: $e');
    }
    if (reflection == null) {
      reflection = _ruleBased(stats);
      source = 'rules';
    }

    final id = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await repo.userDoc.collection('reflections').doc(id).set({
      'headline': reflection['headline'],
      'summary': reflection['summary'],
      'trends': reflection['trends'],
      'suggestions': reflection['suggestions'],
      'source': source,
      'daysLogged': stats.daysThisWeek,
      'createdAt': FieldValue.serverTimestamp(),
    });

    NotificationService.instance
        .showNow('Your weekly reflection is ready ✨', '${reflection['headline']}');
  }

  // ------------------------------------------------------------------ Gemini

  Future<Map<String, dynamic>> _askGemini(String prompt) async {
    Object? lastError;
    for (final name in _models) {
      try {
        final model = FirebaseAI.googleAI().generativeModel(
          model: name,
          generationConfig: GenerationConfig(
            temperature: 0.7,
            responseMimeType: 'application/json',
            responseSchema: Schema.object(properties: {
              'headline': Schema.string(),
              'summary': Schema.string(),
              'trends': Schema.array(items: Schema.string()),
              'suggestions': Schema.array(items: Schema.string()),
            }),
          ),
        );
        final res = await model
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 60));
        final text = res.text;
        if (text == null || text.isEmpty) throw Exception('Empty response');
        final json = jsonDecode(text) as Map<String, dynamic>;
        return {
          'headline': (json['headline'] ?? 'Your week in review').toString(),
          'summary': (json['summary'] ?? '').toString(),
          'trends': ((json['trends'] as List?) ?? []).map((e) => e.toString()).take(4).toList(),
          'suggestions':
              ((json['suggestions'] as List?) ?? []).map((e) => e.toString()).take(3).toList(),
        };
      } catch (e) {
        lastError = e;
        debugPrint('Model $name failed: $e');
      }
    }
    throw Exception('All Gemini models failed: $lastError');
  }

  String _buildPrompt(String? name, WeeklyStats s) {
    final lines = s.metrics.map((m) {
      final cur = m.current == null ? 'n/a' : m.metric.format(m.current!);
      final prev = m.previous == null ? '' : ', last week ${m.metric.format(m.previous!)}';
      final note = m.metric.higherIsBetter ? '' : ' [lower is better]';
      return '- ${m.metric.label}: this week $cur$prev$note';
    }).join('\n');
    final corr = s.correlations.isEmpty
        ? '- none strong enough yet'
        : s.correlations
            .map((c) => '- ${c.a.label} & ${c.b.label}: r=${c.r.toStringAsFixed(2)}')
            .join('\n');
    final notes = s.notes.isEmpty ? 'none' : s.notes.map((n) => '"$n"').join('; ');

    return '''You are MindMirror, a warm, insightful wellbeing coach inside a habit-tracking app.
Write a weekly reflection for ${name == null || name.isEmpty ? 'the user' : name} based ONLY on the data below.

Days logged: ${s.daysThisWeek} this week, ${s.daysLastWeek} last week.
Weekly averages:
$lines
Correlations over the last 30 days (Pearson r, |r| >= 0.3):
$corr
Most productive day this week: ${s.bestDay ?? 'n/a'}
User's own notes this week: $notes

Rules:
- Speak directly to the user ("you"), encouraging but honest. Reference specific numbers.
- Correlation is not causation: say "tends to" or "seems linked", never claim certainty.
- No medical or clinical diagnosis. If average mood is below 3, gently suggest talking to someone they trust.
- headline: max 8 words. summary: 2-3 sentences, max 70 words.
- trends: exactly 3 short observations. suggestions: exactly 2 small, concrete actions for next week.''';
  }

  // ------------------------------------------------------------------ fallback

  Map<String, dynamic> _ruleBased(WeeklyStats s) {
    final changed = s.metrics.where((m) => m.change != null && m.change!.abs() >= 0.1).toList()
      ..sort((a, b) => b.change!.abs().compareTo(a.change!.abs()));
    String fmt(MetricStat m) =>
        '${m.metric.label} ${m.change! > 0 ? 'rose' : 'fell'} to ${m.metric.format(m.current!)}';
    final top = changed.isEmpty ? null : changed.first;
    final good = top != null &&
        (top.metric.higherIsBetter ? top.change! > 0 : top.change! < 0);
    return {
      'headline': top == null
          ? 'Your week in review'
          : 'Your ${top.metric.label.toLowerCase()} ${good ? 'improved' : 'slipped'} this week',
      'summary': 'You logged ${s.daysThisWeek} days this week.'
          '${top == null ? '' : ' The biggest shift: ${fmt(top).toLowerCase()}.'}'
          '${s.bestDay == null ? '' : ' Your most productive day was ${s.bestDay}.'}',
      'trends': changed.take(3).map(fmt).toList(),
      'suggestions': s.correlations.isEmpty
          ? ['Keep logging daily so stronger patterns can emerge.']
          : s.correlations
              .take(2)
              .map((c) => 'Your ${c.a.label.toLowerCase()} and ${c.b.label.toLowerCase()} '
                  'seem ${c.r > 0 ? 'to rise together' : 'to move in opposite directions'} '
                  '— experiment with that this week.')
              .toList(),
    };
  }
}

// -------------------------------------------------------------------- stats

class MetricStat {
  MetricStat(this.metric, this.current, this.previous);
  final Metric metric;
  final double? current;
  final double? previous;
  double? get change =>
      current == null || previous == null ? null : current! - previous!;
}

class WeeklyStats {
  WeeklyStats._(this.daysThisWeek, this.daysLastWeek, this.metrics,
      this.correlations, this.bestDay, this.notes);

  final int daysThisWeek;
  final int daysLastWeek;
  final List<MetricStat> metrics;
  final List<Correlation> correlations;
  final String? bestDay;
  final List<String> notes;

  factory WeeklyStats.from(List<DailyLog> logs) {
    final week = Analytics.lastNDays(logs, 7);
    final prev = Analytics.previousNDays(logs, 7);
    final month = Analytics.lastNDays(logs, 30);
    final best = week.isEmpty
        ? null
        : week.reduce((a, b) => a.productivity >= b.productivity ? a : b);
    return WeeklyStats._(
      week.length,
      prev.length,
      [
        for (final m in Metric.values)
          MetricStat(m, Analytics.average(week, m), Analytics.average(prev, m))
      ],
      Analytics.correlations(month).where((c) => c.r.abs() >= 0.3).take(4).toList(),
      best == null
          ? null
          : '${DateFormat('EEEE').format(best.date)} (${best.productivity}/10)',
      week.map((l) => l.note).where((n) => n.isNotEmpty).toList(),
    );
  }
}

class InsightException implements Exception {
  InsightException(this.message);
  final String message;
  @override
  String toString() => message;
}
