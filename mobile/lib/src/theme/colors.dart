import 'package:flutter/widgets.dart';

/// Color tokens from `docs/FRONTEND_GUIDELINES.md` §2.
///
/// Dusk is the default theme; Prabhat is a full light theme, not a bolted-on
/// inversion. Both are first-class citizens — see the guidelines for why.
class AnhadColors {
  const AnhadColors._();

  // Dusk (default / dark)
  static const duskBgBase = Color(0xFF1B1730);
  static const duskBgSurface = Color(0xFF2E2347);
  static const duskTextPrimary = Color(0xFFF3EADD);
  static const duskTextSecondary = Color(0xFFB8A78E);

  // Prabhat (light)
  static const prabhatBgBase = Color(0xFFFBF3E4);
  static const prabhatBgSurface = Color(0xFFF3E7CE);
  static const prabhatTextPrimary = Color(0xFF2B2418);
  static const prabhatTextSecondary = Color(0xFF7A6F58);

  // Shared accents
  static const accentDiya = Color(0xFFE8A33D);
  static const accentTulsi = Color(0xFF7A9471);
  static const accentSindoor = Color(0xFFC4463A);
}
