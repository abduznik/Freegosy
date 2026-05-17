import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shared_prefs_provider.dart';

enum ThemePreset {
  darkDefault,
  light,
  muscular,
  feminine,
  neonCyan,
  oledBlack,
}

extension ThemePresetExtension on ThemePreset {
  String get displayName {
    switch (this) {
      case ThemePreset.darkDefault:
        return 'Default (Dark)';
      case ThemePreset.light:
        return 'Light Mode';
      case ThemePreset.muscular:
        return 'Muscular (Crimson)';
      case ThemePreset.feminine:
        return 'Feminine (Rose/Gold)';
      case ThemePreset.neonCyan:
        return 'Neon Cyan';
      case ThemePreset.oledBlack:
        return 'OLED Pitch Black';
    }
  }
}

class ThemeNotifier extends StateNotifier<ThemePreset> {
  final SharedPreferences prefs;
  static const _key = 'theme_preset';

  ThemeNotifier(this.prefs) : super(_loadTheme(prefs));

  static ThemePreset _loadTheme(SharedPreferences prefs) {
    final name = prefs.getString(_key);
    if (name != null) {
      return ThemePreset.values.firstWhere(
        (e) => e.name == name,
        orElse: () => ThemePreset.darkDefault,
      );
    }
    return ThemePreset.darkDefault;
  }

  void setTheme(ThemePreset preset) {
    state = preset;
    prefs.setString(_key, preset.name);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemePreset>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeNotifier(prefs);
});

ThemeData getThemeData(ThemePreset preset) {
  switch (preset) {
    case ThemePreset.light:
      return ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
          surface: const Color(0xFFF0F0F0),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        cardTheme: const CardThemeData(color: Color(0xFFF8F8F8), elevation: 2),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFFF8F8F8),
          indicatorColor: Colors.deepPurple.withValues(alpha: 0.2),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8F8F8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.deepPurple.shade300)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.deepPurple.shade200)),
        ),
      );
      
    case ThemePreset.muscular:
      return ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
          surface: const Color(0xFF1a0000),
        ),
        scaffoldBackgroundColor: const Color(0xFF0a0000),
        cardTheme: const CardThemeData(color: Color(0xFF1a0000), elevation: 2),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0a0000),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF1a0000),
          indicatorColor: Colors.redAccent.withValues(alpha: 0.3),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1a0000),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.red.shade800)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.red.shade900)),
        ),
      );

    case ThemePreset.feminine:
      return ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pinkAccent,
          brightness: Brightness.dark,
          surface: const Color(0xFF2a111a),
        ),
        scaffoldBackgroundColor: const Color(0xFF1c0a11),
        cardTheme: const CardThemeData(color: Color(0xFF2a111a), elevation: 2),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1c0a11),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF2a111a),
          indicatorColor: Colors.pinkAccent.withValues(alpha: 0.3),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2a111a),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.pink.shade800)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.pink.shade900)),
        ),
      );

    case ThemePreset.neonCyan:
      return ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyanAccent,
          brightness: Brightness.dark,
          surface: const Color(0xFF001a1a),
        ),
        scaffoldBackgroundColor: const Color(0xFF000d0d),
        cardTheme: const CardThemeData(color: Color(0xFF001a1a), elevation: 2),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF000d0d),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF001a1a),
          indicatorColor: Colors.cyanAccent.withValues(alpha: 0.3),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF001a1a),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.cyan.shade800)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.cyan.shade900)),
        ),
      );

    case ThemePreset.oledBlack:
      return ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey,
          brightness: Brightness.dark,
          surface: const Color(0xFF000000),
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        cardTheme: const CardThemeData(color: Color(0xFF050505), elevation: 2),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF000000),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF050505),
          indicatorColor: Colors.grey.shade800,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF000000),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade800)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade900)),
        ),
      );

    case ThemePreset.darkDefault:
      return ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
          surface: const Color(0xFF1a1a1a),
        ),
        scaffoldBackgroundColor: const Color(0xFF0f0f0f),
        cardTheme: const CardThemeData(color: Color(0xFF1a1a1a), elevation: 2),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0f0f0f),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF1a1a1a),
          indicatorColor: Colors.deepPurple.withValues(alpha: 0.3),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1a1a1a),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.deepPurple.shade800)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.deepPurple.shade900)),
        ),
      );
  }
}
