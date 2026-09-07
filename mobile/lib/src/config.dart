/// Overridable at run time: `flutter run --dart-define=API_BASE_URL=...`.
/// Defaults to the Android-emulator loopback alias for the local API
/// (docs/TECH_STACK.md §2, §4) — a physical device over USB instead needs
/// `adb reverse tcp:8080 tcp:8080` plus `API_BASE_URL=http://localhost:8080`.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

/// Applied to every plain JSON API call via `.timeout(apiRequestTimeout)`
/// (every *_api_client.dart file). package:http's top-level get/post/patch
/// wrap dart:io's HttpClient, which has no default timeout of its own — a
/// dead or half-open connection (a stale local dev tunnel, a flaky mobile
/// network — docs/GAPS.md, "Engineering hygiene") would otherwise hang the
/// request forever instead of failing into the app's own already-correct
/// "Couldn't load/save... Check your connection and try again." error
/// states. 20s is generous for a small JSON payload even on a slow 3G
/// connection, short enough that a genuinely dead connection doesn't read
/// as a frozen app.
const apiRequestTimeout = Duration(seconds: 20);

/// Applied instead of [apiRequestTimeout] to the one request that isn't a
/// small JSON payload: ReelApiClient.uploadVideoFile's raw video-byte send.
/// Matches the pre-signed upload URL's own 5-minute validity window
/// (api/internal/reels.UploadTarget.ExpiresAt) — no point timing the
/// upload out any sooner than that URL itself would already reject it.
const apiUploadTimeout = Duration(minutes: 5);
