import 'package:flutter/material.dart';

/// App-wide Material 3 theme inspired by the 1Password 8 desktop palette.
abstract final class AppTheme {
  static const Color _primary = Color(0xFF0A3B48);
  static const Color _darkBackground = Color(0xFF0F172A);
  static const Color _darkSurface = Color(0xFF111827);
  static const Color _darkPanel = Color(0xFF1E293B);
  static const List<String> _fontFallback = <String>[
    'Segoe UI Variable',
    'Segoe UI',
    'SF Pro Text',
    'Roboto',
    'Arial',
  ];

  static ThemeData light({
    String fontFamily = 'Inter',
    int sizeDelta = 0,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
    );
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: _primary,
      secondary: const Color(0xFF818CF8),
      tertiary: const Color(0xFF14B8A6),
      surface: const Color(0xFFF8FAFC),
      surfaceContainerHighest: const Color(0xFFFFFFFF),
      outlineVariant: const Color(0xFFE2E8F0),
    );

    return _buildTheme(base, colorScheme,
        fontFamily: fontFamily, sizeDelta: sizeDelta);
  }

  static ThemeData dark({
    String fontFamily = 'Inter',
    int sizeDelta = 0,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
    );
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _primary,
      onPrimary: Colors.white,
      secondary: const Color(0xFF8B9CFD),
      tertiary: const Color(0xFF2DD4BF),
      error: const Color(0xFFF87171),
      surface: _darkSurface,
      surfaceContainerHighest: _darkPanel,
      onSurface: const Color(0xFFF8FAFC),
      onSurfaceVariant: const Color(0xFFCBD5E1),
      outline: const Color(0xFF475569),
      outlineVariant: const Color(0xFF334155),
      shadow: const Color(0x99000000),
    );

    return _buildTheme(base, colorScheme,
            fontFamily: fontFamily, sizeDelta: sizeDelta)
        .copyWith(
      scaffoldBackgroundColor: _darkBackground,
      canvasColor: _darkBackground,
    );
  }

  static ThemeData _buildTheme(
    ThemeData base,
    ColorScheme colorScheme, {
    String fontFamily = 'Inter',
    int sizeDelta = 0,
  }) {
    final textTheme = _increaseTextTheme(
      _withFontFallback(
        base.textTheme.apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
          fontFamily: fontFamily,
        ),
      ),
      (2 + sizeDelta).toDouble(),
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme.copyWith(
        displaySmall: textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.45),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.surfaceContainerHighest,
        contentTextStyle: textTheme.bodyMedium,
      ),
      dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.55),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHighest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static TextTheme _withFontFallback(TextTheme textTheme) {
    TextStyle? style(TextStyle? source) {
      if (source == null) {
        return null;
      }
      return source.copyWith(fontFamilyFallback: _fontFallback);
    }

    return textTheme.copyWith(
      displayLarge: style(textTheme.displayLarge),
      displayMedium: style(textTheme.displayMedium),
      displaySmall: style(textTheme.displaySmall),
      headlineLarge: style(textTheme.headlineLarge),
      headlineMedium: style(textTheme.headlineMedium),
      headlineSmall: style(textTheme.headlineSmall),
      titleLarge: style(textTheme.titleLarge),
      titleMedium: style(textTheme.titleMedium),
      titleSmall: style(textTheme.titleSmall),
      bodyLarge: style(textTheme.bodyLarge),
      bodyMedium: style(textTheme.bodyMedium),
      bodySmall: style(textTheme.bodySmall),
      labelLarge: style(textTheme.labelLarge),
      labelMedium: style(textTheme.labelMedium),
      labelSmall: style(textTheme.labelSmall),
    );
  }

  static TextTheme _increaseTextTheme(TextTheme textTheme, double delta) {
    TextStyle? grow(TextStyle? source) {
      final fontSize = source?.fontSize;
      if (source == null || fontSize == null) {
        return source;
      }
      return source.copyWith(fontSize: fontSize + delta);
    }

    return textTheme.copyWith(
      displayLarge: grow(textTheme.displayLarge),
      displayMedium: grow(textTheme.displayMedium),
      displaySmall: grow(textTheme.displaySmall),
      headlineLarge: grow(textTheme.headlineLarge),
      headlineMedium: grow(textTheme.headlineMedium),
      headlineSmall: grow(textTheme.headlineSmall),
      titleLarge: grow(textTheme.titleLarge),
      titleMedium: grow(textTheme.titleMedium),
      titleSmall: grow(textTheme.titleSmall),
      bodyLarge: grow(textTheme.bodyLarge),
      bodyMedium: grow(textTheme.bodyMedium),
      bodySmall: grow(textTheme.bodySmall),
      labelLarge: grow(textTheme.labelLarge),
      labelMedium: grow(textTheme.labelMedium),
      labelSmall: grow(textTheme.labelSmall),
    );
  }
}
