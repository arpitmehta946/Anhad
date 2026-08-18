import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../data/daily_japa_total.dart';
import '../data/local_japa_session.dart';
import '../data/tap_recorder.dart';

const _channelName = 'com.anhad.anhad/japa_background_isolate';

/// Entrypoint for the headless Dart isolate JapaForegroundService spins up
/// for the duration of a screen-off session (docs/PRD.md §7.4). Volume-key
/// taps are captured natively (JapaForegroundService.kt handles the
/// notification/vibration side, which must never depend on this isolate
/// being reachable — see that file's class doc), then handed here to
/// actually land in Isar in real time, independent of whether the main
/// FlutterActivity's engine is still alive.
///
/// Registered as a Dart entrypoint via
/// `DartExecutor.DartEntrypoint(bundlePath, libraryUri, "japaBackgroundMain")`
/// on the native side — the `vm:entry-point` pragma keeps the tree shaker
/// from stripping it, since nothing in the normal Dart call graph reaches
/// it.
@pragma('vm:entry-point')
void japaBackgroundMain() {
  WidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(_channelName);
  Isar? isar;
  int? sessionId;

  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'init':
        final args = (call.arguments as Map).cast<String, dynamic>();
        sessionId = args['sessionId'] as int;
        final dir = await getApplicationDocumentsDirectory();
        // Isar supports opening the same instance from multiple isolates —
        // whichever isolate calls Isar.open() first actually opens the
        // database; this one just gets a working handle to it, safe to use
        // concurrently with the main isolate's handle.
        isar = await Isar.open(
          [LocalJapaSessionSchema, DailyJapaTotalSchema],
          directory: dir.path,
        );
        return null;
      case 'recordTap':
        final currentIsar = isar;
        final currentSessionId = sessionId;
        if (currentIsar == null || currentSessionId == null) return null;
        await recordTapInIsar(currentIsar, currentSessionId);
        return null;
      case 'updateSessionId':
        // The foreground controller rotated to a fresh Isar row (mala
        // completed, connectivity restored) — retarget so the next
        // recordTap lands there instead of the now-abandoned old session.
        final args = (call.arguments as Map).cast<String, dynamic>();
        sessionId = args['sessionId'] as int;
        return null;
      default:
        return null;
    }
  });
}
