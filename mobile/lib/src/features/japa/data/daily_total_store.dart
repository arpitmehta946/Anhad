import 'package:isar_community/isar.dart';

import 'daily_japa_total.dart';

String todayLocalDate() {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Gets (creating if needed) today's running-total row. Always re-reads by
/// today's date rather than caching it, so a call right after a midnight
/// rollover picks up the fresh row instead of yesterday's.
Future<DailyJapaTotal> todayTotalRow(Isar isar) async {
  final today = todayLocalDate();
  final existing =
      await isar.dailyJapaTotals.filter().localDateEqualTo(today).findFirst();
  if (existing != null) return existing;
  final fresh = DailyJapaTotal()
    ..localDate = today
    ..totalTaps = 0;
  await isar.writeTxn(() => isar.dailyJapaTotals.put(fresh));
  return fresh;
}

/// Adjusts today's running total by [delta] — positive for a new tap,
/// negative when a synced batch turns out to be a permanent rejection.
/// Shared between the foreground JapaSessionController and the headless
/// background isolate a screen-off session runs in, so a tap counts the
/// same way regardless of which one recorded it.
Future<void> adjustDailyTotal(Isar isar, int delta) async {
  if (delta == 0) return;
  final row = await todayTotalRow(isar);
  final updated = row.totalTaps + delta;
  row.totalTaps = updated < 0 ? 0 : updated;
  await isar.writeTxn(() => isar.dailyJapaTotals.put(row));
}
