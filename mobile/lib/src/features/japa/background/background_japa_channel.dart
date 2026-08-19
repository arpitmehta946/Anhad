import 'package:flutter/services.dart';

/// The two tiers of completion sound (docs/ONBOARDING.md §5 item 1) — a
/// round is every 108 beads, a target is the user's chosen mala length
/// (27/54/108/1008). They coincide at malaLength == 108 ("one strike," see
/// [JapaCompletionKind.target]'s priority in the native completionKind
/// check), and round never fires below 108 (malaLength 27/54: target only).
enum JapaCompletionKind {
  round,
  target;

  String get wireValue => name;
}

/// What the native service is currently targeting, restored on app open —
/// see [BackgroundJapaChannel.getActiveSessionId].
class ActiveSessionInfo {
  const ActiveSessionInfo({required this.sessionId, required this.cumulativeBase});

  final int sessionId;

  /// Taps from every row already rotated past this screen-off session,
  /// persisted natively alongside the session id so it survives an
  /// unexpected process restart mid-session, not just an explicit End.
  final int cumulativeBase;
}

/// Talks to [JapaForegroundService] on the Android side (docs/PRD.md §7.4):
/// starts/stops the foreground service that keeps a japa session alive and
/// its notification visible with the screen off, and checks/requests the
/// battery-optimization exemption Samsung/Android otherwise use to kill it
/// mid-session. Phase 1 only — the notification's count is not yet backed
/// by real volume-key taps.
class BackgroundJapaChannel {
  BackgroundJapaChannel() {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  static const _channel = MethodChannel('com.anhad.anhad/japa_background');

  /// Fired when a notification button (pause/resume/end) is tapped —
  /// `{'paused': bool, 'ended': bool}`. Only reaches this listener while
  /// the app process is alive; the notification itself keeps working
  /// (via the service) regardless.
  void Function(bool paused, bool ended)? onStateChanged;

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method == 'onStateChanged') {
      final args = (call.arguments as Map).cast<String, dynamic>();
      onStateChanged?.call(
        args['paused'] as bool? ?? false,
        args['ended'] as bool? ?? false,
      );
    }
  }

  Future<void> startSession({
    required int sessionId,
    required int count,
    required int cumulativeBase,
    required int malaLength,
  }) =>
      _channel.invokeMethod(
        'startSession',
        {
          'sessionId': sessionId,
          'count': count,
          'cumulativeBase': cumulativeBase,
          'malaLength': malaLength,
        },
      );

  /// What the native service is currently targeting, or null if no
  /// screen-off session is running — read from SharedPreferences on the
  /// native side rather than a live service binding, so it answers
  /// correctly even if the service isn't currently running.
  Future<ActiveSessionInfo?> getActiveSessionId() async {
    final result = await _channel.invokeMethod('getActiveSessionId');
    if (result == null) return null;
    final map = (result as Map).cast<String, dynamic>();
    return ActiveSessionInfo(
      sessionId: map['sessionId'] as int,
      cumulativeBase: map['cumulativeBase'] as int,
    );
  }

  /// Retargets an already-running session at a different Isar row —
  /// needed because JapaSessionController rotates to a fresh session every
  /// time a mala completes or connectivity is restored (see
  /// _flushCurrentAndRotate), and without this the native service and its
  /// headless isolate would keep appending taps to the old, abandoned row
  /// nobody is watching anymore.
  Future<void> updateSessionId(int sessionId, int cumulativeBase) =>
      _channel.invokeMethod(
        'updateSessionId',
        {'sessionId': sessionId, 'cumulativeBase': cumulativeBase},
      );

  /// Pushes a mala-length change immediately rather than waiting for the
  /// next [updateCount] call — without this, a screen-off session driven
  /// purely by volume-key taps (which never go through updateCount) could
  /// keep checking completion boundaries against the length that was
  /// active when the session started, well after the user switched it.
  Future<void> updateMalaLength(int malaLength) =>
      _channel.invokeMethod('updateMalaLength', {'malaLength': malaLength});

  Future<void> pause() => _channel.invokeMethod('pause');

  Future<void> resume() => _channel.invokeMethod('resume');

  Future<void> end() => _channel.invokeMethod('end');

  Future<void> updateCount(int count, int malaLength) => _channel.invokeMethod(
        'updateCount',
        {'count': count, 'malaLength': malaLength},
      );

  /// Plays a completion sound directly — only meaningful (and only ever
  /// called) when no screen-off session is active, since
  /// JapaForegroundService already owns completion sounds for every tap
  /// source once one is running (docs/ONBOARDING.md §5 item 1).
  Future<void> playCompletionSound(JapaCompletionKind kind) =>
      _channel.invokeMethod('playCompletionSound', {'kind': kind.wireValue});

  /// True at most once ever — whether to show the one-time "sound is
  /// headphone-only" message. Consuming this also marks it shown natively,
  /// so callers don't need to report back; just show it if true.
  Future<bool> shouldShowHeadphoneHint() async {
    final result = await _channel.invokeMethod<bool>('shouldShowHeadphoneHint');
    return result ?? false;
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    final result =
        await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    return result ?? false;
  }

  Future<bool> isNotificationPermissionGranted() async {
    final result =
        await _channel.invokeMethod<bool>('isNotificationPermissionGranted');
    return result ?? false;
  }

  /// Shows the system permission dialog (Android 13+ only — a no-op success
  /// on older versions, which don't require a runtime grant). Resolves once
  /// the user has answered.
  Future<bool> requestNotificationPermission() async {
    final result =
        await _channel.invokeMethod<bool>('requestNotificationPermission');
    return result ?? false;
  }

  /// Opens the system "allow this app to ignore battery optimizations"
  /// dialog. This is the standard Android/AOSP exemption — it does not
  /// cover Samsung's separate Device Care "sleeping apps" list, which has
  /// no public API; that needs manual user action in Samsung's settings.
  Future<void> requestIgnoreBatteryOptimizations() =>
      _channel.invokeMethod('requestIgnoreBatteryOptimizations');
}
