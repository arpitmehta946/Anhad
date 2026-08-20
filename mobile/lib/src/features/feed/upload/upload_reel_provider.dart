import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config.dart';
import '../../auth/auth_controller.dart';
import '../data/reel_api_client.dart';

final reelApiClientProvider = Provider<ReelApiClient>((ref) {
  final authController = ref.watch(authControllerProvider.notifier);
  return ReelApiClient(
    baseUrl: apiBaseUrl,
    tokenProvider: authController.validAccessToken,
  );
});
