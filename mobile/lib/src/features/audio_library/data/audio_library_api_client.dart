import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'audio_track.dart';

class AudioLibraryPage {
  const AudioLibraryPage({required this.tracks, this.nextCursor});

  final List<AudioTrack> tracks;

  /// Pass back as the next request's `cursor` to load the next page; null
  /// means this was the last page.
  final String? nextCursor;
}

/// Talks to the audio-library endpoints (api/internal/server/audio.go,
/// docs/PRD.md §7.3). Browsing and playback are unauthenticated, same as
/// the reel feed itself — only "use this sound" (a new reel creation,
/// api/internal/server/reels.go's createReelFromAudioTrackHandler) needs a
/// token, and that call lives on ReelApiClient instead, since it produces
/// a Reel, not an AudioTrack.
class AudioLibraryApiClient {
  AudioLibraryApiClient({required this.baseUrl});

  final String baseUrl;

  /// creatorId scopes this same listing to one creator's own tracks — a
  /// profile page's sound-library tab is just this listing filtered, not a
  /// separate endpoint.
  Future<AudioLibraryPage> listLibrary({
    String? category,
    String? creatorId,
    String? cursor,
  }) async {
    final query = <String, String>{
      if (category != null) 'category': category,
      if (creatorId != null) 'creator_id': creatorId,
      if (cursor != null) 'cursor': cursor,
    };
    final uri = Uri.parse('$baseUrl/v1/audio-tracks')
        .replace(queryParameters: query.isEmpty ? null : query);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw HttpException(_errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (body['tracks'] as List)
        .cast<Map<String, dynamic>>()
        .map(AudioTrack.fromJson)
        .toList();
    return AudioLibraryPage(
        tracks: items, nextCursor: body['next_cursor'] as String?);
  }

  /// Records a play — the raw signal the future royalty batch job
  /// (docs/PRD.md §10.4) will divide the monthly pool by. Fire-and-forget
  /// from the caller's own point of view: a failed count bump shouldn't
  /// interrupt playback the listener is already hearing.
  Future<void> recordPlay(String trackId) async {
    await http.post(Uri.parse('$baseUrl/v1/audio-tracks/$trackId/plays'));
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
