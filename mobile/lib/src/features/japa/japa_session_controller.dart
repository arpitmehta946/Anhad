import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../config.dart';
import '../auth/auth_controller.dart';
import 'data/isar_provider.dart';
import 'data/japa_api_client.dart';
import 'data/japa_sync_service.dart';
import 'data/local_japa_session.dart';

/// One full mala (docs/FRONTEND_GUIDELINES.md §5).
const malaSize = 108;

class JapaSessionState {
  const JapaSessionState({
    this.tapsInRound = 0,
    this.roundsCompleted = 0,
    this.justFilledBeadIndex,
    this.syncFailed = false,
  });

  /// Beads filled in the ring for the current, in-progress round (0-107).
  final int tapsInRound;

  /// Full malas completed so far this screen visit.
  final int roundsCompleted;

  /// Index of the bead that should play the pulse animation right now.
  final int? justFilledBeadIndex;

  /// True when the most recent sync attempt found taps still queued locally
  /// afterward — e.g. no auth token set yet, or the API was unreachable.
  /// Surfaced in the UI rather than failing silently.
  final bool syncFailed;

  JapaSessionState copyWith({
    int? tapsInRound,
    int? roundsCompleted,
    int? justFilledBeadIndex,
    bool? syncFailed,
  }) {
    return JapaSessionState(
      tapsInRound: tapsInRound ?? this.tapsInRound,
      roundsCompleted: roundsCompleted ?? this.roundsCompleted,
      justFilledBeadIndex: justFilledBeadIndex ?? this.justFilledBeadIndex,
      syncFailed: syncFailed ?? this.syncFailed,
    );
  }
}

/// Drives one screen visit's worth of japa taps: persists every tap to Isar
/// immediately (offline-first), tracks the Mala Ring's round progress, and
/// flushes to Postgres when connectivity returns or the session ends —
/// never a network call per tap (docs/TECH_STACK.md §5).
class JapaSessionController extends StateNotifier<JapaSessionState> {
  JapaSessionController(this._isar, this._sync)
      : super(const JapaSessionState()) {
    _init();
  }

  final Isar _isar;
  final JapaSyncService _sync;
  int? _sessionId;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  Future<void> _init() async {
    // Retry anything left over from a previous run that never made it
    // online — this session doesn't exist yet, so it's never among these.
    // Surface the result: if practice from a prior visit is still stuck
    // locally (e.g. no auth token was ever set), the screen should say so
    // immediately rather than queuing it invisibly forever.
    unawaited(_syncPendingAndReportStatus());

    final session = LocalJapaSession();
    await _isar.writeTxn(() => _isar.localJapaSessions.put(session));
    if (!mounted) return;
    _sessionId = session.id;

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(_flushCurrentAndRotate());
      }
    });
  }

  Future<void> _syncPendingAndReportStatus() async {
    await _sync.flushPending();
    final remaining = await _isar.localJapaSessions.where().count();
    if (!mounted) return;
    state = state.copyWith(syncFailed: remaining > 0);
  }

  Future<void> tap() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;

    final session = await _isar.localJapaSessions.get(sessionId);
    if (session == null || !mounted) return;

    session.taps.add(DateTime.now());
    await _isar.writeTxn(() => _isar.localJapaSessions.put(session));
    // The await above is a suspension point: the screen may have been
    // popped (disposing this controller) while it was in flight. Setting
    // `state` past that point throws — the tap's Isar write already landed
    // either way, so it's safe to just stop here.
    if (!mounted) return;

    final nextTapsInRound = state.tapsInRound + 1;
    if (nextTapsInRound >= malaSize) {
      state = state.copyWith(
        tapsInRound: 0,
        roundsCompleted: state.roundsCompleted + 1,
        justFilledBeadIndex: malaSize - 1,
      );
      // A completed mala is a natural checkpoint — sync it now rather than
      // waiting for the user to leave the screen or a connectivity change.
      unawaited(_flushCurrentAndRotate());
    } else {
      state = state.copyWith(
        tapsInRound: nextTapsInRound,
        justFilledBeadIndex: nextTapsInRound - 1,
      );
    }
  }

  /// Connectivity just came back while still on-screen: flush what's
  /// queued so far, then start a fresh local buffer for anything new —
  /// rotating (rather than reusing the just-flushed, now-deleted row)
  /// keeps in-flight taps from being silently dropped mid-session.
  Future<void> _flushCurrentAndRotate() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final session = await _isar.localJapaSessions.get(sessionId);
    if (session == null) return;

    final flushed = await _sync.flushSession(session);
    if (mounted) {
      state = state.copyWith(syncFailed: !flushed);
    }
    if (flushed) {
      final fresh = LocalJapaSession();
      await _isar.writeTxn(() => _isar.localJapaSessions.put(fresh));
      if (!mounted) return;
      _sessionId = fresh.id;
    }
  }

  /// The session is actually ending (screen closing) — flush without
  /// rotating, since nothing more will be appended.
  Future<void> _flushCurrentFinal() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final session = await _isar.localJapaSessions.get(sessionId);
    if (session == null) return;
    await _sync.flushSession(session);
  }

  @override
  void dispose() {
    unawaited(_connectivitySub?.cancel());
    unawaited(_flushCurrentFinal());
    super.dispose();
  }
}

final japaSessionControllerProvider = StateNotifierProvider.autoDispose<
    JapaSessionController, JapaSessionState>((ref) {
  final isar = ref.watch(isarProvider);
  final authController = ref.watch(authControllerProvider.notifier);
  final api = JapaApiClient(
    baseUrl: apiBaseUrl,
    tokenProvider: authController.validAccessToken,
  );
  final sync = JapaSyncService(isar: isar, api: api);
  final controller = JapaSessionController(isar, sync);
  ref.onDispose(controller.dispose);
  return controller;
});
