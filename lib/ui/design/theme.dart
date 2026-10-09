import 'package:flutter/material.dart';

import 'motion.dart';
import 'tokens.dart';

/// Builds the ThemeData of one palette. Every Material widget that is still
/// used (text fields, dialogs, date pickers, snack bars, the old screens that
/// have not been rebuilt yet) inherits the identity from here, so nothing
/// looks like stock Material while the screens are replaced batch by batch.
ThemeData buildMqTheme(MqPalette p) {
  final scheme = ColorScheme(
    brightness: p.isDark ? Brightness.dark : Brightness.light,
    primary: p.brand,
    onPrimary: p.onBrand,
    secondary: p.accent,
    onSecondary: const Color(0xFF2A1900),
    error: p.overdue,
    onError: p.isDark ? const Color(0xFF3C2016) : Colors.white,
    surface: p.surface,
    onSurface: p.ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: scheme.brightness,
  );

  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(MqSpace.radiusButton),
    borderSide: BorderSide(color: p.line),
  );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(MqSpace.radiusButton),
  );

  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.surface,
    textTheme: base.textTheme.apply(
      bodyColor: p.ink,
      displayColor: p.ink,
      fontFamily: MqType.textFamily,
      fontFamilyFallback: MqType.fallback,
    ),
    extensions: <ThemeExtension<dynamic>>[p],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: MqTransitionsBuilder(),
        TargetPlatform.iOS: MqTransitionsBuilder(),
        TargetPlatform.fuchsia: MqTransitionsBuilder(),
        TargetPlatform.linux: MqTransitionsBuilder(),
        TargetPlatform.macOS: MqTransitionsBuilder(),
        TargetPlatform.windows: MqTransitionsBuilder(),
      },
    ),
    // The screens that still use an AppBar keep a deep-teal bar in both
    // themes; the rebuilt screens use MqPage and have none.
    appBarTheme: AppBarTheme(
      backgroundColor: p.brandDeep,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: MqType.h2.copyWith(color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MqSpace.radiusCard),
        side: BorderSide(color: p.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: MqType.small.copyWith(color: p.ink2),
      hintStyle: MqType.small.copyWith(color: p.ink3),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MqSpace.radiusButton),
        borderSide: BorderSide(color: p.brand, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MqSpace.radiusButton),
        borderSide: BorderSide(color: p.overdue),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MqSpace.radiusButton),
        borderSide: BorderSide(color: p.overdue, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.brand,
        foregroundColor: p.onBrand,
        elevation: 0,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: buttonShape,
        textStyle: MqType.label,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.brand,
        foregroundColor: p.onBrand,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: buttonShape,
        textStyle: MqType.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.line),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: buttonShape,
        textStyle: MqType.label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.brand,
        textStyle: MqType.label,
        shape: buttonShape,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.brand,
      foregroundColor: p.onBrand,
      elevation: 4,
      extendedTextStyle: MqType.label,
      shape: const StadiumBorder(),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBackgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.line,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(MqSpace.radiusSheet)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: MqType.small.copyWith(color: p.bg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MqSpace.radiusButton),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.brand),
    listTileTheme: ListTileThemeData(iconColor: p.ink2, textColor: p.ink),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: p.brandSoft,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
