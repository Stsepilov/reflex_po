import 'package:flutter/material.dart';
import 'package:reflex_po/themes/theme_extensions.dart';

ThemeData appTheme() {
  return ThemeData(
    scaffoldBackgroundColor: const Color(0xFFF5F5F7),
    extensions: [
      AppThemeExtension(
        backgroundGradient: const LinearGradient(
          colors: [
            Color(0xFFF5F5F7),
            Color(0xFFEFEFF4),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        primaryColor: const Color(0xFF5B4FD9),
        secondaryColor: const Color(0xFF9B8FE8),
        accentColor: const Color(0xFFFFB5A7),
        cardColor: const Color(0xFFFFFFFF),
        textPrimaryColor: const Color(0xFF1C1C1E),
        textSecondaryColor: const Color(0xFF8E8E93),
        chartLineColor: const Color(0xFF2E2E5F),
        progressBarColor: const Color(0xFF5B4FD9),
      ),
    ],
  );
}

TextStyle mainTextStyle() {
  return const TextStyle(
    fontFamily: 'SF Pro Display',
    fontWeight: FontWeight.w400,
    fontSize: 42,
    color: Color(0xFF1C1C1E),
  );
}
