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

  /// Beads per mala round (docs/ONBOARDING.md §1.3) — 27/54/108/1008 are the
  /// offered lengths, 108 is the traditional default. Purely a client-side
  /// display/pacing preference: it changes how a round is chunked for the
  /// ring and the completion bell, never the server's streak-qualification
  /// threshold (PRD.md §7.4 keeps that at a fixed 108 taps/day regardless of
  /// what ring length someone prefers to chant in).
  int malaLength = 108;
}
