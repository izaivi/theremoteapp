import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

/// Paywall stub — se muestra como modal bottom sheet cuando un free user
/// intenta acceder a una función Pro (5 Gems bloqueada, Quick Take,
/// filtros avanzados, etc.).
///
/// Por ahora es puramente visual: el botón "Upgrade" cierra el sheet sin
/// cobrar nada. Cuando se integre StoreKit / RevenueCat, el onPressed
/// dispara la compra real.
void showPaywall(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _PaywallContent(),
  );
}

class _PaywallContent extends StatelessWidget {
  const _PaywallContent();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final features = [
      (Icons.auto_awesome, l10n.paywallFeatureGems),
      (Icons.chat_bubble_outline, l10n.paywallFeatureChat),
      (Icons.tune, l10n.paywallFeatureFilters),
      (Icons.rocket_launch_outlined, l10n.paywallFeatureExploding),
      (Icons.edit_outlined, l10n.paywallFeatureQuickTake),
      (Icons.block, l10n.paywallFeatureNoAds),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.paywallTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.paywallSubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            for (final f in features) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(f.$1, size: 20, color: AppColors.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f.$2,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppColors.accent,
              ),
              child: Text(
                l10n.paywallCta,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.paywallLater),
            ),
          ],
        ),
      ),
    );
  }
}
