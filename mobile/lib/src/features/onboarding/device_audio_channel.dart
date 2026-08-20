import 'package:flutter/services.dart';

/// A one-method query against the same native channel
/// [BackgroundJapaChannel] already registers (MainActivity.kt) — kept as a
/// separate, standalone [MethodChannel] instance rather than importing that
/// class, since this has nothing to do with japa background sessions; two
/// [MethodChannel]s with the same name both just talk to the one native
/// handler, which is a normal, supported pattern for splitting unrelated
/// call sites.
class DeviceAudioChannel {
  static const _channel = MethodChannel('com.anhad.anhad/japa_background');

  /// Whether the device's ringer is silent or vibrate-only right now — the
  /// sapta swara arrival sequence (docs/FRONTEND_GUIDELINES.md, "Sapta
  /// Swara") checks this once, since it plays through the speaker and
  /// should animate silently rather than surprise someone who silenced
  /// their phone.
  Future<bool> isSilencedOrVibrate() async {
    final result =
        await _channel.invokeMethod<bool>('isRingerSilentOrVibrate');
    return result ?? false;
  }
}
