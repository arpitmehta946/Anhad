import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// The server evaluated this exact batch and rejected it on its merits —
/// anti-cheat (422) or malformed/unordered taps (400) (api/internal/japa/service.go).
/// Retrying the identical batch will fail identically forever, which is why
/// this is a distinct type from [HttpException]: callers must not queue it
/// for retry the way they would a network blip or a 5xx.
class JapaTapsRejected implements Exception {
  JapaTapsRejected(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'japa tap submission rejected: $statusCode $body';
}

/// A user's standing streak plus lifetime total, from `GET /v1/japa/streak`
/// (api/internal/japa/streak.go) — current/longest consecutive days with at
/// least one full mala (docs/PRD.md §7.4), and every tap ever recorded
/// server-side (docs/ONBOARDING.md §1.3) — server-authoritative, so it
/// survives a reinstall or a new device unlike the device-local daily total.
class JapaStreak {
  const JapaStreak({
    required this.currentStreak,
    required this.longestStreak,
    required this.lifetimeTotal,
  });

  final int currentStreak;
  final int longestStreak;
  final int lifetimeTotal;

  factory JapaStreak.fromJson(Map<String, dynamic> json) => JapaStreak(
        currentStreak: json['current_streak'] as int,
        longestStreak: json['longest_streak'] as int,
        lifetimeTotal: json['lifetime_total'] as int,
      );
}

/// What [JapaSyncService] needs to submit a batch — split out from the
/// concrete [JapaApiClient] so tests can substitute a fake instead of
/// intercepting real HTTP calls (`package:http`'s top-level `post` isn't
/// injectable on its own).
abstract class JapaTapsSubmitter {
  Future<void> submitTaps(List<DateTime> taps);
}

/// Talks to `POST /v1/japa/taps` and `GET /v1/japa/streak`
/// (api/internal/server/japa.go). The auth token is resolved lazily per
/// call via [tokenProvider] rather than injected once, since it can change
/// after this client is constructed (dev sign-in today, the real login flow
/// later).
class JapaApiClient implements JapaTapsSubmitter {
  JapaApiClient({required this.baseUrl, required this.tokenProvider});

  final String baseUrl;
  final Future<String?> Function() tokenProvider;

  Future<JapaStreak> getStreak() async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('no auth token set — use developer sign-in first');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/v1/japa/streak'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'japa streak fetch failed: ${response.statusCode} ${response.body}',
      );
    }
    return JapaStreak.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
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

    if (response.statusCode == 400 || response.statusCode == 422) {
      throw JapaTapsRejected(response.statusCode, response.body);
    }
    if (response.statusCode != 201) {
      throw HttpException(
        'japa tap submission failed: ${response.statusCode} ${response.body}',
      );
    }
  }
}
