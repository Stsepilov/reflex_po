import 'package:flutter/material.dart';

class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final LinearGradient backgroundGradient;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final Color cardColor;
  final Color textPrimaryColor;
  final Color textSecondaryColor;
  final Color chartLineColor;
  final Color progressBarColor;

  AppThemeExtension({
    required this.backgroundGradient,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.cardColor,
    required this.textPrimaryColor,
    required this.textSecondaryColor,
    required this.chartLineColor,
    required this.progressBarColor,
  });

  @override
  AppThemeExtension copyWith({
    LinearGradient? backgroundGradient,
    Color? primaryColor,
    Color? secondaryColor,
    Color? accentColor,
    Color? cardColor,
    Color? textPrimaryColor,
    Color? textSecondaryColor,
    Color? chartLineColor,
    Color? progressBarColor,
  }) {
    return AppThemeExtension(
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      accentColor: accentColor ?? this.accentColor,
      cardColor: cardColor ?? this.cardColor,
      textPrimaryColor: textPrimaryColor ?? this.textPrimaryColor,
      textSecondaryColor: textSecondaryColor ?? this.textSecondaryColor,
      chartLineColor: chartLineColor ?? this.chartLineColor,
      progressBarColor: progressBarColor ?? this.progressBarColor,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    return AppThemeExtension(
      backgroundGradient: backgroundGradient,
      primaryColor: Color.lerp(primaryColor, other.primaryColor, t)!,
      secondaryColor: Color.lerp(secondaryColor, other.secondaryColor, t)!,
      accentColor: Color.lerp(accentColor, other.accentColor, t)!,
      cardColor: Color.lerp(cardColor, other.cardColor, t)!,
      textPrimaryColor: Color.lerp(textPrimaryColor, other.textPrimaryColor, t)!,
      textSecondaryColor: Color.lerp(textSecondaryColor, other.textSecondaryColor, t)!,
      chartLineColor: Color.lerp(chartLineColor, other.chartLineColor, t)!,
      progressBarColor: Color.lerp(progressBarColor, other.progressBarColor, t)!,
    );
  }
}
