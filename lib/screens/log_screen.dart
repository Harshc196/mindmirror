import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/daily_log.dart';
import '../services/log_repository.dart';
import '../widgets/common.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key, required this.repo, required this.initialDate});
  final LogRepository repo;
  final DateTime initialDate;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  static const _defaults = {
    Metric.sleep: 7.0,
    Metric.mood: 6.0,
    Metric.energy: 6.0,
    Metric.productivity: 6.0,
    Metric.workload: 5.0,
    Metric.activity: 30.0,
  };
  static const _moodFaces = ['😞', '😕', '😐', '🙂', '😄'];

  late DateTime _date = widget.initialDate;
  final Map<Metric, double> _values = Map.of(_defaults);
  final _note = TextEditingController();
  bool _exists = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final log = await widget.repo.getFor(_date);
    if (!mounted) return;
    setState(() {
      _exists = log != null;
      _values
        ..clear()
        ..addAll(log == null
            ? _defaults
            : {for (final m in Metric.values) m: log.valueOf(m)});
      _note.text = log?.note ?? '';
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: dayOffset(today, -365),
      lastDate: today,
    );
    if (picked != null && picked != _date) {
      _date = picked;
      _load();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repo.save(DailyLog(
        date: _date,
        sleepHours: _values[Metric.sleep]!,
        mood: _values[Metric.mood]!.round(),
        energy: _values[Metric.energy]!.round(),
        productivity: _values[Metric.productivity]!.round(),
        workload: _values[Metric.workload]!.round(),
        activityMinutes: _values[Metric.activity]!.round(),
        note: _note.text.trim(),
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this check-in?'),
        content: Text(DateFormat('EEEE, d MMM').format(_date)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repo.delete(_date);
    if (mounted) Navigator.pop(context, false);
  }

  String? _hint(Metric m, double v) => switch (m) {
        Metric.mood => _moodFaces[((v - 1) / 9 * 4).round()],
        Metric.sleep => v < 6 ? 'short' : (v <= 9 ? 'healthy' : 'long'),
        Metric.workload => v >= 8 ? 'heavy' : (v <= 3 ? 'light' : null),
        Metric.activity => v >= 30 ? 'active' : null,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(_exists ? 'Edit check-in' : 'Daily check-in'),
        actions: [
          if (_exists)
            IconButton(
                tooltip: 'Delete',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                ActionChip(
                  avatar: const Icon(Icons.calendar_month, size: 18),
                  label: Text(_date == today
                      ? 'Today · ${DateFormat('d MMM').format(_date)}'
                      : DateFormat('EEEE, d MMM').format(_date)),
                  onPressed: _pickDate,
                ),
                const SizedBox(height: 12),
                for (final m in Metric.values) ...[
                  SectionCard(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Column(children: [
                      Row(children: [
                        Icon(m.icon, color: m.color),
                        const SizedBox(width: 10),
                        Text(m.label,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (_hint(m, _values[m]!) != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(_hint(m, _values[m]!)!,
                                style: TextStyle(
                                    color: t.colorScheme.onSurfaceVariant)),
                          ),
                        Text(m.format(_values[m]!),
                            style: t.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700, color: m.color)),
                      ]),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                            activeTrackColor: m.color, thumbColor: m.color),
                        child: Slider(
                          value: _values[m]!.clamp(m.min, m.max).toDouble(),
                          min: m.min,
                          max: m.max,
                          divisions: m.divisions,
                          label: m.format(_values[m]!),
                          onChanged: (v) => setState(() => _values[m] = v),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _note,
                  maxLines: 3,
                  maxLength: 280,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'Anything that shaped your day?',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(_exists ? 'Update' : 'Save check-in'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ),
    );
  }
}
