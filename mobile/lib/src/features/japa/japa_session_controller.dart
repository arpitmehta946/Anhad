import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../config.dart';
import '../auth/auth_controller.dart';
import 'background/background_japa_controller.dart';
import 'data/daily_japa_total.dart';
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
    this.dailyTotal = 0,
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

  /// Every tap recorded today across all sessions (this visit and any
  /// earlier ones), device-local calendar day. Persists across restarts;
  /// resets to 0 at local midnight.
  final int dailyTotal;

  JapaSessionState copyWith({
    int? tapsInRound,
    int? roundsCompleted,
    int? justFilledBeadIndex,
    bool? syncFailed,
    int? dailyTotal,
  }) {
    return JapaSessionState(
      tapsInRound: tapsInRound ?? this.tapsInRound,
      roundsCompleted: roundsCompleted ?? this.roundsCompleted,
      justFilledBeadIndex: justFilledBeadIndex ?? this.justFilledBeadIndex,
      syncFailed: syncFailed ?? this.syncFailed,
      dailyTotal: dailyTotal ?? this.dailyTotal,
    );
  }
}

String _todayLocalDate() {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime _nextLocalMidnight() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
}

/// Drives one screen visit's worth of japa taps: persists every tap to Isar
/// immediately (offline-first), tracks the Mala Ring's round progress, and
/// flushes to Postgres when connectivity returns or the session ends —
/// never a network call per tap (docs/TECH_STACK.md §5).
class JapaSessionController extends StateNotifier<JapaSessionState> {
  JapaSessionController(this._isar, this._sync, {this.onTap})
      : super(const JapaSessionState()) {
    _init();
  }

  final Isar _isar;
  final JapaSyncService _sync;

  /// Notified after every tap lands in Isar — wired to
  /// [BackgroundJapaController.recordTap] so the screen-off notification's
  /// live count stays in sync regardless of whether this tap came from the
  /// mala ring or (once phase 2 lands) a volume-key press.
  final void Function()? onTap;
  int? _sessionId;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _midnightTimer;

  // Serializes every flush-triggering path (init-time pending sync,
  // connectivity restored, mala completion, screen close) onto the current
  // session. Without this, two triggers firing close together (e.g. two
  // connectivity-change events) both read the same still-there Isar row and
  // both submit it, producing duplicate rows on the server — and if one of
  // those submissions gets rejected, the taps added while it was in flight
  // pile onto a session that's already unrecoverable.
  Future<void> _flushChain = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _flushChain.then((_) => action());
    _flushChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _init() async {
    // Create the active session first and hand out its id before touching
    // anything else, so the pending-sync sweep below (which walks every
    // queued session) can exclude it — otherwise it can race the sweep,
    // get flushed-and-deleted out from under `_sessionId` while this
    // controller still believes it's live, and silently swallow every tap
    // written after that until the next rotation.
    final session = LocalJapaSession();
    await _isar.writeTxn(() => _isar.localJapaSessions.put(session));
    if (!mounted) return;
    _sessionId = session.id;

    await _loadDailyTotal();
    if (!mounted) return;
    _scheduleMidnightRollover();

    // Retry anything left over from a previous run that never made it
    // online. Surface the result: if practice from a prior visit is still
    // stuck locally (e.g. no auth token was ever set), the screen should
    // say so immediately rather than queuing it invisibly forever.
    unawaited(_syncPendingAndReportStatus(excludeId: session.id));

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(_serialized(_flushCurrentAndRotate));
      }
    });
  }

  Future<void> _syncPendingAndReportStatus({required int excludeId}) async {
    final result =
        await _serialized(() => _sync.flushPending(excludeId: excludeId));
    if (result.rejectedTaps > 0) {
      await _adjustDailyTotal(-result.rejectedTaps);
    }
    if (!mounted) return;
    state = state.copyWith(syncFailed: result.stillQueued);
  }

  /// Gets (creating if needed) today's running-total row. Always re-reads
  /// by today's date rather than caching the row, so a call that happens
  /// to land right after a midnight rollover picks up the fresh row
  /// instead of yesterday's.
  Future<DailyJapaTotal> _todayRow() async {
    final today = _todayLocalDate();
    final existing = await _isar.dailyJapaTotals
        .filter()
        .localDateEqualTo(today)
        .findFirst();
    if (existing != null) return existing;
    final fresh = DailyJapaTotal()
      ..localDate = today
      ..totalTaps = 0;
    await _isar.writeTxn(() => _isar.dailyJapaTotals.put(fresh));
    return fresh;
  }

  Future<void> _loadDailyTotal() async {
    final row = await _todayRow();
    if (!mounted) return;
    state = state.copyWith(dailyTotal: row.totalTaps);
  }

  Future<void> _adjustDailyTotal(int delta) async {
    if (delta == 0) return;
    final row = await _todayRow();
    final updated = row.totalTaps + delta;
    row.totalTaps = updated < 0 ? 0 : updated;
    await _isar.writeTxn(() => _isar.dailyJapaTotals.put(row));
    if (!mounted) return;
    // Only reflect it in `state` if it's still today's row — a midnight
    // rollover between the read at the top of this method and here means
    // this adjustment belongs to a day that's no longer on screen.
    if (row.localDate == _todayLocalDate()) {
      state = state.copyWith(dailyTotal: row.totalTaps);
    }
  }

  /// Re-derives today's total at the next local midnight, and again after
  /// that — covers the screen being left open across the day boundary,
  /// not just a restart the next day.
  void _scheduleMidnightRollover() {
    final delay = _nextLocalMidnight().difference(DateTime.now()) +
        const Duration(seconds: 1);
    _midnightTimer = Timer(delay, () {
      unawaited(_loadDailyTotal());
      _scheduleMidnightRollover();
    });
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

    onTap?.call();
    await _adjustDailyTotal(1);
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
      unawaited(_serialized(_flushCurrentAndRotate));
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

    final tapCount = session.taps.length;
    final outcome = await _sync.flushSession(session);
    if (mounted) {
      state = state.copyWith(syncFailed: outcome == FlushOutcome.stillQueued);
    }
    if (outcome == FlushOutcome.rejected) {
      await _adjustDailyTotal(-tapCount);
    }
    if (outcome != FlushOutcome.stillQueued) {
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
    final tapCount = session.taps.length;
    final outcome = await _sync.flushSession(session);
    if (outcome == FlushOutcome.rejected) {
      await _adjustDailyTotal(-tapCount);
    }
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    unawaited(_connectivitySub?.cancel());
    unawaited(_serialized(_flushCurrentFinal));
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
  final controller = JapaSessionController(
    isar,
    sync,
    onTap: () => ref.read(backgroundJapaControllerProvider.notifier).recordTap(),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
