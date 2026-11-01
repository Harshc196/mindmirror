import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Two notification paths:
///  • Local notifications — the daily check-in reminder, scheduled on-device.
///  • Firebase Cloud Messaging — server push when the weekly AI reflection is ready.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _local = FlutterLocalNotificationsPlugin();
  static const _reminderId = 1;
  StreamSubscription<String>? _tokenSub;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'mindmirror_general',
      'MindMirror',
      channelDescription: 'Check-in reminders and weekly reflections',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    tzdata.initializeTimeZones();
    await _local.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));

    // FCM doesn't display notifications while the app is open, so mirror them locally.
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n != null) _local.show(message.hashCode & 0x7fffffff, n.title, n.body, _details);
    });
  }

  Future<void> requestPermissions() async {
    await FirebaseMessaging.instance.requestPermission();
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Saves this device's FCM token so Cloud Functions can push to it.
  Future<void> registerToken(String uid) async {
    try {
      await requestPermissions();
      final doc = FirebaseFirestore.instance.collection('users').doc(uid);
      Future<void> save(String t) => doc.set(
          {'fcmToken': t, 'tokenUpdatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await save(token);
      await _tokenSub?.cancel();
      _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen(save);
    } catch (e) {
      debugPrint('FCM registration skipped: $e');
    }
  }

  Future<void> scheduleDailyReminder(TimeOfDay time) async {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    await _local.cancel(_reminderId);
    await _local.zonedSchedule(
      _reminderId,
      'Time to check in 🌙',
      'How did today go? Logging takes about 30 seconds.',
      tz.TZDateTime.from(next, tz.UTC),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
    );
  }

  Future<void> cancelDailyReminder() => _local.cancel(_reminderId);

  Future<void> showNow(String title, String body) =>
      _local.show(DateTime.now().millisecond + 100, title, body, _details);

  /// This device's FCM token — paste it into Firebase Console → Messaging →
  /// "Send test message" to push a notification to this phone.
  Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  Future<void> showTest() => _local.show(
        99,
        'MindMirror notifications are on ✅',
        'You\'ll get a gentle nudge to check in each day.',
        _details,
      );
}
