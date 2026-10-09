import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// Compatibility layer.
///
/// The visual identity now lives in `lib/ui/design/` (tokens.dart, theme.dart
/// and the Mq* components). This file keeps the old names so the screens that
/// have not been rebuilt yet still compile: `AppColors` holds the SAME brand
/// colours as the new light palette (D-1 DS1), and `AppTheme.light()/dark()`
/// build the new theme. New code reads colours through `context.mq`, which
/// follows the light/dark theme; `AppColors` is fixed to light and is only
/// for the old screens until they are replaced.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0A6B6B);
  static const Color primaryDark = Color(0xFF064B4D);
  static const Color secondary = Color(0xFFF5A524);
  static const Color surface = Color(0xFFF4F6F9);
  static const Color success = Color(0xFF16764C);
  static const Color warning = Color(0xFFF5A524);
  static const Color danger = Color(0xFFB8420F);
  static const Color textPrimary = Color(0xFF0C1A2B);
  static const Color textSecondary = Color(0xFF41526A);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => buildMqTheme(MqPalette.light);
  static ThemeData dark() => buildMqTheme(MqPalette.dark);
}
