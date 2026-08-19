import 'dart:io';

import 'package:anhad/src/features/japa/background/background_japa_channel.dart'
    show ActiveSessionInfo;
import 'package:anhad/src/features/japa/data/daily_japa_total.dart';
import 'package:anhad/src/features/japa/data/japa_api_client.dart';
import 'package:anhad/src/features/japa/data/japa_preferences.dart';
import 'package:anhad/src/features/japa/data/japa_preferences_store.dart';
import 'package:anhad/src/features/japa/data/japa_sync_service.dart';
import 'package:anhad/src/features/japa/data/local_japa_session.dart';
import 'package:anhad/src/features/japa/japa_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

enum _FakeOutcome { accept, fail }

class _FakeSubmitter implements JapaTapsSubmitter {
  _FakeOutcome outcome = _FakeOutcome.accept;
  final List<List<DateTime>> submittedBatches = [];

  @override
  Future<void> submitTaps(List<DateTime> taps) async {
    submittedBatches.add(taps);
    if (outcome == _FakeOutcome.fail) {
      throw const _NetworkFailure();
    }
  }
}

class _NetworkFailure implements Exception {
  const _NetworkFailure();
}

/// Polls [condition] until it's true, failing the test loudly instead of
/// hanging forever if something's actually broken — the controller's state
/// transitions all happen via real async Isar watchers, not synchronously.
Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 5));
  }
}

/// Taps [count] times sequentially, with a small real-time gap between each
/// — Isar's watchObject stream can miss the very last notification in a
/// tight back-to-back write sequence with no gap at all between them
/// (confirmed empirically: without this delay, the final tap in a 108-tap
/// loop would land in Isar correctly but never trigger a watcher
/// notification, hanging any test waiting on it). Not a production concern
/// — real taps are naturally paced 300-800ms apart by the anti-cheat
/// design (api/internal/japa/service.go) — but worth a real delay here
/// rather than a bare `await`, which still isn't enough on its own. 10ms
/// rather than the original 2ms: under heavier system load the shorter gap
/// still occasionally missed the last notification (the same failure mode,
/// just less reliably triggered), so this trades a bit of test runtime for
/// consistently clearing it.
///
/// Also: when [count] completes a mala, the rotation that follows is
/// asynchronous (fire-and-forget from _applyTapTotal, not awaited within
/// tap() itself) — calling this again immediately after, before that
/// rotation has settled, would still target the old (soon-to-be-flushed
/// -and-deleted) session and race it. Callers that tap across more than
/// one mala must pumpUntil the rotation has settled (cumulativeBase
/// advanced and sessionId changed) between calls.
Future<void> tapTimes(JapaSessionController controller, int count) async {
  for (var i = 0; i < count; i++) {
    await controller.tap();
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Isar isar;
  late Directory tempDir;
  late _FakeSubmitter fakeApi;
  final controllers = <JapaSessionController>[];

  JapaSessionController makeController({
    Future<ActiveSessionInfo?> Function()? getActiveSessionId,
    void Function(int, int)? updateActiveSessionId,
    void Function(int, int)? updateNotificationCount,
    void Function()? onSynced,
  }) {
    final controller = JapaSessionController(
      isar,
      JapaSyncService(isar: isar, api: fakeApi),
      getActiveSessionId: getActiveSessionId,
      updateActiveSessionId: updateActiveSessionId,
      updateNotificationCount: updateNotificationCount,
      onSynced: onSynced,
      // Empty rather than the real connectivity_plus plugin — these tests
      // drive rotation purely through mala completions, and a stream that
      // never emits is enough to prove that path doesn't depend on it.
      connectivityChanges: const Stream.empty(),
    );
    controllers.add(controller);
    return controller;
  }

  setUp(() async {
    tempDir =
        Directory.systemTemp.createTempSync('japa_session_controller_test');
    isar = await Isar.open(
      [LocalJapaSessionSchema, DailyJapaTotalSchema, JapaPreferencesSchema],
      directory: tempDir.path,
    );
    fakeApi = _FakeSubmitter();
    controllers.clear();
  });

  tearDown(() async {
    for (final c in controllers) {
      if (!c.mounted) continue;
      c.dispose();
    }
    // dispose() fires a final flush unawaited — give it a moment before
    // tearing down Isar out from under it.
    await Future.delayed(const Duration(milliseconds: 20));
    await isar.close(deleteFromDisk: true);
    // isar.close() has already released the files it cares about, but on
    // Windows the native handle (or a real-time antivirus/indexing scan of
    // the freshly-written db files) can hold the directory locked well
    // after close() itself returns — deleteSync() racing that is a
    // test-cleanup timing issue, not a correctness one, and each test uses
    // its own uniquely-named temp dir, so leaving one behind on the rare
    // case retries don't clear it in time costs nothing worth failing the
    // test over.
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        break;
      } catch (_) {
        if (attempt == 9) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  test('starts a fresh session at 0/0 when nothing is adopted', () async {
    final controller = makeController();
    await pumpUntil(() => controller.state.sessionId != null);

    expect(controller.state.tapsInRound, 0);
    expect(controller.state.roundsCompleted, 0);
    expect(controller.cumulativeBase, 0);
  });

  test('tapping increments the in-round count and the daily total',
      () async {
    final controller = makeController();
    await pumpUntil(() => controller.state.sessionId != null);

    for (var i = 0; i < 5; i++) {
      await controller.tap();
    }
    // tapsInRound and dailyTotal are driven by two independent Isar
    // watchers (session row vs. daily-total row) that settle on their own
    // schedules — wait for both rather than assuming they land together.
    await pumpUntil(
      () => controller.state.tapsInRound == 5 && controller.state.dailyTotal == 5,
    );

    expect(controller.state.roundsCompleted, 0);
  });

  test(
      'completing one mala rotates to a fresh session and carries the '
      'cumulative base forward', () async {
    final notifications = <int>[];
    final controller = makeController(
      updateNotificationCount: (total, _) => notifications.add(total),
    );
    await pumpUntil(() => controller.state.sessionId != null);
    final firstSessionId = controller.state.sessionId;

    await tapTimes(controller, malaSize);
    await pumpUntil(
      () =>
          controller.cumulativeBase == malaSize &&
          controller.state.sessionId != firstSessionId,
    );

    expect(controller.state.roundsCompleted, 1);
    expect(controller.state.tapsInRound, 0);
    expect(controller.state.sessionId, isNot(firstSessionId),
        reason: 'a completed mala must rotate to a fresh local row');
    expect(fakeApi.submittedBatches, hasLength(1));
    expect(fakeApi.submittedBatches.single, hasLength(malaSize));
    expect(notifications, contains(malaSize),
        reason: 'the notification must see the true cumulative total');
  });

  test(
      'two mala completions carry the cumulative base correctly across '
      'two separate rotations — the highest-risk math in this file',
      () async {
    final controller = makeController();
    await pumpUntil(() => controller.state.sessionId != null);
    final firstSessionId = controller.state.sessionId;

    // First mala, then wait for its rotation to fully settle before
    // continuing — see tapTimes' doc for why this can't be one tight loop.
    await tapTimes(controller, malaSize);
    await pumpUntil(
      () =>
          controller.cumulativeBase == malaSize &&
          controller.state.sessionId != firstSessionId,
    );
    final secondSessionId = controller.state.sessionId;

    // Second mala, on top of the first.
    await tapTimes(controller, malaSize);
    await pumpUntil(
      () =>
          controller.cumulativeBase == malaSize * 2 &&
          controller.state.sessionId != secondSessionId,
    );

    expect(controller.state.roundsCompleted, 2);
    expect(controller.state.tapsInRound, 0);
    expect(fakeApi.submittedBatches, hasLength(2));
    expect(fakeApi.submittedBatches[0], hasLength(malaSize));
    expect(fakeApi.submittedBatches[1], hasLength(malaSize));
  });

  test(
      'partway through a second mala, the ring reflects cumulative base '
      'plus the new row rather than just the new row alone', () async {
    final controller = makeController();
    await pumpUntil(() => controller.state.sessionId != null);
    final firstSessionId = controller.state.sessionId;

    await tapTimes(controller, malaSize);
    await pumpUntil(
      () =>
          controller.cumulativeBase == malaSize &&
          controller.state.sessionId != firstSessionId,
    );

    await tapTimes(controller, 30);
    await pumpUntil(() => controller.state.tapsInRound == 30);

    expect(controller.state.roundsCompleted, 1);
    expect(controller.cumulativeBase, malaSize);
    expect(fakeApi.submittedBatches, hasLength(1));
  });

  test(
      'onSynced fires after a live mala-completion flush succeeds',
      () async {
    var syncedCount = 0;
    final controller = makeController(onSynced: () => syncedCount++);
    await pumpUntil(() => controller.state.sessionId != null);

    for (var i = 0; i < malaSize; i++) {
      await controller.tap();
    }
    await pumpUntil(() => syncedCount > 0);

    expect(syncedCount, greaterThanOrEqualTo(1));
  });

  test(
      'a failed flush on mala completion does NOT rotate — the row keeps '
      'accumulating and cumulative base stays put until it actually syncs',
      () async {
    fakeApi.outcome = _FakeOutcome.fail;
    final controller = makeController();
    await pumpUntil(() => controller.state.sessionId != null);
    final sessionId = controller.state.sessionId;

    for (var i = 0; i < malaSize; i++) {
      await controller.tap();
    }
    await pumpUntil(() => controller.state.syncFailed);

    expect(controller.state.sessionId, sessionId,
        reason: 'no rotation should happen while the flush is stuck');
    expect(controller.cumulativeBase, 0);
    expect(controller.state.roundsCompleted, 1);
    expect(controller.state.tapsInRound, 0);

    // Tapping again continues on the same unrotated row rather than losing
    // the in-progress round — this is the exact "108, 2/108" display
    // behavior observed during today's real offline testing.
    await controller.tap();
    await pumpUntil(() => controller.state.tapsInRound == 1);
    expect(controller.state.roundsCompleted, 1);
  });

  test(
      'adopting an existing background session resumes from its persisted '
      'cumulative base rather than starting at zero', () async {
    final existing = LocalJapaSession()
      ..taps = List.generate(20, (i) => DateTime(2026, 1, 1, 0, 0, i));
    final existingId =
        await isar.writeTxn(() => isar.localJapaSessions.put(existing));

    final controller = makeController(
      getActiveSessionId: () async =>
          ActiveSessionInfo(sessionId: existingId, cumulativeBase: 300),
    );
    // sessionId is set (synchronously, inside _init) before the row's own
    // tap count is fetched and _applyTapTotal computes roundsCompleted/
    // tapsInRound from it — waiting only on sessionId can observe state
    // between those two steps, so wait for the actual settled value.
    await pumpUntil(() => controller.state.roundsCompleted != 0);

    expect(controller.state.sessionId, existingId);
    expect(controller.cumulativeBase, 300);
    // (300 + 20) = 320 -> 2 full malas (216) + 104 into the third.
    expect(controller.state.roundsCompleted, 2);
    expect(controller.state.tapsInRound, 320 - malaSize * 2);
  });

  test(
      'a phantom adoption target (deleted/never existed) falls back to a '
      'fresh session instead of crashing or adopting nothing', () async {
    const phantomId = 999999;
    final controller = makeController(
      getActiveSessionId: () async =>
          const ActiveSessionInfo(sessionId: phantomId, cumulativeBase: 500),
    );
    await pumpUntil(() => controller.state.sessionId != null);

    expect(controller.state.sessionId, isNot(phantomId));
    expect(controller.cumulativeBase, 0);
  });

  test(
      'if the watched session row disappears out from under the '
      'controller, it self-heals with a fresh session rather than '
      'sticking on stale state', () async {
    final controller = makeController();
    await pumpUntil(() => controller.state.sessionId != null);
    final originalId = controller.state.sessionId!;

    await controller.tap();
    await pumpUntil(() => controller.state.tapsInRound == 1);

    // Simulate another instance's flush completing the row out from under
    // this controller — exactly the race _watchSession's null-session
    // branch documents.
    await isar.writeTxn(() => isar.localJapaSessions.delete(originalId));

    await pumpUntil(
      () => controller.state.sessionId != null &&
          controller.state.sessionId != originalId,
    );
    expect(controller.state.tapsInRound, 0);
    expect(controller.state.roundsCompleted, 0);
  });

  test(
      'a pending session left over from a previous run is flushed at '
      'startup and triggers onSynced, without touching the new session',
      () async {
    final leftover = LocalJapaSession()
      ..taps = [DateTime(2026, 1, 1, 8, 0, 0)];
    await isar.writeTxn(() => isar.localJapaSessions.put(leftover));

    var syncedCount = 0;
    final controller = makeController(onSynced: () => syncedCount++);
    await pumpUntil(() => controller.state.sessionId != null);
    await pumpUntil(() => syncedCount > 0);

    expect(fakeApi.submittedBatches, hasLength(1));
    expect(fakeApi.submittedBatches.single, [DateTime(2026, 1, 1, 8, 0, 0)]);
    // The new session this controller started for itself must be
    // untouched by the leftover sweep.
    final newSession =
        await isar.localJapaSessions.get(controller.state.sessionId!);
    expect(newSession, isNotNull);
    expect(newSession!.taps, isEmpty);
  });

  test('undoLastTap removes a tap and the ring reflects it', () async {
    final controller = makeController();
    await pumpUntil(() => controller.state.sessionId != null);

    await controller.tap();
    await controller.tap();
    await controller.tap();
    await pumpUntil(() => controller.state.tapsInRound == 3);

    final undone = await controller.undoLastTap();
    // tapsInRound and dailyTotal settle via two independent Isar watchers
    // (session row vs. daily-total row) — wait for both, not just one.
    await pumpUntil(
      () => controller.state.tapsInRound == 2 && controller.state.dailyTotal == 2,
    );

    expect(undone, isTrue);
  });

  test('undoLastTap on a fresh session reports false and changes nothing',
      () async {
    final controller = makeController();
    await pumpUntil(() => controller.state.sessionId != null);

    final undone = await controller.undoLastTap();

    expect(undone, isFalse);
    expect(controller.state.tapsInRound, 0);
  });

  test(
      'setMalaLength re-chunks the same cumulative total against the new '
      'length without adding, dropping, or reassigning any taps', () async {
    final controller = makeController();
    await pumpUntil(() => controller.state.sessionId != null);

    for (var i = 0; i < 40; i++) {
      await controller.tap();
    }
    await pumpUntil(() => controller.state.tapsInRound == 40);
    expect(controller.state.malaLength, malaSize); // still the 108 default

    await controller.setMalaLength(27);

    // Cumulative is still exactly 40 — now expressed against a 27-length
    // mala: 1 full round (27) plus 13 into the second.
    expect(controller.state.malaLength, 27);
    expect(controller.state.roundsCompleted, 1);
    expect(controller.state.tapsInRound, 13);

    // The persisted preference sticks for the next controller too.
    expect(await malaLengthPreferred(isar), 27);

    // Tapping after the switch continues to accumulate normally against
    // the new length — no data was lost in the switch.
    await controller.tap();
    await pumpUntil(
      () => controller.state.tapsInRound == 14 && controller.state.dailyTotal == 41,
    );
  });

  test('setMalaLength persists across a fresh controller (adoption path)',
      () async {
    final first = makeController();
    await pumpUntil(() => first.state.sessionId != null);
    await first.setMalaLength(54);

    final second = makeController();
    await pumpUntil(() => second.state.sessionId != null);

    expect(second.state.malaLength, 54);
  });
}
