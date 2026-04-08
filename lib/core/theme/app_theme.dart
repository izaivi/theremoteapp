import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Material 3 con feel iOS:
///  - transiciones tipo Cupertino
///  - sin íconos Material visibles donde se pueda evitar
///  - tipografía SF-like
class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.background,
        surfaceContainer: AppColors.surface,
        primary: AppColors.accent,
        onPrimary: Colors.white,
        secondary: AppColors.trending,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
        fontFamily: '.SF Pro Text',
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
    );
  }

  /// Tipografía monospace para scores (ProductDoc sec. 5).
  static const TextStyle scoreNumber = TextStyle(
    fontFamily: 'SF Mono',
    fontWeight: FontWeight.w800,
    fontSize: 28,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );
}
