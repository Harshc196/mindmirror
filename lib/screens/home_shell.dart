import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/daily_log.dart';
import '../services/log_repository.dart';
import '../services/notification_service.dart';
import 'dashboard_screen.dart';
import 'insights_screen.dart';
import 'log_screen.dart';
import 'profile_screen.dart';
import 'trends_screen.dart';

/// Holds one live Firestore stream of the last 60 days and hands the list to
/// each tab, so all screens stay in sync without extra reads.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.user});
  final User user;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final LogRepository repo = LogRepository(widget.user.uid);
  late final Stream<List<DailyLog>> _logs = repo.watchRecent(days: 60);
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.registerToken(widget.user.uid);
  }

  Future<void> _openLog([DateTime? date]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => LogScreen(
          repo: repo, initialDate: date ?? DateUtils.dateOnly(DateTime.now())),
    ));
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Check-in saved ✨')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DailyLog>>(
      stream: _logs,
      builder: (context, snap) {
        Widget body;
        if (snap.hasError) {
          body = Center(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load your data.\n${snap.error}',
                textAlign: TextAlign.center),
          ));
        } else if (!snap.hasData) {
          body = const Center(child: CircularProgressIndicator());
        } else {
          final logs = snap.data!;
          body = IndexedStack(index: _tab, children: [
            DashboardScreen(user: widget.user, logs: logs, onLog: _openLog),
            TrendsScreen(logs: logs, onEdit: _openLog),
            InsightsScreen(logs: logs, repo: repo),
            ProfileScreen(user: widget.user, repo: repo, logs: logs),
          ]);
        }

        return Scaffold(
          body: SafeArea(child: body),
          floatingActionButton: _tab <= 1
              ? FloatingActionButton.extended(
                  onPressed: () => _openLog(),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Check in'),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.today_outlined),
                  selectedIcon: Icon(Icons.today),
                  label: 'Today'),
              NavigationDestination(
                  icon: Icon(Icons.show_chart),
                  selectedIcon: Icon(Icons.insert_chart),
                  label: 'Trends'),
              NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome),
                  label: 'Insights'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile'),
            ],
          ),
        );
      },
    );
  }
}
