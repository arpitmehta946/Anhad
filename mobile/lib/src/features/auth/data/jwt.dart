import 'dart:convert';

/// Reads the `exp` claim out of a JWT's payload without verifying its
/// signature — verification is the server's job; this is only used
/// client-side to decide whether a proactive refresh is worth attempting.
///
/// Deliberately not persisted as a separately-computed timestamp: a
/// client-computed "issued at + TTL" expiry survives a system clock change
/// (testing, timezone travel, NTP correction) even after the clock is
/// corrected, since it was already baked into an absolute timestamp at the
/// wrong moment — silently trusting a token the server has long since
/// expired. Decoding `exp` fresh from the token itself every time avoids
/// that whole class of bug, since `exp` reflects the server's clock at
/// signing time, not whatever the client's clock happened to read then.
DateTime? jwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final exp = payload['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (exp * 1000).round(),
      isUtc: true,
    );
  } catch (_) {
    return null;
  }
}
