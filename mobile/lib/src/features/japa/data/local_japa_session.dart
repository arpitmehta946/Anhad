import 'package:isar_community/isar.dart';

part 'local_japa_session.g.dart';

/// One offline-first practice session's queued taps (docs/TECH_STACK.md §2,
/// §5). Every tap is written here immediately so nothing is lost if the app
/// is killed mid-session. A row only exists while it hasn't reached
/// Postgres yet — [JapaSyncService] deletes it the moment a flush succeeds,
/// so "every row in this collection" already means "still pending."
@collection
class LocalJapaSession {
  Id id = Isar.autoIncrement;

  List<DateTime> taps = [];
}
