import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'sapta_swara.dart';

/// Synthesizes and plays the seven sapta swara tones (docs/
/// FRONTEND_GUIDELINES.md, "Sapta Swara") — just intonation relative to
/// [saptaSwaraSaHz], a tanpura-like harmonic stack, and an attack/decay
/// envelope so the notes overlap and ring together rather than sounding
/// staccato. Plays every time the arrival screen is shown.
///
/// Playback itself goes through [SaptaSwaraPlayer] on the native side, not
/// `just_audio` — this needs to force the phone's built-in speaker
/// regardless of a connected Bluetooth device, which just_audio has no way
/// to express from Dart. Synthesis stays here in Dart; only the "play this
/// WAV file" step crosses the platform channel.
class SaptaSwaraAudio {
  static const _channel = MethodChannel('com.anhad.anhad/sapta_swara');

  final _paths = <String>[];
  Future<void>? _preloadFuture;
  final _delayedPlays = <Timer>[];

  /// Synthesizes all seven tones fresh every app run — idempotent within
  /// one run (later calls await the same in-flight work rather than
  /// redoing it), but deliberately not cached to disk across runs: this
  /// plays every time the arrival screen shows (many times a day for a
  /// returning user), and caching by a filename with no version or
  /// parameter hash in it means a future tuning change would silently
  /// never take effect for anyone with an already-written file. Synthesis
  /// is cheap enough (well under 100ms for seven ~3.6s tones) that this
  /// isn't worth the staleness risk. Should be kicked off as early as
  /// possible (main.dart, before the arrival screen ever builds) so the
  /// first note isn't late once [playSequence] runs.
  Future<void> preload() => _preloadFuture ??= _preload();

  Future<void> _preload() async {
    final dir = await getTemporaryDirectory();
    for (final swara in saptaSwaras) {
      final path = '${dir.path}/sapta_swara_${swara.name.toLowerCase()}.wav';
      final bytes = _synthesizeTone(
        frequencyHz: saptaSwaraSaHz * swara.frequencyRatio,
      );
      await File(path).writeAsBytes(bytes, flush: true);
      _paths.add(path);
    }
  }

  /// Fires each note at its swara's own [Swara.startOffset], matching the
  /// ripple animation's stagger exactly. Waits for [preload] if it hasn't
  /// finished yet, rather than skipping notes that aren't ready.
  Future<void> playSequence() async {
    await preload();
    for (var i = 0; i < saptaSwaras.length && i < _paths.length; i++) {
      final path = _paths[i];
      _delayedPlays.add(
        Timer(saptaSwaras[i].startOffset, () {
          unawaited(_channel.invokeMethod('playTone', {'path': path}));
        }),
      );
    }
  }

  void dispose() {
    for (final timer in _delayedPlays) {
      timer.cancel();
    }
  }
}

/// One tone: [harmonicAmplitudes] gives a soft, rounded warmth (fundamental
/// plus two gentle overtones) rather than a bright buzz — an early version
/// carried a 4th harmonic and much louder upper harmonics, which read as
/// harsh/noisy rather than melodious in practice; this is deliberately
/// mellower. A gentle sine-eased attack into an exponential decay reads as
/// a soft bloom, not a hit or pluck.
Uint8List _synthesizeTone({
  required double frequencyHz,
  double attackSeconds = 0.3,
  double decaySeconds = 3.4,
  int sampleRate = 44100,
}) {
  const harmonicAmplitudes = [1.0, 0.22, 0.06];
  final amplitudeSum = harmonicAmplitudes.reduce((a, b) => a + b);
  const peak = 0.55; // soft, not loud — headroom well beyond just clip-safety.

  final totalSeconds = attackSeconds + decaySeconds;
  final sampleCount = (totalSeconds * sampleRate).round();
  final samples = Int16List(sampleCount);

  for (var n = 0; n < sampleCount; n++) {
    final t = n / sampleRate;
    final envelope = t < attackSeconds
        ? sin(t / attackSeconds * pi / 2) // eased in, not a linear ramp
        : exp(-2.4 * (t - attackSeconds) / decaySeconds);

    var value = 0.0;
    for (var h = 0; h < harmonicAmplitudes.length; h++) {
      value += harmonicAmplitudes[h] * sin(2 * pi * frequencyHz * (h + 1) * t);
    }
    value = value / amplitudeSum * envelope * peak;
    samples[n] = (value * 32767).round().clamp(-32768, 32767);
  }

  return _wavBytes(samples, sampleRate);
}

/// Plain 16-bit PCM mono WAV — no compression, no dependency beyond the
/// standard RIFF/WAVE header, so [just_audio] can load it straight off
/// disk with [AudioPlayer.setFilePath].
Uint8List _wavBytes(Int16List samples, int sampleRate) {
  const bitsPerSample = 16;
  const numChannels = 1;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  const blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataSize = samples.length * 2;

  final bytes = BytesBuilder();
  void writeString(String s) => bytes.add(s.codeUnits);
  void writeUint32(int v) => bytes.add([
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ]);
  void writeUint16(int v) => bytes.add([v & 0xff, (v >> 8) & 0xff]);

  writeString('RIFF');
  writeUint32(36 + dataSize);
  writeString('WAVE');
  writeString('fmt ');
  writeUint32(16);
  writeUint16(1); // PCM
  writeUint16(numChannels);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(blockAlign);
  writeUint16(bitsPerSample);
  writeString('data');
  writeUint32(dataSize);
  for (final sample in samples) {
    writeUint16(sample & 0xffff);
  }
  return bytes.toBytes();
}
