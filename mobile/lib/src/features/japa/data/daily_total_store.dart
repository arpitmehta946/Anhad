import 'package:isar_community/isar.dart';

import 'daily_japa_total.dart';

String todayLocalDate() {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Gets (creating if needed) today's running-total row. The check-then-create
/// happens inside a single write transaction — Isar serializes write
/// transactions against each other, even across isolates sharing the same
/// instance, so two isolates calling this around the same moment can't both
/// see "no row yet" and each create their own duplicate row for today.
Future<DailyJapaTotal> todayTotalRow(Isar isar) {
  final today = todayLocalDate();
  return isar.writeTxn(() async {
    final existing = await isar.dailyJapaTotals
        .filter()
        .localDateEqualTo(today)
        .findFirst();
    if (existing != null) return existing;
    final fresh = DailyJapaTotal()
      ..localDate = today
      ..totalTaps = 0;
    await isar.dailyJapaTotals.put(fresh);
    return fresh;
  });
}

/// Adjusts today's running total by [delta] — positive for a new tap,
/// negative when a synced batch turns out to be a permanent rejection.
/// Shared between the foreground JapaSessionController and the headless
/// background isolate a screen-off session runs in, so a tap counts the
/// same way regardless of which one recorded it.
///
/// The read (current total) and the write (updated total) happen inside a
/// single write transaction rather than as two separate steps. Two calls
/// racing — e.g. rapid volume-key presses arriving faster than one
/// read-modify-write cycle completes, from the same isolate or different
/// ones — would otherwise both read the same starting value, and the
/// second write silently clobbers the first increment: an undercount, not
/// a crash, which is exactly what made it easy to miss until totals were
/// checked against the server's own sum. Isar serializes write
/// transactions against each other, so doing the whole read-modify-write
/// as one transaction makes each adjustment atomic regardless of timing.
Future<void> adjustDailyTotal(Isar isar, int delta) async {
  if (delta == 0) return;
  final today = todayLocalDate();
  await isar.writeTxn(() async {
    var row = await isar.dailyJapaTotals
        .filter()
        .localDateEqualTo(today)
        .findFirst();
    row ??= DailyJapaTotal()
      ..localDate = today
      ..totalTaps = 0;
    final updated = row.totalTaps + delta;
    row.totalTaps = updated < 0 ? 0 : updated;
    await isar.dailyJapaTotals.put(row);
  });
}
