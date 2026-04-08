import 'package:flutter/material.dart';

/// Design tokens — sacados de ProductDoc v1.1 sec. 5 + sec. 11.
/// Dark mode por defecto, feel iOS sobre Material 3.
class AppColors {
  AppColors._();

  // Backgrounds
  static const Color background = Color(0xFF0A0A1A);
  static const Color surface = Color(0xFF1A1A2E);
  static const Color surfaceElevated = Color(0xFF222238);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0C0);
  static const Color textMuted = Color(0xFF6A6A80);

  // Accent (primary action)
  static const Color accent = Color(0xFF7C4DFF);

  // Watcher Score ranges
  static const Color scoreExceptional = Color(0xFF00E676); // 90-100 verde
  static const Color scoreGood = Color(0xFFFFD600); // 75-89 amarillo
  static const Color scoreMixed = Color(0xFFFF9100); // 60-74 naranja
  static const Color scoreQuestionable = Color(0xFFFF1744); // <60 rojo

  static Color forScore(int score) {
    if (score >= 90) return scoreExceptional;
    if (score >= 75) return scoreGood;
    if (score >= 60) return scoreMixed;
    return scoreQuestionable;
  }

  // Streaming platforms
  static const Color netflix = Color(0xFFE50914);
  static const Color hboMax = Color(0xFF8B5CF6);
  static const Color disneyPlus = Color(0xFF1A73E8);
  static const Color primeVideo = Color(0xFF00A8E1);
  static const Color appleTvPlus = Color(0xFFA3A3A3);
  static const Color mubi = Color(0xFFE44D3A);

  // Special states
  static const Color exploding = Color(0xFFFF3D7F);
  static const Color trending = Color(0xFF00E5FF);
}
