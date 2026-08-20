import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'moderation_models.dart';

/// Talks to the reporting and moderation endpoints
/// (api/internal/server/moderation.go). Mirrors ReelApiClient's shape: the
/// bearer token is resolved lazily per call via [tokenProvider], since
/// every one of these routes requires auth (reporting is any signed-in
/// user, the queue/actions/audit log are moderator-only, enforced
/// server-side by requireModerator).
class ModerationApiClient {
  ModerationApiClient({required this.baseUrl, required this.tokenProvider});

  final String baseUrl;
  final Future<String?> Function() tokenProvider;

  Future<void> reportReel(String reelId, {required String reason, String? detail}) async {
    final token = await _requireToken();
    final response = await http.post(
      Uri.parse('$baseUrl/v1/reels/$reelId/reports'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'reason': reason,
        if (detail != null && detail.isNotEmpty) 'detail': detail,
      }),
    );
    if (response.statusCode != 201) {
      throw HttpException(_errorMessage(response));
    }
  }

  Future<List<QueueItem>> listQueue() async {
    final token = await _requireToken();
    final response = await http.get(
      Uri.parse('$baseUrl/v1/moderation/reports'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['reports'] as List)
        .cast<Map<String, dynamic>>()
        .map(QueueItem.fromJson)
        .toList();
  }

  Future<void> dismissReport(String reportId, {String? reason}) async {
    await _postAction('$baseUrl/v1/moderation/reports/$reportId/dismiss', reason);
  }

  Future<void> removeReel(String reportId, {String? reason}) async {
    await _postAction('$baseUrl/v1/moderation/reports/$reportId/remove-reel', reason);
  }

  Future<List<AuditLogEntry>> listAuditLog() async {
    final token = await _requireToken();
    final response = await http.get(
      Uri.parse('$baseUrl/v1/moderation/audit-log'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['entries'] as List)
        .cast<Map<String, dynamic>>()
        .map(AuditLogEntry.fromJson)
        .toList();
  }

  Future<void> _postAction(String url, String? reason) async {
    final token = await _requireToken();
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({if (reason != null && reason.isNotEmpty) 'reason': reason}),
    );
    if (response.statusCode != 204) {
      throw HttpException(_errorMessage(response));
    }
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
