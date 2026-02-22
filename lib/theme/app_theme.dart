import 'package:flutter/material.dart';

enum AppTheme { system, light, dark }

/// Defines key color palettes per brightness, embedded in ThemeData.
@immutable
class KeyColorExtension extends ThemeExtension<KeyColorExtension> {
  final List<Color> keyColors;
  const KeyColorExtension({required this.keyColors});

  @override
  KeyColorExtension copyWith({List<Color>? keyColors}) =>
      KeyColorExtension(keyColors: keyColors ?? this.keyColors);

  @override
  KeyColorExtension lerp(KeyColorExtension? other, double t) => this;
}

abstract class AppThemeManager {
  static const List<Color> _darkKeyColors = [
    Color(0xFFE53935), // red 600
    Color(0xFF43A047), // green 600
    Color(0xFF1E88E5), // blue 600
    Color(0xFFFFB300), // amber 600
    Color(0xFF00ACC1), // cyan 600
    Color(0xFF8E24AA), // purple 600
    Color(0xFFFB8C00), // orange 600
    Color(0xFF7CB342), // lightGreen 600
    Color(0xFF00897B), // teal 600
    Color(0xFF3949AB), // indigo 600
    Color(0xFF5E35B1), // deepPurple 600
    Color(0xFFD81B60), // pink 600
    Color(0xFFFF7043), // deepOrange 400
    Color(0xFFFDD835), // yellow 700
    Color(0xFFC0CA33), // lime 700
    Color(0xFF2E7D32), // green 800
    Color(0xFF26A69A), // teal 400
    Color(0xFF00838F), // cyan 800
    Color(0xFF1565C0), // blue 800
    Color(0xFF29B6F6), // lightBlue 400
    Color(0xFF9FA8DA), // indigo 300
    Color(0xFFCE93D8), // purple 300
    Color(0xFFF48FB1), // pink 300
    Color(0xFFE57373), // red 300
  ];

  // Deeper shades for better contrast on light backgrounds
  static const List<Color> _lightKeyColors = [
    Color(0xFFB71C1C), // red 900
    Color(0xFF1B5E20), // green 900
    Color(0xFF0D47A1), // blue 900
    Color(0xFFFF6F00), // amber 900
    Color(0xFF006064), // cyan 900
    Color(0xFF4A148C), // purple 900
    Color(0xFFE65100), // deepOrange 900
    Color(0xFF558B2F), // lightGreen 800
    Color(0xFF004D40), // teal 900
    Color(0xFF1A237E), // indigo 900
    Color(0xFF311B92), // deepPurple 900
    Color(0xFF880E4F), // pink 900
    Color(0xFFBF360C), // deepOrange 900
    Color(0xFFF9A825), // yellow 800
    Color(0xFF827717), // lime 900
    Color(0xFF1B5E20), // green 900
    Color(0xFF00695C), // teal 800
    Color(0xFF00626A), // cyan 900 alt
    Color(0xFF0D47A1), // blue 900
    Color(0xFF0277BD), // lightBlue 800
    Color(0xFF3949AB), // indigo 600
    Color(0xFF6A1B9A), // purple 900
    Color(0xFFC2185B), // pink 700
    Color(0xFFC62828), // red 800
  ];

  static ThemeData getLightThemeData() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.orange,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    extensions: [KeyColorExtension(keyColors: _lightKeyColors)],
  );

  static ThemeData getDarkThemeData() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.orange,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    extensions: [KeyColorExtension(keyColors: _darkKeyColors)],
  );

  static ThemeMode getThemeMode(AppTheme theme) => switch (theme) {
    AppTheme.light  => ThemeMode.light,
    AppTheme.dark   => ThemeMode.dark,
    AppTheme.system => ThemeMode.system,
  };
}
