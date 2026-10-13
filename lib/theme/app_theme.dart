import 'package:flutter/material.dart';

class AppTheme {
  static const orange = Color(0xFFF46B38);
  static const accent = Color(0xFFB94317);
  static const ink = Color(0xFF182B33);
  static const muted = Color(0xFF697780);
  static const background = Color(0xFFF7F8FA);
  static const line = Color(0xFFE8ECEF);
  static const green = Color(0xFF18765A);
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansThai',
      colorScheme: ColorScheme.fromSeed(
        seedColor: orange,
        primary: accent,
        secondary: green,
        surface: Colors.white,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme
          .apply(bodyColor: ink, displayColor: ink)
          .copyWith(
            headlineLarge: const TextStyle(
              fontFamily: 'NotoSansThai',
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
            headlineSmall: const TextStyle(
              fontFamily: 'NotoSansThai',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
            titleLarge: const TextStyle(
              fontFamily: 'NotoSansThai',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
            titleMedium: const TextStyle(
              fontFamily: 'NotoSansThai',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: orange, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: orange,
          foregroundColor: ink,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'NotoSansThai',
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: const BorderSide(color: line),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFFFFEEE7),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        labelStyle: const TextStyle(fontFamily: 'NotoSansThai', color: ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFFFEEE7),
        height: 86,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontFamily: 'NotoSansThai',
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(
        color: line,
        thickness: 1,
        space: 24,
      ),
    );
  }
}
