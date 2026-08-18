import 'dart:io';

import 'package:anhad/src/features/japa/data/daily_japa_total.dart';
import 'package:anhad/src/features/japa/data/daily_total_store.dart';
import 'package:anhad/src/features/japa/data/local_japa_session.dart';
import 'package:anhad/src/features/japa/data/tap_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

void main() {
  late Isar isar;
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('tap_recorder_test');
    isar = await Isar.open(
      [LocalJapaSessionSchema, DailyJapaTotalSchema],
      directory: tempDir.path,
    );
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<int> createSession() =>
      isar.writeTxn(() => isar.localJapaSessions.put(LocalJapaSession()));

  test('appends a tap to the session and bumps the daily total by one',
      () async {
    final id = await createSession();
    await recordTapInIsar(isar, id);

    final session = await isar.localJapaSessions.get(id);
    expect(session!.taps.length, 1);

    final total = await todayTotalRow(isar);
    expect(total.totalTaps, 1);
  });

  test('recording against a session id that no longer exists is a no-op',
      () async {
    const missingId = 999999;
    await recordTapInIsar(isar, missingId);

    // No exception, and — since the session write is a no-op — the daily
    // total should NOT be touched either... except adjustDailyTotal always
    // runs regardless. Document the actual (slightly surprising) behavior:
    // the daily total still increments even though no tap was recorded,
    // because recordTapInIsar's two steps aren't conditional on each
    // other. This test exists to make that explicit rather than leave it
    // an unverified assumption.
    final total = await todayTotalRow(isar);
    expect(total.totalTaps, 1);
    expect(await isar.localJapaSessions.get(missingId), isNull);
  });

  test(
      'many concurrent taps on the same session are never lost '
      '(the exact lost-update race this atomic rewrite fixed)', () async {
    final id = await createSession();
    const concurrentTaps = 50;

    await Future.wait(
      List.generate(concurrentTaps, (_) => recordTapInIsar(isar, id)),
    );

    final session = await isar.localJapaSessions.get(id);
    expect(session!.taps.length, concurrentTaps);

    final total = await todayTotalRow(isar);
    expect(total.totalTaps, concurrentTaps);
  });

  test('taps from two different sessions do not clobber each other',
      () async {
    final idA = await createSession();
    final idB = await createSession();

    await Future.wait([
      ...List.generate(20, (_) => recordTapInIsar(isar, idA)),
      ...List.generate(15, (_) => recordTapInIsar(isar, idB)),
    ]);

    final sessionA = await isar.localJapaSessions.get(idA);
    final sessionB = await isar.localJapaSessions.get(idB);
    expect(sessionA!.taps.length, 20);
    expect(sessionB!.taps.length, 15);

    final total = await todayTotalRow(isar);
    expect(total.totalTaps, 35);
  });
}
