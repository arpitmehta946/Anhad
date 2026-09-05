import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../auth/data/not_authenticated_exception.dart';
import 'creator_profile.dart';

/// Talks to the creator-profile endpoints (api/internal/server/profile.go).
/// Viewing is unauthenticated, same as the feed itself — only editing your
/// own profile needs a token.
class ProfileApiClient {
  ProfileApiClient({required this.baseUrl, required this.tokenProvider});

  final String baseUrl;
  final Future<String?> Function() tokenProvider;

  Future<CreatorProfile> getProfile(String userId) async {
    // Best-effort, not required: an anonymous viewer still sees the
    // profile, just without viewer_is_following — same shape as
    // ReelApiClient.listFeed's own token attach.
    final token = await tokenProvider();
    final response = await http.get(
      Uri.parse('$baseUrl/v1/users/$userId/profile'),
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    );
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    return CreatorProfile.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Always sends both fields, even if empty — this is a full profile-edit
  /// form, not a sparse patch (api/internal/profile.Service.UpdateProfile's
  /// own doc explains why an empty string has to mean "cleared," not
  /// "unchanged," for an edit like this).
  Future<CreatorProfile> updateProfile({
    required String displayName,
    required String bio,
  }) async {
    final token = await _requireToken();
    final response = await http.patch(
      Uri.parse('$baseUrl/v1/me/profile'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'display_name': displayName, 'bio': bio}),
    );
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    return CreatorProfile.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CreatorProfile> uploadAvatar(File image) async {
    final token = await _requireToken();
    final contentType = image.path.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    final response = await http.post(
      Uri.parse('$baseUrl/v1/me/avatar'),
      headers: {
        'Content-Type': contentType,
        'Authorization': 'Bearer $token',
      },
      body: await image.readAsBytes(),
    );
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    return CreatorProfile.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<String> _requireToken() async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
      throw const NotAuthenticatedException();
    }
    return token;
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
