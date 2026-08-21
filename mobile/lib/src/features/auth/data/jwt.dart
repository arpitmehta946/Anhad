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

/// Reads the `role` claim out of a JWT's payload — same "not verifying the
/// signature, server already did" caveat as [jwtExpiry]. Used purely for
/// UI decisions (showing the upload entry point to a creator); the actual
/// enforcement is server-side (api/internal/server/reels.go's
/// requireRole), so a stale or spoofed value here can only ever hide or
/// show a button, never grant a real upload.
String? jwtRole(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final role = payload['role'];
    return role is String ? role : null;
  } catch (_) {
    return null;
  }
}

/// Reads the `sub` claim (the user's own id) — same "not verifying the
/// signature" caveat as [jwtExpiry]. Used to tell "this is my own reel"
/// apart from everyone else's client-side (e.g. hiding the Sevak/follow
/// control on your own content, docs/PRD.md §6) — server-side enforcement
/// of the same rule already exists independently
/// (internal/social.ErrCannotFollowSelf), so a stale/spoofed value here
/// can only ever mis-show a button, never actually let anyone follow
/// themselves.
String? jwtUserId(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final sub = payload['sub'];
    return sub is String ? sub : null;
  } catch (_) {
    return null;
  }
}

/// Reads the `is_moderator` claim — same caveats as [jwtRole]: UI-only
/// (shows/hides the moderation queue entry point), never the real
/// enforcement, which is api/internal/server/moderation.go's
/// requireModerator checking the same claim server-side.
bool jwtIsModerator(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return false;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final isModerator = payload['is_moderator'];
    return isModerator == true;
  } catch (_) {
    return false;
  }
}
