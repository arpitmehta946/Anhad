import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  BackgroundJapaController(this._channel) : super(const BackgroundJapaState()) {
    _channel.onStateChanged = _onStateChanged;
    _restoreActiveSession();
  }

  final BackgroundJapaChannel _channel;

  /// A fresh app open (or reopen mid-session) always starts with `active:
  /// false` in memory — this reconciles it with reality if the native
  /// service is actually still running a session from before, so the
  /// toggle reflects what's really happening rather than defaulting to
  /// "off" until the user notices and touches it.
  Future<void> _restoreActiveSession() async {
    final activeId = await _channel.getActiveSessionId();
    if (activeId == null || !mounted) return;
    state = state.copyWith(active: true);
  }

  void _onStateChanged(bool paused, bool ended) {
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

  Future<void> start({required int sessionId, required int currentCount}) async {
    await _channel.startSession(sessionId: sessionId, count: currentCount);
    if (!mounted) return;
    state = BackgroundJapaState(active: true, totalTaps: currentCount);
  }

  /// The Isar session id the native service is targeting right now, or
  /// null if no screen-off session is running — used by
  /// JapaSessionController on init to adopt an already-running session
  /// instead of starting a second, separately-counted one.
  Future<int?> getActiveSessionId() => _channel.getActiveSessionId();

  /// Tells the native service (and its headless isolate) to retarget an
  /// in-progress session at a different Isar row. Called by
  /// JapaSessionController whenever it rotates to a fresh session — a
  /// no-op if no screen-off session is actually running, so callers don't
  /// need to check first.
  void updateActiveSessionId(int newSessionId) {
    if (!state.active) return;
    unawaited(_channel.updateSessionId(newSessionId));
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
    if (!mounted) return;
    state = const BackgroundJapaState();
  }

  /// Called for every tap recorded while a session is active — on-screen
  /// today, volume-key captured once phase 2 lands — so the notification
  /// stays live regardless of where the tap came from. A no-op when no
  /// session is running or it's paused.
  void recordTap() {
    if (!state.active || state.paused) return;
    final updated = state.totalTaps + 1;
    state = state.copyWith(totalTaps: updated);
    unawaited(_channel.updateCount(updated));
  }
}

final backgroundJapaChannelProvider =
    Provider<BackgroundJapaChannel>((ref) => BackgroundJapaChannel());

final backgroundJapaControllerProvider = StateNotifierProvider<
    BackgroundJapaController, BackgroundJapaState>(
  (ref) => BackgroundJapaController(ref.watch(backgroundJapaChannelProvider)),
);
