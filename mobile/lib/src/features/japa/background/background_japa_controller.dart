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
  }

  final BackgroundJapaChannel _channel;

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

  Future<void> start(int currentCount) async {
    await _channel.startSession(count: currentCount);
    if (!mounted) return;
    state = BackgroundJapaState(active: true, totalTaps: currentCount);
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
