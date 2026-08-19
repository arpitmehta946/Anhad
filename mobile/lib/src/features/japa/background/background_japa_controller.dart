import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../data/isar_provider.dart';
import '../data/japa_preferences_store.dart';
import 'background_japa_channel.dart';

class BackgroundJapaState {
  const BackgroundJapaState({
    this.active = false,
    this.paused = false,
    this.totalTaps = 0,
  });

  /// The foreground service is running a session right now.
  final bool active;

  /// Session is active but paused (via the notification's Pause button or
  /// the in-app equivalent).
  final bool paused;

  /// Taps recorded since this screen-off session started — deliberately a
  /// plain running total, not the mala-ring's 0-107 round progress, so the
  /// lock-screen notification counts up rather than resetting every 108
  /// like the in-app ring does.
  final int totalTaps;

  BackgroundJapaState copyWith({bool? active, bool? paused, int? totalTaps}) =>
      BackgroundJapaState(
        active: active ?? this.active,
        paused: paused ?? this.paused,
        totalTaps: totalTaps ?? this.totalTaps,
      );
}

/// Owns the screen-off japa session lifecycle: starting it (after checking
/// the battery-optimization exemption), reflecting pause/end actions that
/// arrive from the notification's buttons rather than the in-app UI, and
/// keeping the notification's live count in sync with every tap recorded
/// while the session is active.
class BackgroundJapaController extends StateNotifier<BackgroundJapaState> {
  BackgroundJapaController(this._channel, this._isar)
      : super(const BackgroundJapaState()) {
    _channel.onStateChanged = _onStateChanged;
    _restoreActiveSession();
  }

  final BackgroundJapaChannel _channel;
  final Isar _isar;

  /// Whether the user's standing preference (docs/PRD.md §7.4) is for
  /// screen-off japa to be on — independent of whether a session actually
  /// happens to be running right now. Off by default for a new user; set to
  /// on/off by [start]/[end] respectively, since those are the explicit
  /// "turn it on"/"turn it off" actions this preference should track.
  Future<bool> isScreenOffPreferred() => screenOffPreferred(_isar);

  /// A fresh app open (or reopen mid-session) always starts with `active:
  /// false` in memory — this reconciles it with reality if the native
  /// service is actually still running a session from before, so the
  /// toggle reflects what's really happening rather than defaulting to
  /// "off" until the user notices and touches it.
  Future<void> _restoreActiveSession() async {
    final info = await _channel.getActiveSessionId();
    if (info == null || !mounted) return;
    state = state.copyWith(active: true);
  }

  void _onStateChanged(bool paused, bool ended) {
    if (ended) {
      // Ended from the notification's own End button, not the in-app
      // toggle — still an explicit "turn it off," so the standing
      // preference needs to follow it the same way [end] does.
      unawaited(setScreenOffPreferred(_isar, false));
    }
    if (!mounted) return;
    if (ended) {
      state = const BackgroundJapaState();
    } else {
      state = state.copyWith(paused: paused);
    }
  }

  /// True if the standard Android battery-optimization exemption still
  /// needs to be requested. Callers should show an explanation before
  /// calling [requestBatteryExemption] — the system prompt alone doesn't
  /// say why the app is asking.
  Future<bool> needsBatteryExemption() async {
    return !await _channel.isIgnoringBatteryOptimizations();
  }

  Future<void> requestBatteryExemption() =>
      _channel.requestIgnoreBatteryOptimizations();

  Future<bool> hasNotificationPermission() =>
      _channel.isNotificationPermissionGranted();

  Future<bool> requestNotificationPermission() =>
      _channel.requestNotificationPermission();

  Future<void> start({
    required int sessionId,
    required int currentCount,
    required int cumulativeBase,
    required int malaLength,
  }) async {
    await _channel.startSession(
      sessionId: sessionId,
      count: currentCount,
      cumulativeBase: cumulativeBase,
      malaLength: malaLength,
    );
    await setScreenOffPreferred(_isar, true);
    if (!mounted) return;
    state = BackgroundJapaState(active: true, totalTaps: currentCount);
  }

  /// What the native service is targeting right now, or null if no
  /// screen-off session is running — used by JapaSessionController on init
  /// to adopt an already-running session (and restore its cumulative base)
  /// instead of starting a second, separately-counted one.
  Future<ActiveSessionInfo?> getActiveSessionId() => _channel.getActiveSessionId();

  /// Tells the native service (and its headless isolate) to retarget an
  /// in-progress session at a different Isar row, persisting the new
  /// cumulative base alongside it so it survives an unexpected process
  /// restart too. Called by JapaSessionController whenever it rotates to a
  /// fresh session — a no-op if no screen-off session is actually running,
  /// so callers don't need to check first.
  void updateActiveSessionId(int newSessionId, int cumulativeBase) {
    if (!state.active) return;
    unawaited(_channel.updateSessionId(newSessionId, cumulativeBase));
  }

  /// Pushes a mala-length change to the native service immediately — a
  /// no-op when no screen-off session is running, so callers don't need to
  /// check first. See [BackgroundJapaChannel.updateMalaLength].
  void updateMalaLength(int malaLength) {
    if (!state.active) return;
    unawaited(_channel.updateMalaLength(malaLength));
  }

  Future<void> pause() async {
    await _channel.pause();
    if (!mounted) return;
    state = state.copyWith(paused: true);
  }

  Future<void> resume() async {
    await _channel.resume();
    if (!mounted) return;
    state = state.copyWith(paused: false);
  }

  Future<void> end() async {
    await _channel.end();
    await setScreenOffPreferred(_isar, false);
    if (!mounted) return;
    state = const BackgroundJapaState();
  }

  /// Pushes this screen visit's true cumulative tap count — from
  /// JapaSessionController, which derives it from Isar the same way it
  /// derives the ring's count — to the native notification. A no-op when
  /// no screen-off session is running.
  ///
  /// Deliberately doesn't gate on `state.paused`: pause only stops the
  /// native service from counting *volume-key* presses (see
  /// JapaForegroundService's onAdjustVolume) — it was never meant to
  /// suppress on-screen taps, which reach Isar the same way regardless of
  /// the screen-off session's pause state. Previously this method
  /// maintained its own incrementing counter (`totalTaps`) rather than
  /// taking a value, which is what let it drift from reality: a
  /// volume-key tap updated the notification directly in native code
  /// without this counter ever finding out, so the next on-screen tap
  /// would push its own now-stale value and clobber whatever the
  /// notification actually showed.
  void updateNotificationCount(int total, int malaLength) {
    if (!state.active) return;
    state = state.copyWith(totalTaps: total);
    unawaited(_channel.updateCount(total, malaLength));
  }

  /// Plays a completion sound (and its distinct haptic) directly from the
  /// foreground — a no-op (deliberately) while a screen-off session is
  /// active, since JapaForegroundService already owns both for every tap
  /// source in that case; see [_channel]'s playCompletionSound doc. The
  /// haptic fires unconditionally alongside the sound request — it has no
  /// privacy concern the way audio does, so it isn't gated on headphones.
  void playCompletionSound(JapaCompletionKind kind) {
    if (state.active) return;
    HapticFeedback.heavyImpact();
    unawaited(_channel.playCompletionSound(kind));
  }

  Future<bool> shouldShowHeadphoneHint() => _channel.shouldShowHeadphoneHint();
}

final backgroundJapaChannelProvider =
    Provider<BackgroundJapaChannel>((ref) => BackgroundJapaChannel());

final backgroundJapaControllerProvider = StateNotifierProvider<
    BackgroundJapaController, BackgroundJapaState>(
  (ref) => BackgroundJapaController(
    ref.watch(backgroundJapaChannelProvider),
    ref.watch(isarProvider),
  ),
);
