import 'package:flutter/material.dart';

/// AlarmHQ brand: glowing lime-green + charcoal (user-approved 2026-10-14).
/// Single shade #a3e635 — no gradients.
class AppTheme {
  static const emerald = Color(0xFFA3E635);
  static const emeraldDark = Color(0xFF7CB518);
  static const charcoal = Color(0xFF23272E);
  static const charcoalSurface = Color(0xFF2C313A);
  static const charcoalCard = Color(0xFF343B46);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.dark,
    ).copyWith(
      primary: emerald,
      secondary: emerald,
      surface: charcoalSurface,
    );
    return ThemeData(
      useMaterial3: true,
      // v2.39: embedded Noto Nastaliq Urdu (subset: Urdu script only). English text and digits fall back to system font.
      fontFamily: 'NotoNastaliqUrdu',
      colorScheme: scheme,
      scaffoldBackgroundColor: charcoal,
      appBarTheme: const AppBarTheme(
        backgroundColor: charcoal,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: charcoalCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: emerald,
        foregroundColor: Colors.white,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: charcoalSurface,
        dialHandColor: emerald,
        dialBackgroundColor: charcoalCard,
        hourMinuteTextColor: Colors.white,
        dayPeriodTextColor: Colors.white70,
      ),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.light,
    ).copyWith(primary: emeraldDark, secondary: emeraldDark);
    return ThemeData(
      useMaterial3: true,
      // v2.39: embedded Noto Nastaliq Urdu (subset: Urdu script only). English text and digits fall back to system font.
      fontFamily: 'NotoNastaliqUrdu',
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: charcoal,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: emerald,
        foregroundColor: Colors.white,
      ),
    );
  }
}
