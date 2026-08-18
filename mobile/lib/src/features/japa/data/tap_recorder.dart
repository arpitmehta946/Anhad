import 'package:isar_community/isar.dart';

import 'daily_total_store.dart';
import 'local_japa_session.dart';

/// Appends one tap to [sessionId] and adjusts today's running total — the
/// core Isar write behind every tap, shared between the foreground
/// JapaSessionController (main isolate) and the headless background
/// isolate JapaForegroundService spins up for a screen-off session
/// (japa_background_entrypoint.dart), so a volume-key tap and an on-screen
/// tap write identically.
Future<void> recordTapInIsar(Isar isar, int sessionId) async {
  final session = await isar.localJapaSessions.get(sessionId);
  if (session == null) return;
  session.taps.add(DateTime.now());
  await isar.writeTxn(() => isar.localJapaSessions.put(session));
  await adjustDailyTotal(isar, 1);
}
