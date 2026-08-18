import 'package:isar_community/isar.dart';

part 'japa_preferences.g.dart';

/// Standing user preference for whether screen-off japa should be engaged,
/// as opposed to [LocalJapaSession]'s per-visit state — a single row (fixed
/// id, not [Isar.autoIncrement]) rather than one per calendar day like
/// [DailyJapaTotal], since this isn't daily state. Defaults to off for a
/// new user; once turned on it's meant to stay on for every future app open
/// until explicitly turned off again (docs/PRD.md §7.4) — see
/// [BackgroundJapaController.start]/[BackgroundJapaController.end].
@collection
class JapaPreferences {
  Id id = 0;

  bool screenOffEnabled = false;
}
