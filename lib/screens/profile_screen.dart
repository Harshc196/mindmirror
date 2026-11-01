import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/daily_log.dart';
import '../services/auth_service.dart';
import '../services/log_repository.dart';
import '../services/notification_service.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen(
      {super.key, required this.user, required this.repo, required this.logs});

  final User user;
  final LogRepository repo;
  final List<DailyLog> logs;

  Future<bool> _confirm(BuildContext context, String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue')),
          ],
        ),
      ) ??
      false;

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final name = user.displayName ?? 'You';

    return StreamBuilder<Map<String, dynamic>>(
      stream: repo.profile,
      builder: (context, snap) {
        final p = snap.data ?? {};
        final enabled = p['reminderEnabled'] == true;
        final time = TimeOfDay(
          hour: (p['reminderHour'] as num?)?.toInt() ?? 21,
          minute: (p['reminderMinute'] as num?)?.toInt() ?? 0,
        );

        Future<void> setReminder(bool on, TimeOfDay at) async {
          await repo.updateProfile({
            'reminderEnabled': on,
            'reminderHour': at.hour,
            'reminderMinute': at.minute,
          });
          if (on) {
            await NotificationService.instance.requestPermissions();
            await NotificationService.instance.scheduleDailyReminder(at);
          } else {
            await NotificationService.instance.cancelDailyReminder();
          }
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            SectionCard(
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name,
                        style: t.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(user.email ?? '',
                        style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('${logs.length} check-ins in the last 60 days'),
                  ]),
                ),
              ]),
            ),
            const SectionTitle('Reminders'),
            SectionCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Daily check-in reminder'),
                  subtitle: const Text('A gentle nudge so you never miss a day'),
                  value: enabled,
                  onChanged: (v) => setReminder(v, time),
                ),
                ListTile(
                  enabled: enabled,
                  leading: const Icon(Icons.schedule),
                  title: const Text('Reminder time'),
                  trailing: Text(time.format(context),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () async {
                    final picked =
                        await showTimePicker(context: context, initialTime: time);
                    if (picked != null) await setReminder(true, picked);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.notification_add_outlined),
                  title: const Text('Send a test notification'),
                  onTap: () async {
                    await NotificationService.instance.requestPermissions();
                    await NotificationService.instance.showTest();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Copy push token (FCM)'),
                  subtitle: const Text('For sending a push from Firebase Console'),
                  onTap: () async {
                    final token = await NotificationService.instance.getToken();
                    debugPrint('FCM token: $token');
                    if (!context.mounted) return;
                    if (token == null) {
                      _toast(context, 'No token — this emulator needs Google Play services.');
                      return;
                    }
                    await Clipboard.setData(ClipboardData(text: token));
                    if (context.mounted) _toast(context, 'Token copied (also printed in the terminal)');
                  },
                ),
              ]),
            ),
            const SectionTitle('Data'),
            SectionCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.dataset_outlined),
                  title: const Text('Load 30 days of sample data'),
                  subtitle: const Text('Great for exploring charts and insights'),
                  onTap: () async {
                    if (!await _confirm(context, 'Load sample data?',
                        'This replaces any check-ins from the last 30 days with realistic sample entries.')) {
                      return;
                    }
                    await repo.seedDemoData();
                    if (context.mounted) _toast(context, 'Sample data loaded');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_sweep_outlined, color: t.colorScheme.error),
                  title: Text('Delete all my check-ins',
                      style: TextStyle(color: t.colorScheme.error)),
                  onTap: () async {
                    if (!await _confirm(context, 'Delete everything?',
                        'All your check-ins will be permanently removed.')) {
                      return;
                    }
                    await repo.deleteAll();
                    if (context.mounted) _toast(context, 'All check-ins deleted');
                  },
                ),
              ]),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                await NotificationService.instance.cancelDailyReminder();
                await AuthService.instance.signOut();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 16),
            Text('MindMirror v1.0 · Your data stays private to your account.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
          ],
        );
      },
    );
  }
}
