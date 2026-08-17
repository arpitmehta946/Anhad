import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

/// Overridden in `main.dart` with the already-open Isar instance once the
/// app has awaited `Isar.open` at startup — never read before that override
/// is applied.
final isarProvider = Provider<Isar>((ref) {
  throw UnimplementedError('isarProvider must be overridden in main()');
});
