import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import 'data/audio_library_api_client.dart';

final audioLibraryApiClientProvider = Provider<AudioLibraryApiClient>((ref) {
  return AudioLibraryApiClient(baseUrl: apiBaseUrl);
});
