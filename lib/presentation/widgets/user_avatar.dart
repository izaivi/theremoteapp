import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Reusable user avatar that decodes [UserProfile.avatarKey] encoding:
///   - null               → initials bubble (deterministic color from seed)
///   - `default:1..5`     → bundled asset `assets/avatars/avatar_N.png`
///   - `file:/abs/path`   → on-device uploaded image
///
/// [seed] is used to derive initials + a stable background color when no
/// avatar image is set. Typically the user's alias (or a fallback string).
class UserAvatar extends StatelessWidget {
  final String? avatarKey;
  final String seed;
  final double size;
  final bool withBorder;

  const UserAvatar({
    super.key,
    required this.avatarKey,
    required this.seed,
    this.size = 44,
    this.withBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final border = withBorder
        ? Border.all(color: AppColors.accent.withOpacity(0.6), width: 1.5)
        : null;

    Widget child;

    if (avatarKey == null) {
      child = _InitialsBubble(seed: seed, size: size);
    } else if (avatarKey!.startsWith('default:')) {
      final n = avatarKey!.substring('default:'.length);
      child = Image.asset(
        'assets/avatars/avatar_$n.png',
        fit: BoxFit.cover,
        // If asset missing (user hasn't bundled the 5 PNGs yet), degrade
        // gracefully to initials rather than a broken image box.
        errorBuilder: (_, __, ___) => _InitialsBubble(seed: seed, size: size),
      );
    } else if (avatarKey!.startsWith('file:')) {
      final path = avatarKey!.substring('file:'.length);
      child = Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _InitialsBubble(seed: seed, size: size),
      );
    } else {
      child = _InitialsBubble(seed: seed, size: size);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: border),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _InitialsBubble extends StatelessWidget {
  final String seed;
  final double size;
  const _InitialsBubble({required this.seed, required this.size});

  String _initials(String s) {
    final clean = s.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'[\s_@.-]+'));
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Color _colorFromSeed(String s) {
    // Stable hue from seed hash → HSL for pleasant dark-theme backgrounds.
    var hash = 0;
    for (final code in s.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.55, 0.42).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final bg = _colorFromSeed(seed);
    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Text(
        _initials(seed),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
