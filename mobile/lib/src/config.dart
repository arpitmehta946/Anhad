/// Overridable at run time: `flutter run --dart-define=API_BASE_URL=...`.
/// Defaults to the Android-emulator loopback alias for the local API
/// (docs/TECH_STACK.md §2, §4) — a physical device over USB instead needs
/// `adb reverse tcp:8080 tcp:8080` plus `API_BASE_URL=http://localhost:8080`.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);
