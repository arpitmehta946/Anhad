import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'reel.dart';

/// Where to upload a new reel's video bytes to, and under what id
/// (api/internal/reels.UploadTarget) — the client never writes directly to
/// storage itself in the sense that matters (TECH_STACK.md §3): it always
/// asks the API for a target first, the same shape whether that target
/// turns out to be this dev server's own local-stub route or, later,
/// Cloudflare's real one.
class UploadTarget {
  const UploadTarget({
    required this.videoId,
    required this.uploadUrl,
    required this.uploadMethod,
  });

  factory UploadTarget.fromJson(Map<String, dynamic> json) => UploadTarget(
        videoId: json['video_id'] as String,
        uploadUrl: json['upload_url'] as String,
        uploadMethod: json['upload_method'] as String,
      );

  final String videoId;
  final String uploadUrl;
  final String uploadMethod;
}

class FeedPage {
  const FeedPage({required this.reels, this.nextCursor});

  final List<Reel> reels;

  /// Pass back as the next request's `cursor` to load the next page; null
  /// means this was the last page.
  final String? nextCursor;
}

/// Talks to the reel upload/feed endpoints
/// (api/internal/server/reels.go). Mirrors JapaApiClient's shape: the
/// bearer token is resolved lazily per call via [tokenProvider], and
/// [listFeed] deliberately never calls it — the feed itself is
/// unauthenticated (docs/PRD.md: viewers browse for free).
class ReelApiClient {
  ReelApiClient({required this.baseUrl, required this.tokenProvider});

  final String baseUrl;
  final Future<String?> Function() tokenProvider;

  Future<UploadTarget> createUploadTarget() async {
    final token = await _requireToken();
    final response = await http.post(
      Uri.parse('$baseUrl/v1/reels/uploads'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 201) {
      throw HttpException(_errorMessage(response));
    }
    return UploadTarget.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Uploads the raw video bytes to an [UploadTarget.uploadUrl] — a plain
  /// streamed request, not multipart: the local dev stub
  /// (internal/reels.LocalVideoStorage) just writes the request body
  /// straight to disk. Swapping to the real Cloudflare backend later means
  /// this method starts branching on [UploadTarget.uploadMethod]/a
  /// multipart body instead; nothing upstream of it needs to change.
  Future<void> uploadVideoFile(UploadTarget target, File file) async {
    final request = http.StreamedRequest(target.uploadMethod, Uri.parse(target.uploadUrl));
    request.contentLength = await file.length();
    file.openRead().listen(
      request.sink.add,
      onDone: request.sink.close,
      onError: request.sink.addError,
    );
    final response = await http.Client().send(request);
    if (response.statusCode != 204) {
      final body = await response.stream.bytesToString();
      throw HttpException('video upload failed: ${response.statusCode} $body');
    }
  }

  Future<Reel> createReel({
    required String videoId,
    required String category,
    String? caption,
  }) async {
    final token = await _requireToken();
    final response = await http.post(
      Uri.parse('$baseUrl/v1/reels'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'video_id': videoId,
        'category': category,
        if (caption != null && caption.isNotEmpty) 'caption': caption,
      }),
    );
    if (response.statusCode != 201) {
      throw HttpException(_errorMessage(response));
    }
    return Reel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<FeedPage> listFeed({String? category, String? cursor}) async {
    final query = <String, String>{
      if (category != null) 'category': category,
      if (cursor != null) 'cursor': cursor,
    };
    final uri = Uri.parse('$baseUrl/v1/reels').replace(queryParameters: query.isEmpty ? null : query);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (body['reels'] as List)
        .cast<Map<String, dynamic>>()
        .map(Reel.fromJson)
        .toList();
    return FeedPage(reels: items, nextCursor: body['next_cursor'] as String?);
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
