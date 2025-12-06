import 'package:flutter/material.dart';

class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final LinearGradient backgroundGradient;

  AppThemeExtension({required this.backgroundGradient});

  @override
  AppThemeExtension copyWith({LinearGradient? backgroundGradient}) {
    return AppThemeExtension(
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    return this;
  }
}
