import 'package:isar_community/isar.dart';

import 'japa_preferences.dart';

/// Always the same row — see [JapaPreferences].
const _preferencesId = 0;

Future<bool> screenOffPreferred(Isar isar) async {
  final row = await isar.japaPreferences.get(_preferencesId);
  return row?.screenOffEnabled ?? false;
}

Future<void> setScreenOffPreferred(Isar isar, bool enabled) async {
  await isar.writeTxn(() async {
    final row = await isar.japaPreferences.get(_preferencesId) ??
        JapaPreferences();
    row.screenOffEnabled = enabled;
    await isar.japaPreferences.put(row);
  });
}

/// The offered mala lengths (docs/ONBOARDING.md §1.3) — 27 (quick), 54
/// (half), 108 (full, traditional default), 1008 (extended).
const malaLengthOptions = [27, 54, 108, 1008];

Future<int> malaLengthPreferred(Isar isar) async {
  final row = await isar.japaPreferences.get(_preferencesId);
  return row?.malaLength ?? 108;
}

Future<void> setMalaLengthPreferred(Isar isar, int length) async {
  await isar.writeTxn(() async {
    final row = await isar.japaPreferences.get(_preferencesId) ??
        JapaPreferences();
    row.malaLength = length;
    await isar.japaPreferences.put(row);
  });
}
