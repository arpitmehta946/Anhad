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

/// Removes the most recent tap from [sessionId]'s still-local (not yet
/// flushed to the server) row, correcting an accidental tap. Returns
/// whether there was actually a tap to remove — the UI uses this to tell
/// "undone" from "nothing to undo" (e.g. right after a rotation, when the
/// last tap already left in the batch that completed the round).
///
/// Deliberately can't reach into an already-flushed/rotated-away row: once
/// a batch has left this device, correcting it would mean issuing a
/// retroactive adjustment against a row the server may already have
/// processed (or be processing), which is a materially different, riskier
/// operation than undoing something that never left the device. In
/// practice this only matters for the rare case of trying to undo the tap
/// that just completed a mala — every other accidental tap is caught long
/// before the next flush trigger.
///
/// The remove-then-put happens inside a single write transaction for the
/// same reason [recordTapInIsar] does — see its doc comment — and the
/// notification/ring pick this up automatically via the same Isar watcher
/// that reacts to every other change to this row, not a separate code
/// path.
Future<bool> undoLastTapInIsar(Isar isar, int sessionId) async {
  final removed = await isar.writeTxn(() async {
    final session = await isar.localJapaSessions.get(sessionId);
    if (session == null || session.taps.isEmpty) return false;
    session.taps.removeLast();
    await isar.localJapaSessions.put(session);
    return true;
  });
  if (removed) {
    await adjustDailyTotal(isar, -1);
  }
  return removed;
}
