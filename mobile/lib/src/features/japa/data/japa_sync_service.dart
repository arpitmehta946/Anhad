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
  /// app run that never made it online.
  Future<void> flushPending() async {
    final pending = await _isar.localJapaSessions.where().findAll();
    for (final session in pending) {
      await flushSession(session);
    }
  }

  /// Flushes a single session. Returns true once it's gone (synced, or
  /// empty and just discarded) — false means it's still queued locally.
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
    } catch (_) {
      // Offline, server unreachable, anti-cheat rejection, or no auth token
      // yet — leave it queued locally. The next trigger (session end,
      // connectivity restored, or next app start) retries it.
      return false;
    }
  }
}
