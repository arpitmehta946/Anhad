import 'package:flutter/material.dart';

import 'colors.dart';

/// Builds the Dusk and Prabhat themes from `docs/FRONTEND_GUIDELINES.md` §2-3.
///
/// Display type (Fraunces) and body/UI type (Work Sans), plus the Devanagari
/// pairing, are Phase 1 work once the font assets are vendored — this
/// skeleton uses the platform default so the app runs today.
class AppTheme {
  const AppTheme._();

  static ThemeData get dusk => _build(
        brightness: Brightness.dark,
        bgBase: AnhadColors.duskBgBase,
        bgSurface: AnhadColors.duskBgSurface,
        textPrimary: AnhadColors.duskTextPrimary,
        textSecondary: AnhadColors.duskTextSecondary,
      );

  static ThemeData get prabhat => _build(
        brightness: Brightness.light,
        bgBase: AnhadColors.prabhatBgBase,
        bgSurface: AnhadColors.prabhatBgSurface,
        textPrimary: AnhadColors.prabhatTextPrimary,
        textSecondary: AnhadColors.prabhatTextSecondary,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bgBase,
    required Color bgSurface,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AnhadColors.accentDiya,
      onPrimary: textPrimary,
      secondary: AnhadColors.accentTulsi,
      onSecondary: textPrimary,
      error: AnhadColors.accentSindoor,
      onError: textPrimary,
      surface: bgSurface,
      onSurface: textPrimary,
      // Material 3 otherwise tints elevated surfaces (including the AppBar)
      // with a baseline purple `surfaceTint` that this constructor doesn't
      // derive from `primary` — left unset, chrome reads as generic
      // Material purple instead of the Dusk/Prabhat palette above.
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgBase,
      appBarTheme: AppBarTheme(
        backgroundColor: bgBase,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            bodyColor: textPrimary,
            displayColor: textPrimary,
          ),
      useMaterial3: true,
    );
  }
}
