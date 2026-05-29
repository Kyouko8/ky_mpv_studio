import 'package:flutter/material.dart';
import 'tokens.dart';

/// Flat dark theme. Material widgets are reconfigured so nothing emits
/// elevation, splash glows, or overlays — the look is uniformly flat.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      surface: Tokens.bg,
      primary: Tokens.accent,
      onPrimary: Tokens.onAccent,
      secondary: Tokens.accent,
      error: Tokens.red,
      onSurface: Tokens.fg,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Tokens.bg,
      canvasColor: Tokens.bg,
      // Flat: kill ripple/highlight glows everywhere.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: const Color(0x0AFFFFFF),
      dividerColor: Tokens.line,
      textTheme: const TextTheme(
        titleLarge: Tokens.title,
        titleMedium: Tokens.heading,
        bodyMedium: Tokens.body,
        labelMedium: Tokens.label,
        bodySmall: Tokens.caption,
      ),
      iconTheme: const IconThemeData(color: Tokens.fgDim, size: 22),
      sliderTheme: const SliderThemeData(
        // Flat slider: thin track, small thumb, NO overlay/glow halo.
        trackHeight: 4,
        overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        activeTrackColor: Tokens.accent,
        inactiveTrackColor: Tokens.line2,
        thumbColor: Tokens.accent,
        overlayColor: Colors.transparent,
        secondaryActiveTrackColor: Tokens.accentDim,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Tokens.onAccent
              : Tokens.fgFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Tokens.accent
              : Tokens.surface3,
        ),
        trackOutlineColor:
            const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: Tokens.surface3,
          borderRadius: BorderRadius.all(Radius.circular(Tokens.rSm)),
        ),
        textStyle: TextStyle(color: Tokens.fg, fontSize: 12),
      ),
    );

    return base;
  }
}
