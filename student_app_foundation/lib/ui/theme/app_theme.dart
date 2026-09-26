import 'package:flutter/material.dart';

/// Central visual identity for "مرافق التلميذ" (Marafiq Ettilmidh).
/// Single source of truth for colors/typography so no screen hardcodes
/// its own palette — kept intentionally simple (no external fonts, since
/// custom font files can't be verified/downloaded in this sandbox; the
/// system Arabic font on Android/iOS/web is already good quality).
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF1E5F74); // Deep teal-blue
  static const Color primaryDark = Color(0xFF14424F);
  static const Color secondary = Color(0xFFE8A33D); // Warm amber accent
  static const Color surface = Color(0xFFF7F9FA);
  static const Color success = Color(0xFF2E8B57);
  static const Color warning = Color(0xFFE0A106);
  static const Color danger = Color(0xFFC0392B);
  static const Color textPrimary = Color(0xFF1A2B32);
  static const Color textSecondary = Color(0xFF5C6F76);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.surface,
    );
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        elevation: 1,
        margin: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD8E0E3)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ),
    );
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        centerTitle: true,
        elevation: 0,
      ),
    );
  }
}
