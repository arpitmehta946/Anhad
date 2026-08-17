import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// A freshly issued or refreshed token pair, mirroring the JSON shape
/// returned by `/v1/auth/otp/verify` and `/v1/auth/refresh`
/// (api/internal/server/auth.go).
class AuthTokens {
  AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresIn: json['expires_in'] as int,
      );

  final String accessToken;
  final String refreshToken;

  /// Access token lifetime in seconds.
  final int expiresIn;
}

/// Talks to the phone-OTP auth endpoints
/// (api/internal/server/auth.go, api/internal/auth/otp.go).
class AuthApiClient {
  AuthApiClient({required this.baseUrl});

  final String baseUrl;

  Future<void> requestOtp(String phoneNumber) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/auth/otp/request'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'phone_number': phoneNumber}),
    );
    if (response.statusCode != 202) {
      throw HttpException(_errorMessage(response));
    }
  }

  Future<AuthTokens> verifyOtp(String phoneNumber, String code) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/auth/otp/verify'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'phone_number': phoneNumber, 'code': code}),
    );
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    return AuthTokens.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/auth/refresh'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    return AuthTokens.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'];
      if (error is String && error.isNotEmpty) return error;
    } catch (_) {
      // Body wasn't the expected {"error": "..."} shape — fall through.
    }
    return 'Request failed (${response.statusCode})';
  }
}
