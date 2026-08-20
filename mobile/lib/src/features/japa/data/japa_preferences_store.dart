import 'package:isar_community/isar.dart';

import 'japa_preferences.dart';

/// Always the same row — see [JapaPreferences].
const _preferencesId = 0;

Future<bool> screenOffPreferred(Isar isar) async {
  final row = await isar.japaPreferences.get(_preferencesId);
  return row?.screenOffEnabled ?? false;
}

Future<void> setScreenOffPreferred(Isar isar, bool enabled) async {
  await isar.writeTxn(() async {
    final row = await isar.japaPreferences.get(_preferencesId) ??
        JapaPreferences();
    row.screenOffEnabled = enabled;
    await isar.japaPreferences.put(row);
  });
}

/// The offered mala lengths (docs/ONBOARDING.md §1.3) — 27 (quick), 54
/// (half), 108 (full, traditional default), 1008 (extended).
const malaLengthOptions = [27, 54, 108, 1008];

Future<int> malaLengthPreferred(Isar isar) async {
  final row = await isar.japaPreferences.get(_preferencesId);
  return row?.malaLength ?? 108;
}

Future<void> setMalaLengthPreferred(Isar isar, int length) async {
  await isar.writeTxn(() async {
    final row = await isar.japaPreferences.get(_preferencesId) ??
        JapaPreferences();
    row.malaLength = length;
    await isar.japaPreferences.put(row);
  });
}

/// The traditional sankalp lengths offered at the sankalp offer (docs/
/// ONBOARDING.md §2) — 11 (short, encouragement only), 21 (earns a badge),
/// 41 (unlocks the 7-day Seva Pass trial — docs/PRD.md §10.3). 41 replaces
/// an earlier 36-day option: 40/41-day mandala and Chalisa observances are
/// an established traditional length, 36 wasn't.
const sankalpLengthOptions = [11, 21, 41];

Future<bool> isOnboardingComplete(Isar isar) async {
  final row = await isar.japaPreferences.get(_preferencesId);
  return row?.onboardingComplete ?? false;
}

Future<void> setOnboardingComplete(Isar isar) async {
  await isar.writeTxn(() async {
    final row = await isar.japaPreferences.get(_preferencesId) ??
        JapaPreferences();
    row.onboardingComplete = true;
    await isar.japaPreferences.put(row);
  });
}

Future<void> setSankalpChoice(
  Isar isar, {
  required int? lengthDays,
  required String? intention,
  required int? dailyTarget,
  required int? reminderHour,
  required int? reminderMinute,
}) async {
  await isar.writeTxn(() async {
    final row = await isar.japaPreferences.get(_preferencesId) ??
        JapaPreferences();
    row.sankalpLengthDays = lengthDays;
    row.sankalpIntention = intention;
    row.sankalpDailyTarget = dailyTarget;
    row.sankalpReminderHour = reminderHour;
    row.sankalpReminderMinute = reminderMinute;
    await isar.japaPreferences.put(row);
  });
}

/// What the japa screen needs to know whether today's target has just been
/// met: the locked daily target itself, and the reminder time to push to
/// tomorrow if so (see [SankalpReminderScheduler.rescheduleForTomorrow]).
/// Distinct from [malaLength], which only affects the ring's visual
/// chunking, not the vow.
class ActiveSankalpReminder {
  const ActiveSankalpReminder({
    required this.dailyTarget,
    required this.reminderHour,
    required this.reminderMinute,
  });

  final int dailyTarget;
  final int reminderHour;
  final int reminderMinute;
}

/// Null if there's no active sankalp, or one is active but no reminder was
/// set for it — either way, nothing for the japa screen to reschedule.
Future<ActiveSankalpReminder?> activeSankalpReminder(Isar isar) async {
  final row = await isar.japaPreferences.get(_preferencesId);
  final target = row?.sankalpDailyTarget;
  final hour = row?.sankalpReminderHour;
  final minute = row?.sankalpReminderMinute;
  if (target == null || hour == null || minute == null) return null;
  return ActiveSankalpReminder(
    dailyTarget: target,
    reminderHour: hour,
    reminderMinute: minute,
  );
}
