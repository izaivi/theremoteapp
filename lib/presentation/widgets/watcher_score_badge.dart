import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

class WatcherScoreBadge extends StatelessWidget {
  final int score;
  final double size;
  const WatcherScoreBadge({super.key, required this.score, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forScore(score);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: Border.all(color: color, width: 3),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$score',
        style: AppTheme.scoreNumber.copyWith(
          fontSize: size * 0.4,
          color: color,
        ),
      ),
    );
  }
}
