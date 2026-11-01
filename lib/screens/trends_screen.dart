import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/daily_log.dart';
import '../services/analytics.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key, required this.logs, required this.onEdit});
  final List<DailyLog> logs;
  final void Function([DateTime? date]) onEdit;

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  final Set<Metric> _selected = {Metric.sleep, Metric.mood, Metric.productivity};
  int _days = 14;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final range = Analytics.lastNDays(widget.logs, _days);
    final metrics = Metric.values.where(_selected.contains).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Text('Trends',
            style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 days')),
            ButtonSegment(value: 14, label: Text('14 days')),
            ButtonSegment(value: 30, label: Text('30 days')),
          ],
          selected: {_days},
          onSelectionChanged: (s) => setState(() => _days = s.first),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final m in Metric.values)
            FilterChip(
              avatar: Icon(m.icon, size: 18, color: m.color),
              label: Text(m.label),
              selected: _selected.contains(m),
              onSelected: (on) => setState(() {
                if (on) {
                  _selected.add(m);
                } else if (_selected.length > 1) {
                  _selected.remove(m);
                }
              }),
            ),
        ]),
        const SizedBox(height: 12),
        if (range.length < 2)
          const EmptyState(
            icon: Icons.show_chart,
            title: 'Not enough data yet',
            message: 'Log at least two days in this range to see a trend line.',
          )
        else
          SectionCard(
            padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
            child: Column(children: [
              SizedBox(
                height: 240,
                child: MultiMetricLineChart(
                    logs: range, metrics: metrics, days: _days),
              ),
              const SizedBox(height: 4),
              Text('All factors scaled to 0–10 · tap the chart for real values',
                  style: TextStyle(
                      fontSize: 11, color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
        const SectionTitle('Averages in this range'),
        SectionCard(
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in Metric.values)
              if (Analytics.average(range, m) != null)
                MetricChip(metric: m, value: Analytics.average(range, m)!),
            if (range.isEmpty) const Text('No check-ins in this range.'),
          ]),
        ),
        SectionTitle('History', trailing: Text('${widget.logs.length} days')),
        for (final l in widget.logs.reversed.take(30))
          Card(
            elevation: 0,
            color: t.colorScheme.surfaceContainerLow,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              onTap: () => widget.onEdit(l.date),
              title: Text(DateFormat('EEE, d MMM').format(l.date),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Sleep ${Metric.sleep.format(l.sleepHours)} · '
                'Mood ${l.mood} · Prod ${l.productivity}'
                '${l.note.isEmpty ? '' : '\n“${l.note}”'}',
              ),
              isThreeLine: l.note.isNotEmpty,
              trailing: CircleAvatar(
                backgroundColor: t.colorScheme.primaryContainer,
                child: Text('${Analytics.dayScore(l)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: t.colorScheme.onPrimaryContainer)),
              ),
            ),
          ),
      ],
    );
  }
}
