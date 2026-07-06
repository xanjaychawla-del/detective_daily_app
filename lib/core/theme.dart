import 'package:flutter/material.dart';

const Color kSurfaceBackground = Color(0xFF141414);
const Color kSurfaceCard = Color(0xFF1E1E1E);
const Color kAccentBlue = Color(0xFF4E8CFF);
const Color kAccentAmber = Color(0xFFE8A33D);
const Color kPillCream = Color(0xFFF3E9D2);

ThemeData buildDetectiveDailyTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: kAccentBlue,
    brightness: Brightness.dark,
  ).copyWith(
    surface: kSurfaceBackground,
    surfaceContainerHighest: kSurfaceCard,
    primary: kAccentBlue,
    secondary: kAccentAmber,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: kSurfaceBackground,
    cardTheme: const CardThemeData(
      color: kSurfaceCard,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kSurfaceBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurfaceCard,
      indicatorColor: kAccentBlue.withValues(alpha: 0.25),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.bold : FontWeight.normal,
          color: states.contains(WidgetState.selected) ? kAccentBlue : Colors.white70,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Colors.white24),
    textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
  );
}
