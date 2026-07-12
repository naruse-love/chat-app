import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFE94560),
        surface: Color(0xFF1A1A2E),
        surfaceContainerHighest: Color(0xFF1F2E54),
        onPrimary: Colors.white,
        onSurface: Color(0xFFF1F5F9),
      ),
      scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      cardColor: const Color(0xFF16213E),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF16213E),
        elevation: 0,
        centerTitle: true,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF2196F3),
        surface: Color(0xFFFFFFFF),
        surfaceContainerHighest: Color(0xFFECEFF1),
        onPrimary: Colors.white,
        onSurface: Colors.black87,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      cardColor: const Color(0xFFFFFFFF),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}
