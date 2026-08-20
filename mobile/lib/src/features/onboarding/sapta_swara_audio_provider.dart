import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sapta_swara_audio.dart';

/// Overridden in main.dart with an instance whose [SaptaSwaraAudio.preload]
/// was already kicked off before `runApp` — synthesis needs to be well
/// underway before the arrival screen ever builds, not started reactively
/// once it does (see the provider's doc there for why).
final saptaSwaraAudioProvider = Provider<SaptaSwaraAudio>((ref) {
  throw UnimplementedError('saptaSwaraAudioProvider must be overridden in main()');
});
