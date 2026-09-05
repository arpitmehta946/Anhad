import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import '../auth/auth_controller.dart';
import 'data/profile_api_client.dart';

final profileApiClientProvider = Provider<ProfileApiClient>((ref) {
  final authController = ref.watch(authControllerProvider.notifier);
  return ProfileApiClient(
    baseUrl: apiBaseUrl,
    tokenProvider: authController.validAccessToken,
  );
});
