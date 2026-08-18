import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import '../auth/auth_controller.dart';
import 'data/japa_api_client.dart';

/// The user's current/longest streak (docs/PRD.md §7.4, §10.3), fetched
/// fresh each time the japa screen is opened — autoDispose rather than
/// cached forever, since the streak can change server-side (a batch flush
/// from an earlier screen-off session, a midnight rollover) between visits.
final japaStreakProvider = FutureProvider.autoDispose<JapaStreak>((ref) {
  final authController = ref.watch(authControllerProvider.notifier);
  final api = JapaApiClient(
    baseUrl: apiBaseUrl,
    tokenProvider: authController.validAccessToken,
  );
  return api.getStreak();
});
