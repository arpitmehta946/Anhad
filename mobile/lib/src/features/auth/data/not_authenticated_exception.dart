/// Thrown by an authenticated API client's own token-resolution helper
/// (e.g. ReelApiClient/_requireToken) when there's no usable session to
/// attach — either nobody has signed in, or a previously valid session
/// just died and couldn't be renewed (AuthController.validAccessToken
/// returned null either way; the two look identical from here, and need
/// the same response: sign in again).
///
/// Kept as its own type rather than the plain StateError every client used
/// to throw, so the UI layer (features/auth/auth_error.dart) can react to
/// this one specific case with sign-in-specific copy and an actual way
/// back into an account, instead of a generic action-failed message with
/// nothing to do about it (docs/FRONTEND_GUIDELINES.md §9).
class NotAuthenticatedException implements Exception {
  const NotAuthenticatedException();

  @override
  String toString() => 'not signed in, or the session could not be renewed';
}
