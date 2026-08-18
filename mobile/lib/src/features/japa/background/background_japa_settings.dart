import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'background_japa_mode_enabled';

/// Whether "background japa mode" is on (docs/PRD.md §7.4) — persisted so
/// it survives restarts, off by default since it involves a foreground
/// service and a battery-optimization exemption prompt.
class BackgroundJapaSettings extends StateNotifier<bool> {
  BackgroundJapaSettings() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }
}

final backgroundJapaSettingsProvider =
    StateNotifierProvider<BackgroundJapaSettings, bool>(
  (ref) => BackgroundJapaSettings(),
);
