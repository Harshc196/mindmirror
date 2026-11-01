import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/daily_log.dart';
import '../services/analytics.dart';

/// Several factors on one timeline. Every metric is scaled to 0–10 so sleep
/// (hours) and activity (minutes) can share an axis; tooltips show real values.
class MultiMetricLineChart extends StatelessWidget {
  const MultiMetricLineChart(
      {super.key,
      required this.logs,
      required this.metrics,
      required this.days});

  final List<DailyLog> logs;
  final List<Metric> metrics;
  final int days;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final start = dayOffset(DateUtils.dateOnly(DateTime.now()), -(days - 1));
    double xOf(DateTime d) => d.difference(start).inHours / 24.0;

    final shown = metrics.where((_) => logs.isNotEmpty).toList();
    final bars = shown
        .map((m) => LineChartBarData(
              spots: logs
                  .map((l) => FlSpot(
                      xOf(l.date).roundToDouble(), m.normalize(l.valueOf(m))))
                  .toList(),
              isCurved: true,
              preventCurveOverShooting: true,
              color: m.color,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(show: days <= 14),
            ))
        .toList();

    final interval = (days / 6).ceilToDouble();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (days - 1).toDouble(),
        minY: 0,
        maxY: 10,
        lineBarsData: bars,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 2.5,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: cs.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: interval,
              getTitlesWidget: (value, meta) {
                if (value != value.roundToDouble()) return const SizedBox();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    DateFormat('d MMM').format(dayOffset(start, value.toInt())),
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (spots) => spots.map((s) {
              final m = shown[s.barIndex];
              return LineTooltipItem(
                '${m.label}: ${m.format(m.denormalize(s.y))}',
                TextStyle(
                    color: cs.onInverseSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// A tiny chart for the dashboard.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.logs, required this.metric});
  final List<DailyLog> logs;
  final Metric metric;

  @override
  Widget build(BuildContext context) {
    if (logs.length < 2) return const SizedBox();
    return LineChart(LineChartData(
      minY: metric.min,
      maxY: metric.max,
      lineTouchData: LineTouchData(enabled: false),
      gridData: FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < logs.length; i++)
              FlSpot(i.toDouble(), logs[i].valueOf(metric))
          ],
          isCurved: true,
          preventCurveOverShooting: true,
          color: metric.color,
          barWidth: 3,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: metric.color.withValues(alpha: 0.15),
          ),
        ),
      ],
    ));
  }
}

/// One dot per day: does factor X move with factor Y?
class CorrelationScatter extends StatelessWidget {
  const CorrelationScatter(
      {super.key, required this.logs, required this.x, required this.y});
  final List<DailyLog> logs;
  final Metric x;
  final Metric y;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = Analytics.correlate(logs, x, y)?.r ?? 0;
    final color = r >= 0 ? const Color(0xFF2E9E5B) : cs.error;
    TextStyle small = TextStyle(fontSize: 10, color: cs.onSurfaceVariant);

    AxisTitles axis(Metric m) => AxisTitles(
          axisNameWidget: Text(m.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          axisNameSize: 20,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: (m.max - m.min) / 4,
            getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta, child: Text(v.round().toString(), style: small)),
          ),
        );

    return ScatterChart(ScatterChartData(
      minX: x.min,
      maxX: x.max,
      minY: y.min,
      maxY: y.max,
      scatterSpots: logs
          .map((l) => ScatterSpot(
                l.valueOf(x),
                l.valueOf(y),
                dotPainter: FlDotCirclePainter(
                    radius: 6, color: color.withValues(alpha: 0.55)),
              ))
          .toList(),
      scatterTouchData: ScatterTouchData(enabled: false),
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        getDrawingHorizontalLine: (_) =>
            FlLine(color: cs.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
        getDrawingVerticalLine: (_) =>
            FlLine(color: cs.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: axis(x),
        leftTitles: axis(y),
      ),
    ));
  }
}
