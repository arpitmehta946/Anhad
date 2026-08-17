import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the access/refresh token pair in the platform keystore
/// (Android Keystore / iOS Keychain via flutter_secure_storage) rather than
/// Isar — these are bearer credentials, not app data, and don't belong in a
/// plain on-disk database file.
class TokenStore {
  TokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'anhad.auth.access_token';
  static const _refreshTokenKey = 'anhad.auth.refresh_token';
  static const _accessTokenExpiryKey = 'anhad.auth.access_token_expiry';

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required DateTime accessTokenExpiry,
  }) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      _storage.write(
        key: _accessTokenExpiryKey,
        value: accessTokenExpiry.toIso8601String(),
      ),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _accessTokenExpiryKey),
    ]);
  }

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<DateTime?> readAccessTokenExpiry() async {
    final raw = await _storage.read(key: _accessTokenExpiryKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }
}
