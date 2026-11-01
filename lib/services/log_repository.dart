import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/daily_log.dart';

/// All Firestore access lives here. Data model:
///   users/{uid}                    profile, fcmToken, reminder settings
///   users/{uid}/logs/{yyyy-MM-dd}  one DailyLog per day
///   users/{uid}/reflections/{id}   AI reflections (written only by Cloud Functions)
class LogRepository {
  LogRepository(this.uid);

  final String uid;
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get userDoc =>
      _db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get _logs =>
      userDoc.collection('logs');

  Stream<List<DailyLog>> watchRecent({int days = 60}) {
    final since = dayOffset(DateUtils.dateOnly(DateTime.now()), -(days - 1));
    return _logs
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('date')
        .snapshots()
        .map((s) => s.docs.map((d) => DailyLog.fromMap(d.data())).toList());
  }

  Future<DailyLog?> getFor(DateTime date) async {
    final doc = await _logs.doc(DailyLog.idFor(date)).get();
    return doc.exists ? DailyLog.fromMap(doc.data()!) : null;
  }

  Future<void> save(DailyLog log) => _logs.doc(log.id).set(log.toMap());

  Future<void> delete(DateTime date) => _logs.doc(DailyLog.idFor(date)).delete();

  Future<void> deleteAll() async {
    final snap = await _logs.get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  /// Cached so widgets that rebuild keep the same subscription.
  late final Stream<Map<String, dynamic>> profile =
      userDoc.snapshots().map((s) => s.data() ?? {});

  Future<void> updateProfile(Map<String, dynamic> data) =>
      userDoc.set(data, SetOptions(merge: true));

  Stream<Map<String, dynamic>?> watchLatestReflection() => userDoc
      .collection('reflections')
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : s.docs.first.data());

  /// Writes [days] of realistic sample data so the demo has patterns to show.
  /// Built-in relationships: sleep → energy → productivity, activity → mood,
  /// heavy workload → lower mood.
  Future<void> seedDemoData({int days = 30}) async {
    final rnd = Random(7);
    double noise(double s) => (rnd.nextDouble() + rnd.nextDouble() - 1) * s;
    int clamp10(num v) => v.round().clamp(1, 10).toInt();

    final today = DateUtils.dateOnly(DateTime.now());
    final batch = _db.batch();
    const notes = [
      'Late night studying for exams.',
      'Went for a long run in the evening — felt great.',
      'Back-to-back lab sessions, exhausting.',
      'Slept in, relaxed day with friends.',
      'Project deadline crunch.',
    ];

    for (var i = days - 1; i >= 0; i--) {
      final date = dayOffset(today, -i);
      final weekend = date.weekday >= 6;
      final sleep = ((5.2 + rnd.nextDouble() * 3.6 + (weekend ? 0.8 : 0.0)) * 2)
              .round() /
          2;
      final activity = rnd.nextDouble() < 0.55
          ? 25 + rnd.nextInt(55)
          : rnd.nextInt(18);
      final workload =
          clamp10((weekend ? 3.0 : 6.5) + noise(2.5));
      final energy = clamp10(2 + (sleep - 5) * 1.25 + activity / 45 + noise(1.2));
      final mood = clamp10(3 +
          energy * 0.4 +
          (activity >= 30 ? 1.2 : 0.0) -
          (workload >= 7 ? 1.6 : 0) +
          noise(1.2));
      final productivity = clamp10(1.2 +
          energy * 0.55 +
          mood * 0.2 +
          (weekend ? -1.0 : 0.6) -
          (sleep < 6 ? 1.0 : 0.0) +
          noise(1));

      final log = DailyLog(
        date: date,
        sleepHours: sleep,
        mood: mood,
        energy: energy,
        productivity: productivity,
        workload: workload,
        activityMinutes: activity,
        note: rnd.nextDouble() < 0.3 ? notes[rnd.nextInt(notes.length)] : '',
      );
      batch.set(_logs.doc(log.id), log.toMap());
    }
    await batch.commit();
  }
}
