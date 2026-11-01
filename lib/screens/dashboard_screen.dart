import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/daily_log.dart';
import '../services/analytics.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen(
      {super.key, required this.user, required this.logs, required this.onLog});

  final User user;
  final List<DailyLog> logs;
  final void Function([DateTime? date]) onLog;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final todayLog = logs.where((l) => l.date == today).firstOrNull;
    final week = Analytics.lastNDays(logs, 7);
    final prevWeek = Analytics.previousNDays(logs, 7);
    final streak = Analytics.streak(logs);
    final highlights = Analytics.highlights(Analytics.lastNDays(logs, 30));
    final name = (user.displayName ?? '').split(' ').first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Text(DateFormat('EEEE, d MMMM').format(today),
            style: t.textTheme.labelLarge
                ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(name.isEmpty ? _greeting : '$_greeting, $name',
            style: t.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          Chip(
            avatar: const Icon(Icons.local_fire_department,
                size: 18, color: Colors.deepOrange),
            label: Text('$streak-day streak'),
          ),
          Chip(
            avatar: const Icon(Icons.event_available, size: 18),
            label: Text('${week.length}/7 days this week'),
          ),
        ]),
        const SizedBox(height: 8),
        _TodayCard(log: todayLog, onLog: () => onLog(today)),
        if (logs.isEmpty) ...[
          const SizedBox(height: 16),
          const EmptyState(
            icon: Icons.insights,
            title: 'Your patterns will appear here',
            message:
                'Check in daily for a few days. Want to explore right away? '
                'Load sample data from the Profile tab.',
          ),
        ] else ...[
          const SectionTitle('This week vs last week'),
          SectionCard(
            child: Column(children: [
              for (final m in Metric.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(m.icon, color: m.color, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(m.label)),
                    Text(
                      Analytics.average(week, m) == null
                          ? '—'
                          : m.format(Analytics.average(week, m)!),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 56,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TrendBadge(
                          metric: m,
                          current: Analytics.average(week, m),
                          previous: Analytics.average(prevWeek, m),
                        ),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
          if (week.length >= 2) ...[
            const SectionTitle('Productivity · last 7 days'),
            SectionCard(
              child: SizedBox(
                  height: 90,
                  child: Sparkline(logs: week, metric: Metric.productivity)),
            ),
          ],
          if (highlights.isNotEmpty) ...[
            const SectionTitle('Pattern spotted'),
            SectionCard(
              color: t.colorScheme.primaryContainer,
              child: Row(children: [
                Icon(highlights.first.icon,
                    color: t.colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(highlights.first.text,
                      style: TextStyle(color: t.colorScheme.onPrimaryContainer)),
                ),
              ]),
            ),
          ],
        ],
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.log, required this.onLog});
  final DailyLog? log;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (log == null) {
      return SectionCard(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('How was today?',
                  style: t.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('A 30-second check-in keeps your insights accurate.',
                  style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: onLog, child: const Text('Log today')),
        ]),
      );
    }
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Today is logged ✓',
                  style: t.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Your day score combines all six factors.',
                  style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
              TextButton.icon(
                onPressed: onLog,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ]),
          ),
          ScoreRing(score: Analytics.dayScore(log!)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in Metric.values) MetricChip(metric: m, value: log!.valueOf(m)),
        ]),
      ]),
    );
  }
}
