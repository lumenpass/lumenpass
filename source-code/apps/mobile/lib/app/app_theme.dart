import 'package:flutter/material.dart';

class AppTheme {
  static const Color deepTeal = Color(0xFF0F3E47);
  static const Color ink = Color(0xFF0B1E23);
  static const Color mist = Color(0xFFEFF6F7);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: deepTeal,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: deepTeal,
        surface: mist,
      ),
      scaffoldBackgroundColor: const Color(0xFFF4FAFB),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: deepTeal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          height: 1.05,
          letterSpacing: -0.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.45,
        ),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

