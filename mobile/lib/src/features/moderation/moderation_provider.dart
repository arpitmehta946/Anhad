import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import '../auth/auth_controller.dart';
import 'data/moderation_api_client.dart';

final moderationApiClientProvider = Provider<ModerationApiClient>((ref) {
  final authController = ref.watch(authControllerProvider.notifier);
  return ModerationApiClient(
    baseUrl: apiBaseUrl,
    tokenProvider: authController.validAccessToken,
  );
});
