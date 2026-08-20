import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
// Never called from here — this import exists purely so the Dart compiler
// includes japa_background_entrypoint.dart's library in the compiled
// program at all. It's otherwise invoked only from native code
// (JapaForegroundService.kt, via DartExecutor.DartEntrypoint by library
// URI + function name), and a library nothing imports isn't part of the
// compiled kernel regardless of its @pragma('vm:entry-point') annotation —
// that pragma only protects an already-included function from AOT
// tree-shaking, it doesn't pull the file in to begin with.
// ignore: unused_import
import 'src/features/japa/background/japa_background_entrypoint.dart';
import 'src/features/japa/data/daily_japa_total.dart';
import 'src/features/japa/data/isar_provider.dart';
import 'src/features/japa/data/japa_preferences.dart';
import 'src/features/japa/data/local_japa_session.dart';
import 'src/features/onboarding/sapta_swara_audio.dart';
import 'src/features/onboarding/sapta_swara_audio_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [LocalJapaSessionSchema, DailyJapaTotalSchema, JapaPreferencesSchema],
    directory: dir.path,
  );

  // The sound is currently disabled (see onboarding_arrival_screen.dart's
  // _checkMotionAndAudio doc) — nothing calls playSequence(), so there's
  // nothing to preload right now. The provider is still overridden below
  // so the app doesn't crash if anything unexpectedly reads it, but the
  // actual preload() kick-off is commented out rather than doing
  // synthesis work every app open for a sound nobody hears.
  final saptaSwaraAudio = SaptaSwaraAudio();
  // unawaited(saptaSwaraAudio.preload());

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
        saptaSwaraAudioProvider.overrideWithValue(saptaSwaraAudio),
      ],
      child: const AnhadApp(),
    ),
  );
}
