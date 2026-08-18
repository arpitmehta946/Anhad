import 'package:isar_community/isar.dart';

import 'japa_api_client.dart';
import 'local_japa_session.dart';

/// What happened to a session on a flush attempt. Distinct from a plain
/// bool because the caller needs to tell "gone because it synced" apart
/// from "gone because it was rejected" — a rejected batch's taps were
/// never recorded server-side, so anything counting them locally (the
/// daily total) needs to unwind that count, which a synced batch doesn't.
enum FlushOutcome { synced, rejected, stillQueued }

/// Summary of a [JapaSyncService.flushPending] sweep across every locally
/// queued session.
class FlushPendingResult {
  const FlushPendingResult({required this.rejectedTaps, required this.stillQueued});

  /// Total tap count across every session this sweep found rejected.
  final int rejectedTaps;

  /// True if anything is still queued locally after the sweep (offline,
  /// server unreachable, or no auth token yet).
  final bool stillQueued;
}

/// Flushes locally-queued tap batches to the API — one write per accepted
/// batch on the server side (api/internal/japa/service.go), never one per
/// tap (docs/TECH_STACK.md §5).
class JapaSyncService {
  JapaSyncService({required Isar isar, required JapaApiClient api})
      : _isar = isar,
        _api = api;

  final Isar _isar;
  final JapaApiClient _api;

  /// Flushes every locally-queued session — e.g. leftovers from a previous
  /// app run that never made it online. [excludeId] skips the caller's own
  /// active session, which is still being appended to and must only ever
  /// be flushed through the caller's own serialized path.
  Future<FlushPendingResult> flushPending({int? excludeId}) async {
    final pending = await _isar.localJapaSessions.where().findAll();
    var rejectedTaps = 0;
    var stillQueued = false;
    for (final session in pending) {
      if (session.id == excludeId) continue;
      final tapCount = session.taps.length;
      switch (await flushSession(session)) {
        case FlushOutcome.rejected:
          rejectedTaps += tapCount;
        case FlushOutcome.stillQueued:
          stillQueued = true;
        case FlushOutcome.synced:
          break;
      }
    }
    return FlushPendingResult(rejectedTaps: rejectedTaps, stillQueued: stillQueued);
  }

  /// Flushes a single session.
  Future<FlushOutcome> flushSession(LocalJapaSession session) async {
    if (session.taps.isEmpty) {
      await _isar.writeTxn(() => _isar.localJapaSessions.delete(session.id));
      return FlushOutcome.synced;
    }

    try {
      final sorted = [...session.taps]..sort();
      await _api.submitTaps(sorted);
      await _isar.writeTxn(() => _isar.localJapaSessions.delete(session.id));
      return FlushOutcome.synced;
    } on JapaTapsRejected {
      // The server evaluated this exact batch and rejected it (anti-cheat
      // or malformed taps) — retrying identical data fails identically
      // forever. Left queued, it would keep absorbing every new tap into
      // an ever-growing batch that can never pass the rate check again
      // (docs/PRD.md §7.4). Drop it so future taps get a clean session.
      await _isar.writeTxn(() => _isar.localJapaSessions.delete(session.id));
      return FlushOutcome.rejected;
    } catch (_) {
      // Offline, server unreachable, or no auth token yet — leave it queued
      // locally. The next trigger (session end, connectivity restored, or
      // next app start) retries it.
      return FlushOutcome.stillQueued;
    }
  }
}
