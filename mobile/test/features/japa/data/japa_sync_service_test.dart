import 'dart:io';

import 'package:anhad/src/features/japa/data/japa_api_client.dart';
import 'package:anhad/src/features/japa/data/japa_sync_service.dart';
import 'package:anhad/src/features/japa/data/local_japa_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

/// What the batch should do when submitted — controlled per test rather
/// than hitting real HTTP, per [JapaTapsSubmitter]'s whole reason for
/// existing.
enum _FakeOutcome { accept, reject, fail }

class _FakeSubmitter implements JapaTapsSubmitter {
  _FakeOutcome outcome = _FakeOutcome.accept;
  final List<List<DateTime>> submittedBatches = [];

  @override
  Future<void> submitTaps(List<DateTime> taps) async {
    submittedBatches.add(taps);
    switch (outcome) {
      case _FakeOutcome.accept:
        return;
      case _FakeOutcome.reject:
        throw JapaTapsRejected(422, 'anti-cheat rejection');
      case _FakeOutcome.fail:
        throw const SocketExceptionStub();
    }
  }
}

/// A stand-in for a network failure — the exact type doesn't matter to
/// flushSession's catch-all branch, only that it's not JapaTapsRejected.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

void main() {
  late Isar isar;
  late Directory tempDir;
  late _FakeSubmitter fakeApi;
  late JapaSyncService sync;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('japa_sync_service_test');
    isar = await Isar.open([LocalJapaSessionSchema], directory: tempDir.path);
    fakeApi = _FakeSubmitter();
    sync = JapaSyncService(isar: isar, api: fakeApi);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<LocalJapaSession> createSession(List<DateTime> taps) async {
    final session = LocalJapaSession()..taps = taps;
    final id = await isar.writeTxn(() => isar.localJapaSessions.put(session));
    return (await isar.localJapaSessions.get(id))!;
  }

  group('flushSession', () {
    test('an empty session is deleted locally without calling the API',
        () async {
      final session = await createSession([]);
      final outcome = await sync.flushSession(session);

      expect(outcome, FlushOutcome.synced);
      expect(fakeApi.submittedBatches, isEmpty);
      expect(await isar.localJapaSessions.get(session.id), isNull);
    });

    test('a successful submission deletes the local row and reports synced',
        () async {
      final taps = [DateTime(2026, 1, 1, 8, 0, 0)];
      final session = await createSession(taps);

      final outcome = await sync.flushSession(session);

      expect(outcome, FlushOutcome.synced);
      expect(fakeApi.submittedBatches, [taps]);
      expect(await isar.localJapaSessions.get(session.id), isNull);
    });

    test('taps are sorted before submission regardless of storage order',
        () async {
      final t1 = DateTime(2026, 1, 1, 8, 0, 0);
      final t2 = DateTime(2026, 1, 1, 8, 0, 1);
      final t3 = DateTime(2026, 1, 1, 8, 0, 2);
      final session = await createSession([t2, t3, t1]); // out of order

      await sync.flushSession(session);

      expect(fakeApi.submittedBatches.single, [t1, t2, t3]);
    });

    test(
        'a permanent rejection deletes the local row too — retrying '
        'identical data would fail identically forever', () async {
      fakeApi.outcome = _FakeOutcome.reject;
      final session = await createSession([DateTime(2026, 1, 1)]);

      final outcome = await sync.flushSession(session);

      expect(outcome, FlushOutcome.rejected);
      expect(await isar.localJapaSessions.get(session.id), isNull);
    });

    test(
        'a transient failure (offline, server down, throttled) leaves the '
        'row queued locally — this is the "never destroy on throttle" '
        'contract the 429 rate-limit fix depends on', () async {
      fakeApi.outcome = _FakeOutcome.fail;
      final session = await createSession([DateTime(2026, 1, 1)]);

      final outcome = await sync.flushSession(session);

      expect(outcome, FlushOutcome.stillQueued);
      expect(
        await isar.localJapaSessions.get(session.id),
        isNotNull,
        reason: 'a stillQueued outcome must never delete the local data',
      );
    });
  });

  group('flushPending', () {
    test('sweeps every session except the excluded one', () async {
      final keep = await createSession([DateTime(2026, 1, 1)]);
      final flushA = await createSession([DateTime(2026, 1, 2)]);
      final flushB = await createSession([DateTime(2026, 1, 3)]);

      final result = await sync.flushPending(excludeId: keep.id);

      expect(result.stillQueued, isFalse);
      expect(result.rejectedTaps, 0);
      expect(await isar.localJapaSessions.get(keep.id), isNotNull,
          reason: 'the excluded session must be left alone');
      expect(await isar.localJapaSessions.get(flushA.id), isNull);
      expect(await isar.localJapaSessions.get(flushB.id), isNull);
    });

    test('reports total rejected taps across a mixed sweep', () async {
      // First sweep: nothing queued yet to set up a clean rejected batch.
      final rejectedSession =
          await createSession([DateTime(2026, 1, 1), DateTime(2026, 1, 2)]);
      fakeApi.outcome = _FakeOutcome.reject;

      final result = await sync.flushPending();

      expect(result.rejectedTaps, 2);
      expect(await isar.localJapaSessions.get(rejectedSession.id), isNull);
    });

    test('a still-queued session is reflected in the summary and survives',
        () async {
      fakeApi.outcome = _FakeOutcome.fail;
      final session = await createSession([DateTime(2026, 1, 1)]);

      final result = await sync.flushPending();

      expect(result.stillQueued, isTrue);
      expect(await isar.localJapaSessions.get(session.id), isNotNull);
    });
  });
}
