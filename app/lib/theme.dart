import 'package:flutter/material.dart';

class FarmLensColors {
  FarmLensColors._();

  static const Color primary = Color(0xFF1D9E75);
  static const Color amber = Color(0xFFBA7517);
  static const Color alert = Color(0xFFE24B4A);
  static const Color background = Color(0xFFF5F5F0);
  static const Color card = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFE8E8E4);

  static Color ccombinedColor(double value) {
    if (value < 0.4) return primary;
    if (value < 0.65) return amber;
    return alert;
  }
}

ThemeData farmLensTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: FarmLensColors.primary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: FarmLensColors.background,
    cardColor: FarmLensColors.card,
    appBarTheme: const AppBarTheme(
      backgroundColor: FarmLensColors.card,
      foregroundColor: FarmLensColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: FarmLensColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: FarmLensColors.border, width: 0.5),
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: FarmLensColors.textPrimary),
      bodyMedium: TextStyle(color: FarmLensColors.textPrimary),
      bodySmall: TextStyle(color: FarmLensColors.textSecondary),
    ),
  );
}