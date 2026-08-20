import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../config.dart';
import '../auth/auth_controller.dart';
import 'background/background_japa_channel.dart'
    show ActiveSessionInfo, JapaCompletionKind;
import 'background/background_japa_controller.dart';
import 'data/daily_japa_total.dart';
import 'data/daily_total_store.dart';
import 'data/isar_provider.dart';
import 'data/japa_api_client.dart';
import 'data/japa_sync_service.dart';
import 'data/japa_preferences_store.dart';
import 'data/local_japa_session.dart';
import 'data/tap_recorder.dart';
import 'japa_streak_controller.dart';

/// The traditional default mala length (docs/FRONTEND_GUIDELINES.md §5) —
/// used before the persisted preference has loaded, and as the fallback if
/// none is set. The actual active length is [JapaSessionState.malaLength],
/// which is per-user (docs/ONBOARDING.md §1.3: 27/54/108/1008).
const malaSize = 108;

class JapaSessionState {
  const JapaSessionState({
    this.tapsInRound = 0,
    this.roundsCompleted = 0,
    this.malaLength = malaSize,
    this.justFilledBeadIndex,
    this.syncFailed = false,
    this.dailyTotal = 0,
    this.sessionId,
  });

  /// Beads filled in the ring for the current, in-progress round (0-107).
  final int tapsInRound;

  /// Full malas completed so far this screen visit.
  final int roundsCompleted;

  /// Beads per round — the user's persisted preference (docs/ONBOARDING.md
  /// §1.3: 27/54/108/1008), not a fixed constant. Changing it recomputes
  /// [tapsInRound]/[roundsCompleted] from the same cumulative tap total
  /// against the new length — no taps are added, lost, or reassigned, but
  /// the round-boundary display does jump to reflect the new chunking.
  final int malaLength;

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
    int? malaLength,
    int? justFilledBeadIndex,
    bool clearJustFilledBeadIndex = false,
    bool? syncFailed,
    int? dailyTotal,
    int? sessionId,
  }) {
    return JapaSessionState(
      tapsInRound: tapsInRound ?? this.tapsInRound,
      roundsCompleted: roundsCompleted ?? this.roundsCompleted,
      malaLength: malaLength ?? this.malaLength,
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

/// Mirrors JapaBellPlayer.completionKind on the native side exactly — see
/// its doc for the full reasoning. Kept in sync deliberately rather than
/// shared, since one runs in the Dart isolate (no screen-off session) and
/// the other natively (screen-off session active); duplicating a few lines
/// of pure logic is simpler than threading a shared implementation across
/// that boundary.
JapaCompletionKind? _completionKind(int oldCount, int newCount, int malaLength) {
  if (newCount <= oldCount || malaLength <= 0) return null;
  final ringLength = malaLength < malaSize ? malaLength : malaSize;
  if (newCount ~/ malaLength > oldCount ~/ malaLength) {
    return JapaCompletionKind.target;
  }
  if (newCount ~/ ringLength > oldCount ~/ ringLength) {
    return JapaCompletionKind.round;
  }
  return null;
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
    this.updateMalaLength,
    this.updateNotificationCount,
    this.onSynced,
    this.onCompletion,
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

  /// Pushes a mala-length change to the native service immediately —
  /// called from [setMalaLength]; see [BackgroundJapaController.updateMalaLength].
  final void Function(int malaLength)? updateMalaLength;

  /// Pushes this screen visit's true cumulative tap count to the
  /// notification — called every time the session watcher recomputes
  /// ring/round state, from whichever tap source triggered it. A no-op
  /// (via BackgroundJapaController's own guard) when no screen-off session
  /// is running.
  final void Function(int total, int malaLength)? updateNotificationCount;

  /// Called whenever a batch actually reaches the server — a mala
  /// completion, connectivity restored, or a backlog flushed at startup —
  /// since any of those can be the moment today's total crosses the streak
  /// threshold server-side (docs/PRD.md §7.4, §10.3). japaStreakProvider
  /// listens for this to know when to refetch, rather than fetching once
  /// on screen mount and never again: that once caught the streak a
  /// fraction of a second before a login-time backlog flush created it,
  /// and then never looked again for the rest of the visit.
  final void Function()? onSynced;

  /// Fired on a *live* crossing of a round or target boundary (never on
  /// init/resume/a mala-length switch re-chunking the same total — see the
  /// triggerFlushOnCompletion gate in [_applyTapTotal]) — docs/ONBOARDING.md
  /// §5 item 1. The provider wiring is what decides whether this actually
  /// plays a sound directly or is a no-op: JapaForegroundService already
  /// owns completion sounds for every tap source once a screen-off session
  /// is active, so playing it again here too would double it up.
  final void Function(JapaCompletionKind kind)? onCompletion;

  int? _sessionId;

  /// The active mala length (docs/ONBOARDING.md §1.3) — loaded from the
  /// persisted preference in [_init], changeable via [setMalaLength].
  /// Deliberately not part of [_cumulativeBase]'s math: it only changes how
  /// the same cumulative total is chunked into rounds, via [_applyTapTotal].
  int _malaLength = malaSize;

  /// The current row's own tap count as of the last [_applyTapTotal] call —
  /// cached so [setMalaLength] can immediately re-chunk the display against
  /// the new length without waiting for the next tap to trigger a fresh
  /// watcher notification.
  int _lastRowTotal = 0;

  /// The cumulative total as of the last [_applyTapTotal] call — compared
  /// against the new cumulative each time to detect a completion boundary
  /// crossing (rather than cumulative % x == 0, which a multi-tap jump
  /// between two calls could step past without ever landing exactly on).
  int _lastCumulative = 0;

  /// Taps from every *synced* row this screen visit has already rotated
  /// past (mala completions, connectivity-triggered flushes) — added to
  /// the current row's own tap count to get a total that climbs
  /// continuously across rotations, since the Isar row itself resets to
  /// empty each time (_flushCurrentAndRotate always starts the
  /// replacement fresh). A rejected batch is deliberately *not* carried
  /// in here — it never happened as far as the ring/round display is
  /// concerned, matching the daily total (which also excludes it via
  /// adjustDailyTotal). A batch still queued (offline, no auth yet) stays
  /// out of both until it actually resolves one way or the other.
  int _cumulativeBase = 0;

  /// Exposed so a caller starting a screen-off session (japa_screen.dart)
  /// can hand the native service this exact value to persist, matching
  /// whatever this controller currently has — see [_cumulativeBase].
  int get cumulativeBase => _cumulativeBase;

  /// The true cumulative total for this screen visit — [_cumulativeBase]
  /// plus the current row's own tap count. Distinct from the ring's
  /// roundsCompleted/tapsInRound, which chunk this same total by the ring
  /// length (108, or the mala length itself if shorter — see
  /// [_applyTapTotal]), not the mala length directly: reconstructing this
  /// value from roundsCompleted/tapsInRound would need to know the ring
  /// length too, so callers that need the real total (starting a
  /// screen-off session's notification baseline) should read this instead.
  int get cumulativeTotal => _cumulativeBase + _lastRowTotal;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<LocalJapaSession?>? _sessionWatchSub;
  StreamSubscription<DailyJapaTotal?>? _dailyTotalWatchSub;
  Timer? _midnightTimer;

  /// True for the span of [_flushCurrentAndRotate]'s own flush attempt —
  /// see [_watchSession]'s doc for exactly what race this closes.
  bool _rotating = false;

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
    _malaLength = await malaLengthPreferred(_isar);
    if (!mounted) return;
    state = state.copyWith(malaLength: _malaLength);

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
      // The ring shows today's real progress, not just "since this app
      // happens to have been opened" — seeding from anything else meant
      // every reopen after an earlier session the same day showed a ring
      // that had silently reset while "chants today" kept climbing, which
      // reads as data loss even though nothing was actually lost. A fresh
      // session's ring now picks up exactly where today's already-
      // confirmed total left off.
      final todayRow = await todayTotalRow(_isar);
      _cumulativeBase = todayRow.totalTaps;
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
    unawaited(_syncPendingAndReportStatus());

    _connectivitySub = _connectivityChanges.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(_serialized(_flushCurrentAndRotate));
      }
    });
  }

  /// Recomputes ring/round state — and pushes the notification's count —
  /// from the current row's tap total plus everything already rotated past
  /// this visit. Used at init (no flush, no completion sound — a resumed
  /// session may already be mid- or past-completion and shouldn't replay
  /// either just for being loaded) and by the session watcher (does both —
  /// a live crossing of a boundary, from either tap source, is the real
  /// completion event).
  ///
  /// The ring itself always cycles every [_ringLength] beads (108, or the
  /// mala length itself if that's shorter) rather than the raw mala length
  /// — a 1008-length "target" is traditionally counted as repeated malas,
  /// not one ring of 1008 beads (docs/ONBOARDING.md §5), and this is also
  /// what keeps a natural sync checkpoint every 108 taps for a long
  /// session instead of one large batch built up over 1008.
  void _applyTapTotal(int rowTotal, {required bool triggerFlushOnCompletion}) {
    _lastRowTotal = rowTotal;
    final cumulative = _cumulativeBase + rowTotal;
    final ringLength = _ringLength;
    final rounds = cumulative ~/ ringLength;
    final inRound = cumulative % ringLength;
    final justCompletedRound =
        triggerFlushOnCompletion && inRound == 0 && rowTotal > 0;
    state = state.copyWith(
      tapsInRound: inRound,
      roundsCompleted: rounds,
      malaLength: _malaLength,
      justFilledBeadIndex: inRound == 0 ? ringLength - 1 : inRound - 1,
    );
    updateNotificationCount?.call(cumulative, _malaLength);
    if (triggerFlushOnCompletion) {
      final kind = _completionKind(_lastCumulative, cumulative, _malaLength);
      if (kind != null) onCompletion?.call(kind);
    }
    _lastCumulative = cumulative;
    if (justCompletedRound) {
      // A completed mala is a natural checkpoint — sync it now rather than
      // waiting for the user to leave the screen or a connectivity change.
      unawaited(_serialized(_flushCurrentAndRotate));
    }
  }

  /// The ring's own bead count — see [_applyTapTotal]'s doc for why this
  /// isn't always just [_malaLength].
  int get _ringLength => _malaLength < malaSize ? _malaLength : malaSize;

  void _watchSession(int id) {
    unawaited(_sessionWatchSub?.cancel());
    _sessionWatchSub = _isar.localJapaSessions
        .watchObject(id, fireImmediately: false)
        .listen((session) {
      if (!mounted) return;
      // A rotation we triggered ourselves (_flushCurrentAndRotate,
      // _startFreshSession) always reassigns _sessionId and calls
      // _watchSession again *before* deleting the old row — but that
      // delete's own notification can still be in flight on this old
      // subscription when it happens (cancel() above is unawaited, and
      // even awaited, Isar's watch stream doesn't guarantee a cancelled
      // subscription can't already have a pending event queued). Without
      // this check, that stray "gone" notification for an id we've
      // already rotated *away from* looks identical to the genuine
      // "something else deleted our current session out from under us"
      // case below, and self-heals into a spurious extra session that
      // clobbers the real one — observed as taps silently going nowhere
      // right after a rejected batch rotated the session.
      if (id != _sessionId) return;
      if (session == null) {
        if (_rotating) {
          // This id's own row is being deleted as part of a rotation
          // this controller itself already has in flight
          // (_flushCurrentAndRotate) — that rotation will reassign
          // _sessionId and call _watchSession again once it knows the
          // flush outcome. Self-healing here too would create a second,
          // competing session before the real one exists, and the real
          // rotation's later reassignment would then orphan whichever one
          // actually received the next tap.
          return;
        }
        // The row we were watching is gone, and it's still the row we
        // think is current — genuinely another flush of this same id
        // completed out from under us, most plausibly a previous
        // controller instance's dispose-time flush (fire-and-forget, so
        // it can outlive that instance) finishing after this instance
        // already adopted the same session on startup. Left unhandled,
        // the ring stays stuck showing whatever it last displayed until
        // something else forces a re-derivation (e.g. a full app
        // restart) — self-heal immediately instead.
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

  /// Deliberately takes no `excludeId` parameter — reads [_sessionId] live,
  /// inside the closure `_serialized` eventually invokes, rather than a
  /// value frozen at call time. This is `unawaited`-called from [_init]
  /// well before it actually runs (queued behind whatever's already ahead
  /// of it on [_flushChain]), and a live round completion can rotate
  /// [_sessionId] to a brand new row in the meantime — a frozen id would
  /// then exclude a session that's already gone, leaving the sweep free to
  /// flush (and, for an empty row, delete) the session that's actually
  /// current and still being tapped into.
  Future<void> _syncPendingAndReportStatus() async {
    final result =
        await _serialized(() => _sync.flushPending(excludeId: _sessionId));
    if (result.rejectedTaps > 0) {
      await adjustDailyTotal(_isar, -result.rejectedTaps);
      // These leftover sessions' taps were already folded into
      // _cumulativeBase's initial seed (today's confirmed total at
      // _init) before this sweep ever ran — a rejection discovered here
      // needs the exact same correction _flushCurrentAndRotate makes for
      // a live rejection, or the ring would keep showing a total today's
      // figure has already excluded.
      _cumulativeBase -= result.rejectedTaps;
      if (mounted) _applyTapTotal(_lastRowTotal, triggerFlushOnCompletion: false);
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
      unawaited(_handleMidnightRollover());
      _scheduleMidnightRollover();
    });
  }

  /// The ring resets to zero for a new day too, not just the daily total
  /// — otherwise leaving the screen open across midnight would have the
  /// ring keep counting on top of yesterday's base forever, the exact
  /// "ring vs. today's total" mismatch _cumulativeBase's seeding at
  /// _init exists to prevent, just triggered by staying open instead of
  /// reopening.
  Future<void> _handleMidnightRollover() async {
    final sessionIdBeforeFlush = _sessionId;
    await _serialized(_flushCurrentAndRotate);
    if (!mounted) return;
    if (_sessionId != sessionIdBeforeFlush) {
      // Rotated cleanly onto a genuinely empty row — today really does
      // start at zero.
      _cumulativeBase = 0;
      _applyTapTotal(0, triggerFlushOnCompletion: false);
    }
    // If it didn't rotate (still offline/queued), yesterday's row and
    // cumulative base are left exactly as they were rather than
    // discarding taps that are still only sitting locally — the next
    // successful flush (whenever connectivity returns) rotates normally,
    // and ordinary daily-total re-derivation below still keeps the
    // *displayed total* correct in the meantime either way.
    await _watchDailyTotal();
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

  /// Corrects an accidental tap — see [undoLastTapInIsar] for exactly what
  /// this can and can't reach. Returns whether anything was actually
  /// undone, so the caller can tell the difference from "nothing to undo."
  Future<bool> undoLastTap() async {
    final sessionId = _sessionId;
    if (sessionId == null) return false;
    return undoLastTapInIsar(_isar, sessionId);
  }

  /// Changes the active mala length (docs/ONBOARDING.md §1.3) and persists
  /// it as the standing preference. Re-chunks the *same* cumulative total
  /// against the new length immediately, using the row total cached from
  /// the last watcher notification rather than waiting for the next tap —
  /// no taps are added, dropped, or reassigned, but tapsInRound/
  /// roundsCompleted will jump to reflect the new grouping.
  Future<void> setMalaLength(int length) async {
    _malaLength = length;
    await setMalaLengthPreferred(_isar, length);
    updateMalaLength?.call(length);
    if (!mounted) return;
    _applyTapTotal(_lastRowTotal, triggerFlushOnCompletion: false);
  }

  /// Retries whatever's still queued locally now that an auth token exists
  /// — called right after a successful sign-in partway through the first-run
  /// flow (docs/ONBOARDING.md §7), since the mala chanted *before* that
  /// account existed is otherwise just sitting in Isar waiting for the next
  /// natural trigger (a connectivity change or the next mala completing),
  /// which could be a while. A no-op before [_init] has set [_sessionId].
  Future<void> retryPendingSync() {
    if (_sessionId == null) return Future.value();
    return _syncPendingAndReportStatus();
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
    // Stays true for this whole function, not just the flushSession call
    // below — the delete it can trigger doesn't necessarily notify this
    // controller's watcher strictly within that one await; it can land on
    // a later microtask, any time up until _watchSession is pointed
    // elsewhere further down. Clearing the flag too early left exactly
    // that gap open.
    _rotating = true;
    try {
      final outcome = await _sync.flushSession(session);
      if (mounted) {
        state =
            state.copyWith(syncFailed: outcome == FlushOutcome.stillQueued);
      }
      if (outcome == FlushOutcome.rejected) {
        await adjustDailyTotal(_isar, -tapCount);
      }
      if (outcome == FlushOutcome.synced) {
        onSynced?.call();
      }
      if (outcome != FlushOutcome.stillQueued) {
        // A rejected batch never happened as far as the ring/round display
        // is concerned either — carrying it into _cumulativeBase anyway
        // used to leave the ring showing rounds/beads that today's total
        // (correctly, via adjustDailyTotal above) didn't count, with no
        // visible explanation for the gap. Only a synced batch counts
        // toward what the ring shows going forward.
        if (outcome == FlushOutcome.synced) {
          _cumulativeBase += tapCount;
        }
        final fresh = LocalJapaSession();
        await _isar.writeTxn(() => _isar.localJapaSessions.put(fresh));
        if (!mounted) return;
        _sessionId = fresh.id;
        state = state.copyWith(sessionId: fresh.id);
        _watchSession(fresh.id);
        updateActiveSessionId?.call(fresh.id, _cumulativeBase);
        if (outcome == FlushOutcome.rejected) {
          // The watcher on the fresh (empty) row won't fire on its own
          // until the next tap — re-derive the ring/round display against
          // the corrected cumulative right away instead of leaving it
          // showing the pre-correction count until then.
          _applyTapTotal(0, triggerFlushOnCompletion: false);
        }
      }
    } finally {
      _rotating = false;
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
    updateMalaLength: background.updateMalaLength,
    updateNotificationCount: background.updateNotificationCount,
    onSynced: () => ref.invalidate(japaStreakProvider),
    onCompletion: background.playCompletionSound,
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
