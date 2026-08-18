import 'package:isar_community/isar.dart';

import 'daily_total_store.dart';
import 'local_japa_session.dart';

/// Appends one tap to [sessionId] and adjusts today's running total — the
/// core Isar write behind every tap, shared between the foreground
/// JapaSessionController (main isolate) and the headless background
/// isolate JapaForegroundService spins up for a screen-off session
/// (japa_background_entrypoint.dart), so a volume-key tap and an on-screen
/// tap write identically.
///
/// The read (current tap list) and the write (list plus the new tap)
/// happen inside a single write transaction, not as two separate steps.
/// Two calls racing — rapid volume-key presses arriving faster than one
/// get-then-put cycle completes, whether from the same isolate or the
/// other one — would otherwise both read the same starting list, each
/// append to their own in-memory copy, and the second put() silently
/// overwrites the first: a real tap dropped entirely, not just missing
/// from a display counter. Isar serializes write transactions against
/// each other, so doing the whole get-then-put as one transaction makes
/// each append atomic regardless of timing.
Future<void> recordTapInIsar(Isar isar, int sessionId) async {
  await isar.writeTxn(() async {
    final session = await isar.localJapaSessions.get(sessionId);
    if (session == null) return;
    session.taps.add(DateTime.now());
    await isar.localJapaSessions.put(session);
  });
  await adjustDailyTotal(isar, 1);
}
