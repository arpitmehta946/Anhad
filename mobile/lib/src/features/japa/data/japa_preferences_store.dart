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
