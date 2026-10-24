import 'package:flutter/material.dart';

import 'drive_clue_tokens.dart';

/// App-wide Material 3 theme inspired by the 1Password 8 desktop palette.
abstract final class AppTheme {
  static const Color _primary = Color(0xFF0A3B48);
  static const Color _darkBackground = Color(0xFF0F172A);
  static const Color _darkSurface = Color(0xFF111827);
  static const Color _darkPanel = Color(0xFF1E293B);
  static const List<String> _fontFallback = <String>[
    'Ubuntu Sans',
    'Segoe UI Variable',
    'Segoe UI',
    'SF Pro Text',
    'Roboto',
    'Arial',
  ];

  static ThemeData light({
    String fontFamily = 'Ubuntu Sans',
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
    String fontFamily = 'Ubuntu Sans',
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

  /// DriveClue-inspired theme: dark slate surfaces, blue selection color,
  /// rounded-6/7 controls and compact padding.
  static ThemeData driveClue({
    String fontFamily = 'Ubuntu Sans',
    int sizeDelta = 0,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
    );
    final colorScheme = ColorScheme.fromSeed(
      seedColor: DcColors.selection,
      brightness: Brightness.dark,
    ).copyWith(
      primary: DcColors.selection,
      onPrimary: Colors.white,
      primaryContainer: DcColors.selectionSoft,
      onPrimaryContainer: DcColors.text,
      secondary: DcColors.cyan,
      onSecondary: DcColors.background,
      tertiary: DcColors.teal,
      error: DcColors.red,
      onError: Colors.white,
      surface: DcColors.background,
      onSurface: DcColors.text,
      onSurfaceVariant: DcColors.muted,
      surfaceContainerLowest: DcColors.well,
      surfaceContainerLow: DcColors.rowAlternate,
      surfaceContainer: DcColors.row,
      surfaceContainerHigh: DcColors.panel,
      surfaceContainerHighest: DcColors.panel,
      outline: DcColors.lineStrong,
      outlineVariant: DcColors.line,
      shadow: const Color(0x66000000),
      surfaceTint: Colors.transparent,
    );

    final themed = _buildTheme(base, colorScheme,
        fontFamily: fontFamily, sizeDelta: sizeDelta);
    final textTheme = themed.textTheme;
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
    );
    final panelShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
      side: const BorderSide(color: DcColors.line),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return themed.copyWith(
      scaffoldBackgroundColor: DcColors.background,
      canvasColor: DcColors.background,
      dividerColor: DcColors.line,
      dividerTheme: const DividerThemeData(
        color: DcColors.line,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DcColors.well,
        isDense: true,
        hintStyle: TextStyle(color: DcColors.faint, fontFamily: fontFamily),
        labelStyle: TextStyle(color: DcColors.muted, fontFamily: fontFamily),
        border: inputBorder(DcColors.lineStrong),
        enabledBorder: inputBorder(DcColors.lineStrong),
        focusedBorder: inputBorder(DcColors.selection, 1.4),
        errorBorder: inputBorder(DcColors.red),
        focusedErrorBorder: inputBorder(DcColors.red, 1.4),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          backgroundColor: DcColors.selection,
          foregroundColor: Colors.white,
          shape: controlShape,
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          backgroundColor: DcColors.selection,
          foregroundColor: Colors.white,
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          foregroundColor: DcColors.text,
          backgroundColor: const Color(0x0FFFFFFF),
          shape: controlShape,
          side: const BorderSide(color: DcColors.lineStrong),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DcColors.text,
          shape: controlShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: DcColors.muted,
          shape: controlShape,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: const BorderSide(color: DcColors.muted, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DcColors.selection
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll<Color>(Colors.white),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : DcColors.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DcColors.selection
              : DcColors.well,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DcColors.selection
              : DcColors.lineStrong,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: DcColors.selection,
        inactiveTrackColor: DcColors.barTrack,
        thumbColor: Colors.white,
        overlayColor: DcColors.selectionSoft,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: DcColors.selection,
        linearTrackColor: DcColors.barTrack,
        circularTrackColor: DcColors.barTrack,
      ),
      cardTheme: CardThemeData(
        color: DcColors.panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: panelShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DcColors.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: panelShape,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: DcColors.text,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: DcColors.muted,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: DcColors.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shape: panelShape,
        textStyle: textTheme.bodyMedium?.copyWith(color: DcColors.text),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(DcColors.panel),
          surfaceTintColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: DcColors.panel,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: DcColors.text),
        actionTextColor: DcColors.cyan,
        shape: panelShape,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xF0263340),
          borderRadius: BorderRadius.circular(DcMetrics.badgeRadius),
          border: Border.all(color: DcColors.line),
        ),
        textStyle: TextStyle(
          color: DcColors.text,
          fontSize: 11,
          fontFamily: fontFamily,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(Color(0x59FFFFFF)),
        radius: Radius.circular(999),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: DcColors.text,
        selectionColor: DcColors.selectionTint,
        selectionHandleColor: DcColors.selection,
      ),
    );
  }

  /// Light variant of [driveClue] for dialogs whose content sits on the
  /// sidebar color (`#E3EBF2`): dark sidebar text, white cards and inputs.
  static ThemeData driveClueLight({
    String fontFamily = 'Ubuntu Sans',
    int sizeDelta = 0,
  }) {
    final dark = driveClue(fontFamily: fontFamily, sizeDelta: sizeDelta);
    final colorScheme = dark.colorScheme.copyWith(
      brightness: Brightness.light,
      onPrimaryContainer: DcColors.sidebarText,
      onSecondary: Colors.white,
      surface: DcColors.sidebar,
      onSurface: DcColors.sidebarText,
      onSurfaceVariant: DcColors.sidebarMuted,
      surfaceContainerLowest: DcColors.lightSurface,
      surfaceContainerLow: DcColors.lightSurface,
      surfaceContainer: DcColors.lightSurface,
      surfaceContainerHigh: DcColors.lightSurface,
      surfaceContainerHighest: DcColors.lightSurface,
      outline: DcColors.lightLineStrong,
      outlineVariant: DcColors.sidebarLine,
      shadow: const Color(0x33000000),
    );
    final textTheme = dark.textTheme.apply(
      bodyColor: DcColors.sidebarText,
      displayColor: DcColors.sidebarText,
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
    );
    final panelShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
      side: const BorderSide(color: DcColors.sidebarLine),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return dark.copyWith(
      brightness: Brightness.light,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: DcColors.sidebar,
      canvasColor: DcColors.sidebar,
      dividerColor: DcColors.sidebarLine,
      dividerTheme: const DividerThemeData(
        color: DcColors.sidebarLine,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: dark.inputDecorationTheme.copyWith(
        fillColor: DcColors.lightSurface,
        hintStyle:
            TextStyle(color: DcColors.sidebarMuted, fontFamily: fontFamily),
        labelStyle:
            TextStyle(color: DcColors.sidebarMuted, fontFamily: fontFamily),
        border: inputBorder(DcColors.lightLineStrong),
        enabledBorder: inputBorder(DcColors.lightLineStrong),
        disabledBorder: inputBorder(DcColors.sidebarLine),
        focusedBorder: inputBorder(DcColors.selection, 1.4),
        errorBorder: inputBorder(DcColors.redOnLight),
        focusedErrorBorder: inputBorder(DcColors.redOnLight, 1.4),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          backgroundColor: DcColors.selection,
          foregroundColor: Colors.white,
          disabledBackgroundColor: DcColors.sidebarLine,
          disabledForegroundColor: DcColors.sidebarMuted,
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          foregroundColor: DcColors.sidebarText,
          backgroundColor: DcColors.lightSurface,
          disabledForegroundColor: DcColors.sidebarMuted,
          shape: controlShape,
          side: const BorderSide(color: DcColors.lightLineStrong),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DcColors.sidebarText,
          shape: controlShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: DcColors.sidebarMuted,
          shape: controlShape,
        ),
      ),
      checkboxTheme: dark.checkboxTheme.copyWith(
        side: const BorderSide(color: DcColors.sidebarMuted, width: 1.4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DcColors.selection
              : DcColors.lightLineStrong,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DcColors.selection
              : DcColors.lightLineStrong,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: DcColors.selection,
        linearTrackColor: DcColors.sidebarLine,
        circularTrackColor: DcColors.sidebarLine,
      ),
      cardTheme: dark.cardTheme.copyWith(
        color: DcColors.lightSurface,
        shape: panelShape,
      ),
      dialogTheme: dark.dialogTheme.copyWith(
        backgroundColor: DcColors.sidebar,
        shape: panelShape,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: DcColors.sidebarText,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: DcColors.sidebarMuted,
        ),
      ),
      popupMenuTheme: dark.popupMenuTheme.copyWith(
        color: DcColors.lightSurface,
        shape: panelShape,
        textStyle: textTheme.bodyMedium?.copyWith(color: DcColors.sidebarText),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(DcColors.lightSurface),
          surfaceTintColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        ),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(DcColors.lightLineStrong),
        radius: Radius.circular(999),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: DcColors.sidebarText,
        selectionColor: DcColors.selectionSoft,
        selectionHandleColor: DcColors.selection,
      ),
    );
  }

  static ThemeData _buildTheme(
    ThemeData base,
    ColorScheme colorScheme, {
    String fontFamily = 'Ubuntu Sans',
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
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontFamily: fontFamily,
        ),
        waitDuration: const Duration(milliseconds: 400),
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
