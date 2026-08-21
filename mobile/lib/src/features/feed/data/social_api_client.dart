import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// The result of toggling Pranam or Smaran (api/internal/server/social.go's
/// pranamHandler/smaranHandler) — `active` is the new state after this
/// call, `count` is the reel's fresh total, both computed server-side in
/// the same transaction so they can never drift from each other.
class ToggleResult {
  const ToggleResult({required this.active, required this.count});

  factory ToggleResult.fromJson(Map<String, dynamic> json) => ToggleResult(
        active: json['active'] as bool,
        count: (json['count'] as num).toInt(),
      );

  final bool active;
  final int count;
}

class SatsangComment {
  const SatsangComment({
    required this.id,
    required this.reelId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.userDisplayName,
  });

  factory SatsangComment.fromJson(Map<String, dynamic> json) => SatsangComment(
        id: json['id'] as String,
        reelId: json['reel_id'] as String,
        userId: json['user_id'] as String,
        userDisplayName: json['user_display_name'] as String?,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String reelId;
  final String userId;
  final String? userDisplayName;
  final String body;
  final DateTime createdAt;
}

/// Talks to the P0 renamed-interaction endpoints
/// (api/internal/server/social.go): Pranam, Satsang, Prasad, Smaran, Sevak.
/// Mirrors ModerationApiClient's shape — a lazily-resolved bearer token per
/// call — except [listSatsang], which is unauthenticated the same way
/// [ReelApiClient.listFeed] is (reading reflections is free, same as
/// reading the feed itself).
class SocialApiClient {
  SocialApiClient({required this.baseUrl, required this.tokenProvider});

  final String baseUrl;
  final Future<String?> Function() tokenProvider;

  Future<ToggleResult> togglePranam(String reelId) =>
      _postToggle('$baseUrl/v1/reels/$reelId/pranam');

  Future<ToggleResult> toggleSmaran(String reelId) =>
      _postToggle('$baseUrl/v1/reels/$reelId/smaran');

  Future<bool> toggleSevak(String creatorId) async {
    final token = await _requireToken();
    final response = await http.post(
      Uri.parse('$baseUrl/v1/users/$creatorId/sevak'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['active'] as bool;
  }

  Future<int> recordPrasad(String reelId) async {
    final token = await _requireToken();
    final response = await http.post(
      Uri.parse('$baseUrl/v1/reels/$reelId/prasad'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['count'] as num).toInt();
  }

  Future<SatsangComment> postSatsang(String reelId, String body) async {
    final token = await _requireToken();
    final response = await http.post(
      Uri.parse('$baseUrl/v1/reels/$reelId/satsang'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'body': body}),
    );
    if (response.statusCode != 201) {
      throw HttpException(_errorMessage(response));
    }
    return SatsangComment.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<SatsangComment>> listSatsang(String reelId) async {
    final response =
        await http.get(Uri.parse('$baseUrl/v1/reels/$reelId/satsang'));
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['comments'] as List)
        .cast<Map<String, dynamic>>()
        .map(SatsangComment.fromJson)
        .toList();
  }

  Future<ToggleResult> _postToggle(String url) async {
    final token = await _requireToken();
    final response = await http.post(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    return ToggleResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<String> _requireToken() async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('no auth token set — sign in first');
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
