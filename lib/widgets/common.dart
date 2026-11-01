import 'package:flutter/material.dart';

import '../models/daily_log.dart';

class SectionCard extends StatelessWidget {
  const SectionCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(18),
      this.color});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(children: [
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.message,
      this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Icon(icon, size: 40, color: t.colorScheme.primary),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: t.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(message,
            textAlign: TextAlign.center,
            style: t.textTheme.bodyMedium
                ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// Shows ▲/▼ and the change between two averages, coloured by whether the
/// change is good for this metric (less workload is good).
class TrendBadge extends StatelessWidget {
  const TrendBadge(
      {super.key,
      required this.metric,
      required this.current,
      required this.previous});

  final Metric metric;
  final double? current;
  final double? previous;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (current == null || previous == null) {
      return Text('—', style: TextStyle(color: cs.onSurfaceVariant));
    }
    final delta = current! - previous!;
    if (delta.abs() < 0.05) {
      return Text('steady', style: TextStyle(color: cs.onSurfaceVariant));
    }
    final good = metric.higherIsBetter ? delta > 0 : delta < 0;
    final color = good ? const Color(0xFF2E9E5B) : cs.error;
    final digits = metric == Metric.activity ? 0 : 1;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(delta > 0 ? Icons.arrow_upward : Icons.arrow_downward,
          size: 14, color: color),
      Text(delta.abs().toStringAsFixed(digits),
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    ]);
  }
}

class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.score, this.size = 84});
  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 8,
            strokeCap: StrokeCap.round,
            backgroundColor: cs.surfaceContainerHighest,
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$score',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text('score',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ]),
      ]),
    );
  }
}

class MetricChip extends StatelessWidget {
  const MetricChip({super.key, required this.metric, required this.value});
  final Metric metric;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: metric.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(metric.icon, size: 16, color: metric.color),
        const SizedBox(width: 6),
        Text(metric.format(value),
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
