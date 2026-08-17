import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Talks to `POST /v1/japa/taps` (api/internal/server/japa.go). The auth
/// token is resolved lazily per call via [tokenProvider] rather than
/// injected once, since it can change after this client is constructed
/// (dev sign-in today, the real login flow later).
class JapaApiClient {
  JapaApiClient({required this.baseUrl, required this.tokenProvider});

  final String baseUrl;
  final Future<String?> Function() tokenProvider;

  Future<void> submitTaps(List<DateTime> taps) async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('no auth token set — use developer sign-in first');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/v1/japa/taps'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'taps': taps.map((t) => t.toUtc().toIso8601String()).toList(),
      }),
    );

    if (response.statusCode != 201) {
      throw HttpException(
        'japa tap submission failed: ${response.statusCode} ${response.body}',
      );
    }
  }
}
