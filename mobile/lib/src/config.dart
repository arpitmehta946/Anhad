/// Overridable at run time: `flutter run --dart-define=API_BASE_URL=...`.
/// Defaults to the dev machine's WiFi LAN IP (also whitelisted in
/// android/app/src/debug/res/xml/network_security_config.xml) so a physical
/// device reaches the API directly over WiFi — no `adb reverse` tunnel,
/// which silently goes dead on reconnect/reboot/reinstall while
/// `adb reverse --list` keeps reporting it as registered (docs/GAPS.md,
/// "Engineering hygiene"). This project only ever runs on a physical
/// device, never the emulator (see CLAUDE.md) — if that ever changes, the
/// emulator needs `--dart-define=API_BASE_URL=http://10.0.2.2:8080`
/// instead. DHCP-assigned — if it changes, `ipconfig` on Windows shows the
/// current one under the WiFi adapter; update it here, in
/// network_security_config.xml, and in api/.env's PUBLIC_BASE_URL (which
/// must match — it's what the API stamps into local-storage playback URLs
/// returned to this client).
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.1.3:8080',
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
