import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/daily_log.dart';
import '../services/analytics.dart';
import '../services/insight_service.dart';
import '../services/log_repository.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.logs, required this.repo});
  final List<DailyLog> logs;
  final LogRepository repo;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late final Stream<Map<String, dynamic>?> _reflection =
      widget.repo.watchLatestReflection();
  Metric _x = Metric.sleep;
  Metric _y = Metric.productivity;
  bool _generating = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      await InsightService.instance.generateWeeklyReflection(
        repo: widget.repo,
        logs: widget.logs,
        name: FirebaseAuth.instance.currentUser?.displayName,
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final month = Analytics.lastNDays(widget.logs, 30);
    final correlations = Analytics.correlations(month)
        .where((c) => c.r.abs() >= 0.2)
        .take(5)
        .toList();
    final highlights = Analytics.highlights(month);
    final pair = Analytics.correlate(month, _x, _y);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Text('Insights',
            style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text('Based on your last 30 days · ${month.length} check-ins',
            style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),

        // ---------- AI weekly reflection ----------
        StreamBuilder<Map<String, dynamic>?>(
          stream: _reflection,
          builder: (context, snap) => _ReflectionCard(
            data: snap.data,
            generating: _generating,
            error: _error,
            onGenerate: _generate,
          ),
        ),

        if (month.length < 5) ...[
          const SizedBox(height: 16),
          const EmptyState(
            icon: Icons.hourglass_bottom,
            title: 'Patterns need a few days',
            message:
                'Correlations appear after 5 check-ins. Keep logging, or load '
                'sample data from Profile to explore.',
          ),
        ] else ...[
          if (highlights.isNotEmpty) ...[
            const SectionTitle('What your data says'),
            for (final h in highlights.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SectionCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: (h.positive
                              ? const Color(0xFF2E9E5B)
                              : t.colorScheme.error)
                          .withValues(alpha: 0.15),
                      child: Icon(h.icon,
                          color: h.positive
                              ? const Color(0xFF2E9E5B)
                              : t.colorScheme.error),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(h.text)),
                  ]),
                ),
              ),
          ],
          const SectionTitle('Strongest connections'),
          SectionCard(
            child: correlations.isEmpty
                ? const Text('No strong connections yet — your factors move independently.')
                : Column(children: [
                    for (final c in correlations)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() {
                          _x = c.a;
                          _y = c.b;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: _CorrelationRow(c: c),
                        ),
                      ),
                  ]),
          ),
          const SectionTitle('Explore any two factors'),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
            child: Column(children: [
              Row(children: [
                Expanded(child: _metricDropdown('X axis', _x, (m) => setState(() => _x = m))),
                const SizedBox(width: 8),
                Expanded(child: _metricDropdown('Y axis', _y, (m) => setState(() => _y = m))),
              ]),
              const SizedBox(height: 16),
              SizedBox(height: 240, child: CorrelationScatter(logs: month, x: _x, y: _y)),
              const SizedBox(height: 8),
              if (_x == _y)
                const Text('Pick two different factors.')
              else if (pair != null)
                Text('${pair.strength} ${pair.r >= 0 ? 'positive' : 'negative'} '
                    'link (r = ${pair.r.toStringAsFixed(2)}). ${pair.sentence}',
                    textAlign: TextAlign.center),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Correlation shows things that move together — not proof that one causes the other.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metricDropdown(String label, Metric value, ValueChanged<Metric> onChanged) {
    return DropdownButtonFormField<Metric>(
      initialValue: value,
      key: ValueKey('$label-$value'),
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final m in Metric.values)
          DropdownMenuItem(value: m, child: Text(m.label)),
      ],
      onChanged: (m) {
        if (m != null) onChanged(m);
      },
    );
  }
}

class _CorrelationRow extends StatelessWidget {
  const _CorrelationRow({required this.c});
  final Correlation c;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = c.r >= 0 ? const Color(0xFF2E9E5B) : cs.error;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(c.a.icon, size: 18, color: c.a.color),
        Icon(c.r >= 0 ? Icons.trending_up : Icons.trending_down, size: 18, color: color),
        Icon(c.b.icon, size: 18, color: c.b.color),
        const SizedBox(width: 8),
        Expanded(
          child: Text('${c.a.label} & ${c.b.label}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Text('r = ${c.r.toStringAsFixed(2)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: c.r.abs(),
          minHeight: 6,
          color: color,
          backgroundColor: cs.surfaceContainerHighest,
        ),
      ),
      const SizedBox(height: 4),
      Text('${c.strength} · ${c.sentence}',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    ]);
  }
}

class _ReflectionCard extends StatelessWidget {
  const _ReflectionCard({
    required this.data,
    required this.generating,
    required this.error,
    required this.onGenerate,
  });

  final Map<String, dynamic>? data;
  final bool generating;
  final String? error;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final on = t.colorScheme.onSecondaryContainer;
    final created = (data?['createdAt'] as Timestamp?)?.toDate();
    List<String> list(String k) =>
        ((data?[k] as List?) ?? []).map((e) => e.toString()).toList();

    return SectionCard(
      color: t.colorScheme.secondaryContainer,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome, color: on),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Weekly AI reflection',
                style: t.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: on)),
          ),
          if (created != null)
            Text(DateFormat('d MMM, h:mm a').format(created),
                style: TextStyle(fontSize: 11, color: on)),
        ]),
        const SizedBox(height: 12),
        if (data == null)
          Text(
            'Get a personal summary of your week — what changed, what seems '
            'to help, and one or two ideas to try.',
            style: TextStyle(color: on),
          )
        else ...[
          Text(data!['headline']?.toString() ?? '',
              style: t.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, color: on)),
          const SizedBox(height: 8),
          Text(data!['summary']?.toString() ?? '', style: TextStyle(color: on, height: 1.4)),
          if (list('trends').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Trends', style: TextStyle(fontWeight: FontWeight.w700, color: on)),
            for (final s in list('trends')) _bullet(s, Icons.insights, on),
          ],
          if (list('suggestions').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Try this week', style: TextStyle(fontWeight: FontWeight.w700, color: on)),
            for (final s in list('suggestions')) _bullet(s, Icons.lightbulb_outline, on),
          ],
          if (data!['source'] == 'rules')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Generated from your stats (AI service was unavailable).',
                  style: TextStyle(fontSize: 11, color: on)),
            ),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: TextStyle(color: t.colorScheme.error)),
        ],
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          onPressed: generating ? null : onGenerate,
          icon: generating
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          label: Text(generating
              ? 'Reflecting on your week…'
              : data == null
                  ? 'Generate my reflection'
                  : 'Regenerate'),
        ),
      ]),
    );
  }

  Widget _bullet(String s, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(s, style: TextStyle(color: color, height: 1.35))),
        ]),
      );
}
