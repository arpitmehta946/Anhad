import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../config.dart';
import '../auth/auth_controller.dart';
import 'background/background_japa_channel.dart' show ActiveSessionInfo;
import 'background/background_japa_controller.dart';
import 'data/daily_japa_total.dart';
import 'data/daily_total_store.dart';
import 'data/isar_provider.dart';
import 'data/japa_api_client.dart';
import 'data/japa_sync_service.dart';
import 'data/local_japa_session.dart';
import 'data/tap_recorder.dart';
import 'japa_streak_controller.dart';

/// One full mala (docs/FRONTEND_GUIDELINES.md §5).
const malaSize = 108;

class JapaSessionState {
  const JapaSessionState({
    this.tapsInRound = 0,
    this.roundsCompleted = 0,
    this.justFilledBeadIndex,
    this.syncFailed = false,
    this.dailyTotal = 0,
    this.sessionId,
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

  /// The Isar row currently being appended to — exposed so starting a
  /// screen-off session can hand this exact id to the native service
  /// (docs/PRD.md §7.4), keeping on-screen and volume-key taps in the same
  /// session rather than two independently-counted ones.
  final int? sessionId;

  JapaSessionState copyWith({
    int? tapsInRound,
    int? roundsCompleted,
    int? justFilledBeadIndex,
    bool clearJustFilledBeadIndex = false,
    bool? syncFailed,
    int? dailyTotal,
    int? sessionId,
  }) {
    return JapaSessionState(
      tapsInRound: tapsInRound ?? this.tapsInRound,
      roundsCompleted: roundsCompleted ?? this.roundsCompleted,
      justFilledBeadIndex: clearJustFilledBeadIndex
          ? null
          : (justFilledBeadIndex ?? this.justFilledBeadIndex),
      syncFailed: syncFailed ?? this.syncFailed,
      dailyTotal: dailyTotal ?? this.dailyTotal,
      sessionId: sessionId ?? this.sessionId,
    );
  }
}

DateTime _nextLocalMidnight() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
}

/// Drives one screen visit's worth of japa taps: persists every tap to Isar
/// immediately (offline-first), tracks the Mala Ring's round progress, and
/// flushes to Postgres when connectivity returns or the session ends —
/// never a network call per tap (docs/TECH_STACK.md §5).
///
/// The current session is watched via Isar's cross-isolate change
/// notifications rather than updated only from [tap] directly, so a
/// volume-key tap recorded by the headless background isolate (screen-off
/// session, docs/PRD.md §7.4) updates the ring and count here exactly the
/// same way an on-screen tap does — there's one source of truth, not two
/// counters that happen to agree only sometimes. That same watcher also
/// drives the lock-screen notification's count (see
/// [BackgroundJapaController.updateNotificationCount]) — the notification
/// used to keep its own separately-incremented counter that only on-screen
/// taps knew to update, so a volume-key tap would advance the ring but not
/// the notification, and the next on-screen tap would push that
/// now-stale counter and clobber whatever the notification actually showed.
class JapaSessionController extends StateNotifier<JapaSessionState> {
  JapaSessionController(
    this._isar,
    this._sync, {
    this.getActiveSessionId,
    this.updateActiveSessionId,
    this.updateNotificationCount,
    this.onSynced,
    Stream<List<ConnectivityResult>>? connectivityChanges,
  })  : _connectivityChanges =
            connectivityChanges ?? Connectivity().onConnectivityChanged,
        super(const JapaSessionState()) {
    _init();
  }

  final Isar _isar;
  final JapaSyncService _sync;

  /// Defaults to the real platform plugin — overridable so tests can drive
  /// connectivity-restored behavior with a plain [Stream] instead of
  /// needing to mock connectivity_plus's platform channel.
  final Stream<List<ConnectivityResult>> _connectivityChanges;

  /// Asks the native service whether a screen-off session is currently
  /// running and, if so, which Isar session id it's targeting (plus its
  /// cumulative base — see [_cumulativeBase]) — so a fresh app open adopts
  /// that session instead of starting a second, separately counted one.
  final Future<ActiveSessionInfo?> Function()? getActiveSessionId;

  /// Tells the native service to retarget an in-progress screen-off session
  /// at a new Isar row, persisting the new cumulative base alongside it —
  /// called after every rotation (_flushCurrentAndRotate). Without the
  /// retarget, a session that outlives one mala keeps writing volume-key
  /// taps to the now-abandoned old row: the notification (native-counted,
  /// unaffected) keeps climbing while the in-app ring (watching the new
  /// row) stalls, until the session is ended and restarted resyncs them by
  /// coincidence. Without persisting the cumulative base too, an
  /// unexpected process restart mid-session would silently drop every tap
  /// already rotated past before the restart.
  final void Function(int newSessionId, int cumulativeBase)? updateActiveSessionId;

  /// Pushes this screen visit's true cumulative tap count to the
  /// notification — called every time the session watcher recomputes
  /// ring/round state, from whichever tap source triggered it. A no-op
  /// (via BackgroundJapaController's own guard) when no screen-off session
  /// is running.
  final void Function(int total)? updateNotificationCount;

  /// Called whenever a batch actually reaches the server — a mala
  /// completion, connectivity restored, or a backlog flushed at startup —
  /// since any of those can be the moment today's total crosses the streak
  /// threshold server-side (docs/PRD.md §7.4, §10.3). japaStreakProvider
  /// listens for this to know when to refetch, rather than fetching once
  /// on screen mount and never again: that once caught the streak a
  /// fraction of a second before a login-time backlog flush created it,
  /// and then never looked again for the rest of the visit.
  final void Function()? onSynced;

  int? _sessionId;

  /// Taps from every row this screen visit has already rotated past (mala
  /// completions, connectivity-triggered flushes) — added to the current
  /// row's own tap count to get a total that climbs continuously across
  /// rotations, since the Isar row itself resets to empty each time
  /// (_flushCurrentAndRotate always starts the replacement fresh). Carried
  /// forward regardless of whether a rotated batch synced or was rejected
  /// — this tracks taps physically made this visit, not confirmed-synced
  /// taps (that distinction is what the daily total, which does exclude
  /// rejected batches, is for).
  int _cumulativeBase = 0;

  /// Exposed so a caller starting a screen-off session (japa_screen.dart)
  /// can hand the native service this exact value to persist, matching
  /// whatever this controller currently has — see [_cumulativeBase].
  int get cumulativeBase => _cumulativeBase;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<LocalJapaSession?>? _sessionWatchSub;
  StreamSubscription<DailyJapaTotal?>? _dailyTotalWatchSub;
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
    // Adopt whatever the native service is already targeting (a screen-off
    // session started before this screen was opened, or still running from
    // before the app was last closed) rather than always creating a fresh
    // session — otherwise reopening the app after chanting screen-off would
    // start counting a second, empty session while the real taps sit in a
    // different row this controller never looks at.
    final info = await getActiveSessionId?.call();
    int sessionId;
    if (info != null && await _isar.localJapaSessions.get(info.sessionId) != null) {
      sessionId = info.sessionId;
      _cumulativeBase = info.cumulativeBase;
    } else {
      final session = LocalJapaSession();
      await _isar.writeTxn(() => _isar.localJapaSessions.put(session));
      sessionId = session.id;
    }
    if (!mounted) return;
    _sessionId = sessionId;
    state = state.copyWith(sessionId: sessionId);

    final current = await _isar.localJapaSessions.get(sessionId);
    if (!mounted) return;
    _applyTapTotal(current?.taps.length ?? 0, triggerFlushOnCompletion: false);
    _watchSession(sessionId);

    await _watchDailyTotal();
    if (!mounted) return;
    _scheduleMidnightRollover();

    // Retry anything left over from a previous run that never made it
    // online. Surface the result: if practice from a prior visit is still
    // stuck locally (e.g. no auth token was ever set), the screen should
    // say so immediately rather than queuing it invisibly forever.
    unawaited(_syncPendingAndReportStatus(excludeId: sessionId));

    _connectivitySub = _connectivityChanges.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(_serialized(_flushCurrentAndRotate));
      }
    });
  }

  /// Recomputes ring/round state — and pushes the notification's count —
  /// from the current row's tap total plus everything already rotated past
  /// this visit. Used at init (no flush — a resumed session may already be
  /// mid- or past-completion and shouldn't re-trigger a flush just for
  /// being loaded) and by the session watcher (does flush — a live crossing
  /// of a mala boundary, from either tap source, is the real completion
  /// event).
  void _applyTapTotal(int rowTotal, {required bool triggerFlushOnCompletion}) {
    final cumulative = _cumulativeBase + rowTotal;
    final rounds = cumulative ~/ malaSize;
    final inRound = cumulative % malaSize;
    final justCompletedRound =
        triggerFlushOnCompletion && inRound == 0 && rowTotal > 0;
    state = state.copyWith(
      tapsInRound: inRound,
      roundsCompleted: rounds,
      justFilledBeadIndex: inRound == 0 ? malaSize - 1 : inRound - 1,
    );
    updateNotificationCount?.call(cumulative);
    if (justCompletedRound) {
      // A completed mala is a natural checkpoint — sync it now rather than
      // waiting for the user to leave the screen or a connectivity change.
      unawaited(_serialized(_flushCurrentAndRotate));
    }
  }

  void _watchSession(int id) {
    unawaited(_sessionWatchSub?.cancel());
    _sessionWatchSub = _isar.localJapaSessions
        .watchObject(id, fireImmediately: false)
        .listen((session) {
      if (!mounted) return;
      if (session == null) {
        // The row we were watching is gone. This isn't a rotation we
        // triggered ourselves (those already create the replacement and
        // re-subscribe before the old row is deleted) — it means some
        // other flush of this same id completed out from under us, most
        // plausibly a previous controller instance's dispose-time flush
        // (fire-and-forget, so it can outlive that instance) finishing
        // after this instance already adopted the same session on
        // startup. Left unhandled, the ring stays stuck showing whatever
        // it last displayed until something else forces a re-derivation
        // (e.g. a full app restart) — self-heal immediately instead.
        unawaited(_startFreshSession());
        return;
      }
      _applyTapTotal(session.taps.length, triggerFlushOnCompletion: true);
    });
  }

  Future<void> _startFreshSession() async {
    final fresh = LocalJapaSession();
    await _isar.writeTxn(() => _isar.localJapaSessions.put(fresh));
    if (!mounted) return;
    _sessionId = fresh.id;
    state = state.copyWith(sessionId: fresh.id);
    _applyTapTotal(0, triggerFlushOnCompletion: false);
    _watchSession(fresh.id);
    updateActiveSessionId?.call(fresh.id, _cumulativeBase);
  }

  Future<void> _watchDailyTotal() async {
    final row = await todayTotalRow(_isar);
    if (!mounted) return;
    state = state.copyWith(dailyTotal: row.totalTaps);
    unawaited(_dailyTotalWatchSub?.cancel());
    _dailyTotalWatchSub = _isar.dailyJapaTotals
        .watchObject(row.id, fireImmediately: false)
        .listen((updated) {
      if (updated == null || !mounted) return;
      state = state.copyWith(dailyTotal: updated.totalTaps);
    });
  }

  Future<void> _syncPendingAndReportStatus({required int excludeId}) async {
    final result =
        await _serialized(() => _sync.flushPending(excludeId: excludeId));
    if (result.rejectedTaps > 0) {
      await adjustDailyTotal(_isar, -result.rejectedTaps);
    }
    // This is exactly the login-time backlog-catch-up path — unconditional
    // since a queued batch from a prior visit reaching the server here is
    // precisely the kind of update the streak needs to know about.
    onSynced?.call();
    if (!mounted) return;
    state = state.copyWith(syncFailed: result.stillQueued);
  }

  /// Re-derives today's total at the next local midnight, and again after
  /// that — covers the screen being left open across the day boundary,
  /// not just a restart the next day.
  void _scheduleMidnightRollover() {
    final delay = _nextLocalMidnight().difference(DateTime.now()) +
        const Duration(seconds: 1);
    _midnightTimer = Timer(delay, () {
      unawaited(_watchDailyTotal());
      _scheduleMidnightRollover();
    });
  }

  Future<void> tap() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    await recordTapInIsar(_isar, sessionId);
    // The await above is a suspension point: the screen may have been
    // popped (disposing this controller) while it was in flight. The tap's
    // Isar write already landed either way, so it's safe to just stop here
    // — ring/count/daily-total/notification updates all arrive via the
    // watchers set up in _init, regardless of which input method (on-screen
    // or, for a screen-off session, a volume key) produced this tap.
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
      await adjustDailyTotal(_isar, -tapCount);
    }
    if (outcome == FlushOutcome.synced) {
      onSynced?.call();
    }
    if (outcome != FlushOutcome.stillQueued) {
      // Carry the rotated row's count forward regardless of sync outcome —
      // the ring/notification track taps physically made this visit, not
      // confirmed-synced taps (adjustDailyTotal above is what excludes a
      // rejected batch from the figure that does need to mean "confirmed").
      _cumulativeBase += tapCount;
      final fresh = LocalJapaSession();
      await _isar.writeTxn(() => _isar.localJapaSessions.put(fresh));
      if (!mounted) return;
      _sessionId = fresh.id;
      state = state.copyWith(sessionId: fresh.id);
      _watchSession(fresh.id);
      updateActiveSessionId?.call(fresh.id, _cumulativeBase);
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
      await adjustDailyTotal(_isar, -tapCount);
    }
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    unawaited(_connectivitySub?.cancel());
    unawaited(_sessionWatchSub?.cancel());
    unawaited(_dailyTotalWatchSub?.cancel());
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
  final background = ref.watch(backgroundJapaControllerProvider.notifier);
  final controller = JapaSessionController(
    isar,
    sync,
    getActiveSessionId: background.getActiveSessionId,
    updateActiveSessionId: background.updateActiveSessionId,
    updateNotificationCount: background.updateNotificationCount,
    onSynced: () => ref.invalidate(japaStreakProvider),
  );
  // No ref.onDispose(controller.dispose) here — StateNotifierProvider
  // already disposes the notifier it creates automatically. Registering it
  // again double-calls dispose(), and the second call trips
  // StateNotifier's own "already disposed" assertion (surfaced as an
  // uncaught "Tried to use JapaSessionController after `dispose` was
  // called" whenever this provider actually got torn down and recreated,
  // which earlier testing apparently never happened to trigger).
  return controller;
});
