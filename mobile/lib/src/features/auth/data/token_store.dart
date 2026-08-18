import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the access/refresh token pair in the platform keystore
/// (Android Keystore / iOS Keychain via flutter_secure_storage) rather than
/// Isar — these are bearer credentials, not app data, and don't belong in a
/// plain on-disk database file.
///
/// Deliberately doesn't also store the access token's expiry — see
/// `data/jwt.dart` for why that's derived from the token itself instead.
class TokenStore {
  TokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'anhad.auth.access_token';
  static const _refreshTokenKey = 'anhad.auth.refresh_token';

  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);
}
