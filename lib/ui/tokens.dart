import 'package:flutter/widgets.dart';

/// Flat design tokens for MPV Studio.
///
/// Deliberately flat: no shadows, no glows, no gradients. Hierarchy is
/// carried by surface colour and spacing alone. The single accent
/// (`accent`) is used sparingly — transport, progress, active state.
class Tokens {
  Tokens._();

  // ---- Surfaces (near-black, layered by lightness) ----------------
  static const Color bg = Color(0xFF0E0F11);
  static const Color surface = Color(0xFF16181B);
  static const Color surface2 = Color(0xFF1C1F23);
  static const Color surface3 = Color(0xFF24282D);

  // ---- Hairlines (flat borders, never shadows) --------------------
  static const Color line = Color(0x12FFFFFF); // ~7% white
  static const Color line2 = Color(0x1FFFFFFF); // ~12% white

  // ---- Text -------------------------------------------------------
  static const Color fg = Color(0xFFE6E8EA);
  static const Color fgDim = Color(0xFF8A9097);
  static const Color fgFaint = Color(0xFF565C63);

  // ---- Accent (the one blue) --------------------------------------
  static const Color accent = Color(0xFF91D8F9);
  static const Color accentDim = Color(0xFF4E8BAA);
  static const Color onAccent = Color(0xFF08151C);
  static const Color accentWash = Color(0x2291D8F9); // ~13% for active fills

  // ---- Semantic ---------------------------------------------------
  static const Color green = Color(0xFF5FD39A);
  static const Color amber = Color(0xFFE9C46A);
  static const Color red = Color(0xFFE55A5A);

  // ---- Radius -----------------------------------------------------
  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 16;
  static const double rPill = 999;

  // ---- Spacing ----------------------------------------------------
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  // ---- Type -------------------------------------------------------
  static const String mono = 'monospace';

  static const TextStyle title = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w600,
    color: fg,
    letterSpacing: -0.2,
  );
  static const TextStyle heading = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: fg,
  );
  static const TextStyle body = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    color: fg,
  );
  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: fgDim,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: fgFaint,
  );
  static const TextStyle numeric = TextStyle(
    fontFamily: mono,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    color: fgDim,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ---- Breakpoint -------------------------------------------------
  /// Below this width the app uses the mobile shell (tab bar + sheets);
  /// at or above it uses the desktop shell (sidebar + dock).
  static const double desktopBreakpoint = 720;
}
