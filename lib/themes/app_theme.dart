import 'package:flutter/material.dart';
import 'package:reflex_po/themes/theme_extensions.dart';

ThemeData appTheme() {
  return ThemeData(
    extensions: [
      AppThemeExtension(
        backgroundGradient: const LinearGradient(
          colors: [
            Color(0xFF800F38),
            Color(0xFF810C27),
            Color(0xFF6A0D25),
            Color(0xFF570B22),
            Color(0xFF3D0A1F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomLeft,
        ),
      ),
    ],
  );
}

TextStyle mainTextStyle() {
  return const TextStyle(
    fontFamily: 'SF Pro Display',
    fontWeight: FontWeight.w400,
    fontSize: 42,
    color: Colors.white,
  );
}
