import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The daily practice reminder (docs/PRD.md §7.7) — a local, on-device
/// notification, not push: the phone already knows the reminder time and
/// today's progress, so no server round-trip is needed for this one.
///
/// Exactly one reminder is ever pending at a time, under a fixed
/// [_notificationId] — [scheduleForTime] and [rescheduleForTomorrow] both
/// call `zonedSchedule` with that same id, which replaces whatever was
/// previously pending rather than stacking a second one. That's what
/// keeps this "one per day maximum" by construction: there is never more
/// than one scheduled occurrence to begin with, so "today's already
/// handled" is expressed by moving the single pending occurrence to
/// tomorrow, not by cancelling N of them.
class SankalpReminderScheduler {
  SankalpReminderScheduler(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _notificationId = 7001;
  static const _channelId = 'sankalp_reminder';
  static const _channelName = 'Practice reminder';

  static bool _initialized = false;

  /// Sets up the plugin and the device's real local timezone — without
  /// the latter, `timezone`'s [tz.local] defaults to UTC, which would
  /// schedule every reminder at the wrong wall-clock hour for anyone not
  /// on UTC. Safe to call more than once; only does the work the first
  /// time.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  /// Schedules the reminder for the next occurrence of [time] — today if
  /// that time hasn't passed yet, tomorrow otherwise. Called when a
  /// sankalp is first taken, and again any time the reminder time itself
  /// changes.
  Future<void> scheduleForTime(TimeOfDay time) async {
    await ensureInitialized();
    final next = _nextOccurrence(time, afterToday: false);
    await _schedule(next);
  }

  /// Moves the single pending reminder from today to tomorrow at the same
  /// [time] — called the moment today's target is met, so the reminder
  /// that would otherwise have fired later today never does. Never nags
  /// someone who's already practised.
  Future<void> rescheduleForTomorrow(TimeOfDay time) async {
    await ensureInitialized();
    final next = _nextOccurrence(time, afterToday: true);
    await _schedule(next);
  }

  /// No active sankalp (declined, ended, or broken) — nothing left to
  /// remind about.
  Future<void> cancel() async {
    await ensureInitialized();
    await _plugin.cancel(id: _notificationId);
  }

  tz.TZDateTime _nextOccurrence(TimeOfDay time, {required bool afterToday}) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (afterToday || !next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  Future<void> _schedule(tz.TZDateTime when) async {
    await _plugin.zonedSchedule(
      id: _notificationId,
      title: 'Your practice is waiting',
      body: "A few quiet minutes, whenever you're ready.",
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: "Reminds you once a day, only if today's "
              "sankalp target hasn't been met yet.",
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      // Inexact rather than exact: this is a gentle daily nudge, not an
      // alarm-clock-precision need, and inexact scheduling doesn't require
      // the separate "Alarms & reminders" special access Android 12+
      // gates exact alarms behind — a heavier ask than this feature
      // warrants.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
