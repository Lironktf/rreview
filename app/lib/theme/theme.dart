import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTheme(Brightness brightness, {String? fontFamily}) {
  final c = brightness == Brightness.dark ? ReviewColors.dark : ReviewColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.danger,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.textPrimary,
    surfaceContainerHighest: c.surfaceSunken,
    onSurfaceVariant: c.textSecondary,
    outline: c.hairline,
    outlineVariant: c.hairline,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    splashFactory: InkSparkle.splashFactory,
  );
  // System font on every platform: Material's iOS typography maps to SF.
  final text = base.textTheme.apply(bodyColor: c.textPrimary, displayColor: c.textPrimary).copyWith(
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.textPrimary, letterSpacing: -0.2),
        titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary),
        bodyLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w400, color: c.textPrimary, height: 1.35),
        bodyMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: c.textPrimary, height: 1.35),
        bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: c.textSecondary, height: 1.3),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary),
        labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary),
        labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textSecondary, letterSpacing: 0),
      )
      .apply(fontFamily: fontFamily);
  return base.copyWith(
    extensions: [c],
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleMedium,
      toolbarHeight: 52,
    ),
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.medium)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.textSecondary,
      textColor: c.textPrimary,
      minVerticalPadding: 12,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.medium)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary,
        minimumSize: const Size(44, 44),
        side: BorderSide(color: c.hairline),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.medium)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        minimumSize: const Size(44, 44),
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.textPrimary, minimumSize: const Size(44, 44)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: c.surface,
        selectedForegroundColor: c.textPrimary,
        foregroundColor: c.textSecondary,
        backgroundColor: c.surfaceSunken,
        side: BorderSide(color: Colors.transparent),
        textStyle: text.labelMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.small)),
        visualDensity: VisualDensity.compact,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: text.bodyMedium?.copyWith(color: c.textTertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.medium), borderSide: BorderSide(color: c.hairline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.medium), borderSide: BorderSide(color: c.hairline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.medium), borderSide: BorderSide(color: c.accent, width: 1.5)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.textPrimary,
      contentTextStyle: text.bodyMedium?.copyWith(color: c.background),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.medium)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.background,
      showDragHandle: true,
      dragHandleColor: c.hairline,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onAccent : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : null),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
    cupertinoOverrideTheme: CupertinoThemeData(brightness: brightness, primaryColor: c.accent),
  );
}

/// Whether motion should be reduced. Flutter does not map iOS Reduce Motion to
/// MediaQuery.disableAnimations, so both signals are consulted.
bool reduceMotion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations ||
    WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.reduceMotion;

Duration motion(BuildContext context, Duration d) => reduceMotion(context) ? Duration.zero : d;
