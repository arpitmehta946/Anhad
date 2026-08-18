import 'package:isar_community/isar.dart';

part 'daily_japa_total.g.dart';

/// One calendar day's cumulative tap count, keyed by the device's local
/// date (`yyyy-MM-dd`) rather than overwritten in place, so a day
/// rollover leaves history behind instead of erasing it. Written only by
/// [JapaSessionController].
@collection
class DailyJapaTotal {
  Id id = Isar.autoIncrement;

  late String localDate;

  late int totalTaps;
}
