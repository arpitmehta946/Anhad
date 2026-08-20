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

  /// Set once the four-screen first-run flow (docs/ONBOARDING.md §3) has
  /// been seen through to its end — whether that ended in a saved account,
  /// a declared-under-18 routing, or an explicit skip. Gates whether a
  /// fresh app open shows the onboarding flow or goes straight to practice;
  /// never reset once true (there's no "show onboarding again").
  bool onboardingComplete = false;

  /// The sankalp length chosen at the sankalp offer (11/21/41), or null if
  /// never taken yet or the user chose "Not now". 11 days is encouragement
  /// only, 21 earns a badge, 41 unlocks the 7-day Seva Pass trial (docs/
  /// PRD.md §10.3) — that reward logic isn't wired up yet; this only
  /// preserves the choice.
  int? sankalpLengthDays;

  /// The optional intention stated alongside [sankalpLengthDays] — "what is
  /// this practice for?" (docs/ONBOARDING.md §2). Null if none was given.
  /// Always private — never shown on a profile or to anyone else (docs/
  /// PRD.md §10.3).
  String? sankalpIntention;

  /// The daily chant target locked in when the sankalp was taken (docs/
  /// PRD.md §10.3) — set once, never changed for the vow's duration. Null
  /// alongside [sankalpLengthDays] when no sankalp is active. Distinct from
  /// [malaLength]: this is how many chants count as "today done" for the
  /// vow and the reminder; malaLength only affects how the ring visually
  /// chunks a round.
  int? sankalpDailyTarget;

  /// The user-chosen time of day for the practice reminder (docs/PRD.md
  /// §7.7) — set when the sankalp is taken, never preset. Null alongside
  /// [sankalpLengthDays] when no sankalp is active or no reminder was set.
  int? sankalpReminderHour;
  int? sankalpReminderMinute;
}
