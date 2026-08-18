import 'package:isar_community/isar.dart';

import 'japa_api_client.dart';
import 'local_japa_session.dart';

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
  Future<void> flushPending({int? excludeId}) async {
    final pending = await _isar.localJapaSessions.where().findAll();
    for (final session in pending) {
      if (session.id == excludeId) continue;
      await flushSession(session);
    }
  }

  /// Flushes a single session. Returns true once it's gone — synced, empty
  /// and discarded, or rejected on its merits and discarded — false means
  /// it's still queued locally for a retry.
  Future<bool> flushSession(LocalJapaSession session) async {
    if (session.taps.isEmpty) {
      await _isar.writeTxn(() => _isar.localJapaSessions.delete(session.id));
      return true;
    }

    try {
      final sorted = [...session.taps]..sort();
      await _api.submitTaps(sorted);
      await _isar.writeTxn(() => _isar.localJapaSessions.delete(session.id));
      return true;
    } on JapaTapsRejected {
      // The server evaluated this exact batch and rejected it (anti-cheat
      // or malformed taps) — retrying identical data fails identically
      // forever. Left queued, it would keep absorbing every new tap into
      // an ever-growing batch that can never pass the rate check again
      // (docs/PRD.md §7.4). Drop it so future taps get a clean session.
      await _isar.writeTxn(() => _isar.localJapaSessions.delete(session.id));
      return true;
    } catch (_) {
      // Offline, server unreachable, or no auth token yet — leave it queued
      // locally. The next trigger (session end, connectivity restored, or
      // next app start) retries it.
      return false;
    }
  }
}
