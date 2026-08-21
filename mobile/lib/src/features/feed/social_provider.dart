import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import '../auth/auth_controller.dart';
import 'data/social_api_client.dart';

final socialApiClientProvider = Provider<SocialApiClient>((ref) {
  final authController = ref.watch(authControllerProvider.notifier);
  return SocialApiClient(
    baseUrl: apiBaseUrl,
    tokenProvider: authController.validAccessToken,
  );
});
