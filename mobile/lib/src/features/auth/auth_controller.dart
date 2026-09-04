import 'dart:async';
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
    this.role,
    this.isModerator = false,
    this.userId,
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

  /// Decoded from the access token (data/jwt.dart's jwtRole) — a UI-only
  /// signal for things like showing the upload entry point to a creator.
  /// The real enforcement is server-side
  /// (api/internal/server/reels.go's requireRole), so this being stale or
  /// absent only ever hides a button early, never grants access late.
  final String? role;

  /// Decoded from the access token (data/jwt.dart's jwtIsModerator) — same
  /// UI-only caveat as [role]: shows/hides the moderation queue entry
  /// point, never the real enforcement
  /// (api/internal/server/moderation.go's requireModerator).
  final bool isModerator;

  /// Decoded from the access token (data/jwt.dart's jwtUserId) — same
  /// UI-only caveat as [role]/[isModerator]: lets the UI recognize "this is
  /// my own reel" (e.g. hiding the Sevak/follow control on it), never the
  /// real enforcement, which is internal/social.ErrCannotFollowSelf
  /// server-side.
  final String? userId;

  bool get isCreator => role == 'creator';

  AuthState copyWith({
    bool? checkingSession,
    bool? isAuthenticated,
    String? phoneNumber,
    bool clearPhoneNumber = false,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
    String? role,
    bool? isModerator,
    String? userId,
  }) {
    return AuthState(
      checkingSession: checkingSession ?? this.checkingSession,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      phoneNumber: clearPhoneNumber ? null : (phoneNumber ?? this.phoneNumber),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
      role: role ?? this.role,
      isModerator: isModerator ?? this.isModerator,
      userId: userId ?? this.userId,
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
    _restoreCompleter.complete(_restore());
  }

  final AuthApiClient _api;

  final _restoreCompleter = Completer<void>();

  /// Resolves once the stored-session check on app start has actually
  /// finished — [state.isAuthenticated] reads as its default `false`
  /// until then, not as "genuinely signed out." A caller that routes on
  /// [state.isAuthenticated] before this resolves (the arrival screen's
  /// "Begin" handler used to) can catch that default and send a signed-in
  /// returning user down the wrong path — observed as landing on the japa
  /// screen instead of the feed right after a fresh app open.
  Future<void> get initialized => _restoreCompleter.future;
  final TokenStore _tokenStore;

  // The in-memory source of truth for the rest of this process's life,
  // once _restore() has primed them — [TokenStore] is write-through
  // persistence for the *next* cold start, not the thing every call reads
  // from. That distinction is what lets a refreshed token pair keep
  // working for the current session even if persisting it to secure
  // storage happens to fail right after a successful server-side rotation
  // (see _refresh's own doc for why that specific failure must not be
  // treated the same as a genuinely dead session).
  String? _accessToken;
  String? _refreshToken;

  // Ensures at most one /v1/auth/refresh call is ever in flight at a time.
  // api/internal/auth/token.go's RefreshTokens deletes the redeemed
  // refresh token before minting the next one — "a client that races a
  // refresh against itself gets exactly one winner" is that function's own
  // stated intent, but nothing on this side previously enforced it: five
  // independent API clients (reels, social, japa taps, japa streak,
  // moderation) each resolve their own bearer token by calling
  // validAccessToken() straight from their own request path, with no
  // coordination between them. A cold app resume after the access token's
  // 15-minute TTL has long since passed — exactly the "backgrounded for
  // hours" scenario — fires several of these nearly simultaneously; without
  // this, every loser of that race redeemed a token that had already been
  // consumed by the winner, got ErrRefreshInvalid back, and (before this
  // fix) wiped the *entire* stored session in response — including
  // whichever fresh pair the winner had just saved, if its own save() had
  // already landed. Single-flighting means every one of those concurrent
  // callers shares the exact same refresh attempt and its exact same
  // outcome, so the race this describes can no longer happen at all.
  Future<String?>? _refreshInFlight;

  Future<void> _restore() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    final accessToken = await _tokenStore.readAccessToken();
    _refreshToken = refreshToken;
    _accessToken = accessToken;
    if (!mounted) return;
    state = state.copyWith(
      checkingSession: false,
      isAuthenticated: refreshToken != null,
      role: accessToken != null ? jwtRole(accessToken) : null,
      isModerator: accessToken != null && jwtIsModerator(accessToken),
      userId: accessToken != null ? jwtUserId(accessToken) : null,
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
      state =
          state.copyWith(isSubmitting: false, error: _describe(e, stackTrace));
    }
  }

  Future<void> verifyOtp(String code) async {
    final phoneNumber = state.phoneNumber;
    if (phoneNumber == null) return;

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final tokens = await _api.verifyOtp(phoneNumber, code);
      _accessToken = tokens.accessToken;
      _refreshToken = tokens.refreshToken;
      await _tokenStore.save(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        isAuthenticated: true,
        role: jwtRole(tokens.accessToken),
        isModerator: jwtIsModerator(tokens.accessToken),
        userId: jwtUserId(tokens.accessToken),
      );
    } catch (e, stackTrace) {
      if (!mounted) return;
      state =
          state.copyWith(isSubmitting: false, error: _describe(e, stackTrace));
    }
  }

  /// Back to the phone-entry step, e.g. the user mistyped their number.
  void changeNumber() {
    state = state.copyWith(clearPhoneNumber: true, clearError: true);
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    await _tokenStore.clear();
    if (!mounted) return;
    state = const AuthState(checkingSession: false);
  }

  /// Returns a currently-valid access token, refreshing first if the stored
  /// one is missing/expiring — or null if there's no session at all, or the
  /// refresh token itself has died (in which case this also signs the user
  /// out). Every authenticated API client should call this rather than
  /// reading a token once and holding onto it.
  ///
  /// Concurrent callers during a refresh all share the one in-flight
  /// attempt via [_refreshInFlight] — see its own doc for why that's not
  /// optional.
  Future<String?> validAccessToken() async {
    final accessToken = _accessToken;
    if (accessToken == null) return null;

    final expiry = jwtExpiry(accessToken);
    final expiringSoon = expiry == null ||
        DateTime.now().toUtc().isAfter(
              expiry.subtract(const Duration(seconds: 30)),
            );
    if (!expiringSoon) return accessToken;

    return _refreshInFlight ??=
        _refresh().whenComplete(() => _refreshInFlight = null);
  }

  /// Redeems the stored refresh token for a new pair. Two failure modes
  /// here are genuinely different and must not be handled the same way:
  ///
  /// - The *redemption itself* fails ([_api.refresh] throws) — the token
  ///   was rejected outright (expired, already used, or revoked). There is
  ///   no session left to recover; signing out is the only correct
  ///   response.
  /// - The redemption *succeeds* but persisting the result fails (a
  ///   secure-storage write error, or the process dying mid-write during
  ///   exactly the kind of backgrounding event that motivated this fix).
  ///   By this point the server has already rotated: the *old* refresh
  ///   token is dead either way, whether or not this write ever lands. The
  ///   new pair is real and valid right now — wiping it out because it
  ///   didn't get persisted would turn a successful refresh into a forced
  ///   logout for no reason. Instead this keeps serving the new tokens
  ///   from memory for the rest of this process's life; if the process
  ///   really did die before the write landed, the next cold start's
  ///   _restore() reads the stale token from disk and signs out cleanly
  ///   then — a normal, explained "please sign in again," not a silent one.
  Future<String?> _refresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return null;

    final AuthTokens tokens;
    try {
      tokens = await _api.refresh(refreshToken);
    } catch (_) {
      _accessToken = null;
      _refreshToken = null;
      await _tokenStore.clear();
      if (mounted) {
        state = state.copyWith(isAuthenticated: false, clearPhoneNumber: true);
      }
      return null;
    }

    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
    if (mounted) {
      state = state.copyWith(
        isAuthenticated: true,
        role: jwtRole(tokens.accessToken),
        isModerator: jwtIsModerator(tokens.accessToken),
        userId: jwtUserId(tokens.accessToken),
      );
    }

    try {
      await _tokenStore.save(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    } catch (e, stackTrace) {
      developer.log(
        'failed to persist refreshed tokens — serving them from memory '
        'for the rest of this session instead',
        name: 'auth',
        error: e,
        stackTrace: stackTrace,
      );
    }

    return tokens.accessToken;
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
