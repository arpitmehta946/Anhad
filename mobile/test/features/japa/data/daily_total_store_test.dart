import 'dart:io';

import 'package:anhad/src/features/japa/data/daily_japa_total.dart';
import 'package:anhad/src/features/japa/data/daily_total_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

void main() {
  late Isar isar;
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('daily_total_store_test');
    isar = await Isar.open([DailyJapaTotalSchema], directory: tempDir.path);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('todayTotalRow', () {
    test('creates a fresh zero row the first time', () async {
      final row = await todayTotalRow(isar);
      expect(row.totalTaps, 0);
      expect(row.localDate, todayLocalDate());
    });

    test('returns the same row on a second call rather than duplicating it',
        () async {
      final first = await todayTotalRow(isar);
      final second = await todayTotalRow(isar);
      expect(second.id, first.id);
      expect(await isar.dailyJapaTotals.count(), 1);
    });

    test('two concurrent first-calls still only create one row', () async {
      // The exact race the check-then-create write transaction guards
      // against: two isolates (or two callers) both seeing "no row yet"
      // and each creating their own.
      final results = await Future.wait([
        todayTotalRow(isar),
        todayTotalRow(isar),
        todayTotalRow(isar),
      ]);
      final ids = results.map((r) => r.id).toSet();
      expect(ids.length, 1, reason: 'all callers must land on the same row');
      expect(await isar.dailyJapaTotals.count(), 1);
    });
  });

  group('adjustDailyTotal', () {
    test('a positive delta on a fresh day creates the row and sets it',
        () async {
      await adjustDailyTotal(isar, 5);
      final row = await todayTotalRow(isar);
      expect(row.totalTaps, 5);
    });

    test('sequential adjustments accumulate', () async {
      await adjustDailyTotal(isar, 1);
      await adjustDailyTotal(isar, 1);
      await adjustDailyTotal(isar, 1);
      final row = await todayTotalRow(isar);
      expect(row.totalTaps, 3);
    });

    test('a negative delta below zero clamps at zero, not negative',
        () async {
      await adjustDailyTotal(isar, 3);
      await adjustDailyTotal(isar, -10);
      final row = await todayTotalRow(isar);
      expect(row.totalTaps, 0);
    });

    test('a zero delta is a no-op and does not create a row', () async {
      await adjustDailyTotal(isar, 0);
      expect(await isar.dailyJapaTotals.count(), 0);
    });

    test(
        'many concurrent +1 adjustments never lose an update '
        '(the exact lost-update race this atomic rewrite fixed)', () async {
      const concurrentTaps = 50;
      await Future.wait(
        List.generate(concurrentTaps, (_) => adjustDailyTotal(isar, 1)),
      );
      final row = await todayTotalRow(isar);
      expect(row.totalTaps, concurrentTaps);
    });

    test('concurrent increments and decrements settle to the correct net',
        () async {
      final futures = <Future<void>>[
        ...List.generate(30, (_) => adjustDailyTotal(isar, 1)),
        ...List.generate(10, (_) => adjustDailyTotal(isar, -1)),
      ];
      await Future.wait(futures);
      final row = await todayTotalRow(isar);
      expect(row.totalTaps, 20);
    });
  });
}
