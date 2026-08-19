import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../config.dart';
import 'data/auth_api_client.dart';
import 'data/jwt.dart';
import 'data/token_store.dart';

class AuthState {
  const AuthState({
    this.checkingSession = true,
    this.isAuthenticated = false,
    this.phoneNumber,
    this.isSubmitting = false,
    this.error,
  });

  /// True until the stored-session check on app start resolves — the app
  /// shell shows a loading state rather than flashing the login screen.
  final bool checkingSession;

  final bool isAuthenticated;

  /// The number an OTP was last requested for. Non-null means the login
  /// screen should show the code-entry step rather than the phone step.
  final String? phoneNumber;

  final bool isSubmitting;
  final String? error;

  AuthState copyWith({
    bool? checkingSession,
    bool? isAuthenticated,
    String? phoneNumber,
    bool clearPhoneNumber = false,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      checkingSession: checkingSession ?? this.checkingSession,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      phoneNumber: clearPhoneNumber ? null : (phoneNumber ?? this.phoneNumber),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Owns the phone-OTP login flow and the token lifecycle: requesting and
/// verifying codes, persisting the resulting tokens via [TokenStore], and
/// transparently rotating the access token through [validAccessToken] —
/// every authenticated API client (japa taps included) should resolve its
/// bearer token through this rather than reading storage directly.
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._api, this._tokenStore) : super(const AuthState()) {
    _restore();
  }

  final AuthApiClient _api;
  final TokenStore _tokenStore;

  Future<void> _restore() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (!mounted) return;
    state = state.copyWith(
      checkingSession: false,
      isAuthenticated: refreshToken != null,
    );
  }

  Future<void> requestOtp(String phoneNumber) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _api.requestOtp(phoneNumber);
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, phoneNumber: phoneNumber);
    } catch (e, stackTrace) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: _describe(e, stackTrace));
    }
  }

  Future<void> verifyOtp(String code) async {
    final phoneNumber = state.phoneNumber;
    if (phoneNumber == null) return;

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final tokens = await _api.verifyOtp(phoneNumber, code);
      await _tokenStore.save(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, isAuthenticated: true);
    } catch (e, stackTrace) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: _describe(e, stackTrace));
    }
  }

  /// Back to the phone-entry step, e.g. the user mistyped their number.
  void changeNumber() {
    state = state.copyWith(clearPhoneNumber: true, clearError: true);
  }

  Future<void> logout() async {
    await _tokenStore.clear();
    if (!mounted) return;
    state = const AuthState(checkingSession: false);
  }

  /// Returns a currently-valid access token, refreshing first if the stored
  /// one is missing/expiring — or null if there's no session at all, or the
  /// refresh token itself has died (in which case this also signs the user
  /// out). Every authenticated API client should call this rather than
  /// reading a token once and holding onto it.
  Future<String?> validAccessToken() async {
    final accessToken = await _tokenStore.readAccessToken();
    if (accessToken == null) return null;

    final expiry = jwtExpiry(accessToken);
    final expiringSoon = expiry == null ||
        DateTime.now().toUtc().isAfter(
              expiry.subtract(const Duration(seconds: 30)),
            );
    if (!expiringSoon) return accessToken;

    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) return null;

    try {
      final tokens = await _api.refresh(refreshToken);
      await _tokenStore.save(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens.accessToken;
    } catch (_) {
      // The refresh token is dead (expired, already used, or revoked) —
      // there's no way back into this session without logging in again.
      await _tokenStore.clear();
      if (mounted) {
        state = state.copyWith(isAuthenticated: false, clearPhoneNumber: true);
      }
      return null;
    }
  }

  /// Turns a caught error into copy a person can actually act on
  /// (docs/FRONTEND_GUIDELINES.md §9: say what happened and what to do,
  /// never surface raw exception/OS detail). The one case with anything
  /// genuinely useful to show is [HttpException] thrown by [AuthApiClient]
  /// — its message *is* the server's own {"error": "..."} response
  /// (api/internal/server/auth.go), already written as plain, person-facing
  /// copy, not a stack-trace fragment. Everything else — a dropped
  /// connection, a timeout, a malformed response — never got far enough to
  /// have anything server-written to relay, so there's nothing accurate to
  /// show beyond "something's wrong, try again"; the real cause goes to the
  /// log instead of the screen.
  String _describe(Object e, StackTrace stackTrace) {
    if (e is HttpException) return e.message;
    developer.log(
      'auth request failed',
      name: 'auth',
      error: e,
      stackTrace: stackTrace,
    );
    return "Couldn't reach the server. Check your connection and try again.";
  }
}

final authApiClientProvider = Provider<AuthApiClient>((ref) {
  return AuthApiClient(baseUrl: apiBaseUrl);
});

final tokenStoreProvider = Provider<TokenStore>((ref) {
  return TokenStore(const FlutterSecureStorage());
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.watch(authApiClientProvider),
    ref.watch(tokenStoreProvider),
  );
});
