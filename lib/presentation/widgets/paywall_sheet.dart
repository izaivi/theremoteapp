import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/revenuecat/revenuecat_client.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

/// Paywall — se muestra como modal bottom sheet cuando un free user
/// intenta acceder a una función Pro (5 Gems bloqueada, Quick Take,
/// filtros avanzados, etc.).
///
/// Connects to RevenueCat to display real offerings and trigger the
/// native purchase flow. Falls back to a stub if RC is not configured
/// (dev/test builds without --dart-define keys).
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

class _PaywallContent extends StatefulWidget {
  const _PaywallContent();

  @override
  State<_PaywallContent> createState() => _PaywallContentState();
}

class _PaywallContentState extends State<_PaywallContent> {
  Offering? _offering;
  bool _loading = true;
  bool _purchasing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOffering();
  }

  Future<void> _loadOffering() async {
    if (!RevenueCatConfig.isConfigured) {
      setState(() {
        _loading = false;
        _error = null; // just show stub
      });
      return;
    }

    try {
      final offerings = await Purchases.getOfferings();
      setState(() {
        _offering = offerings.current;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _purchase(Package package) async {
    if (_purchasing) return;
    setState(() => _purchasing = true);

    try {
      final result = await Purchases.purchasePackage(package);
      // Check if the user now has the premium entitlement.
      final isPro = result.entitlements.all[RevenueCatConfig.premiumEntitlement]
              ?.isActive ??
          false;
      if (isPro && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Welcome to Flixscope Premium! 🎬'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } on PurchasesErrorCode catch (_) {
      // User cancelled or billing issue — stay on the paywall, no error.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final features = [
      (Icons.smart_toy_outlined, l10n.paywallFeatureChat),
      (Icons.tune, l10n.paywallFeatureFilters),
      (Icons.rocket_launch_outlined, l10n.paywallFeatureExploding),
      (Icons.diamond_outlined, l10n.paywallFeatureGems),
      (Icons.bar_chart_outlined, l10n.paywallFeatureStats),
      (Icons.bookmark_outline, l10n.paywallFeatureWatchlist),
      (Icons.edit_outlined, l10n.paywallFeatureQuickTake),
    ];

    return SafeArea(
      child: SingleChildScrollView(
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
            const SizedBox(height: 16),
            Center(
              child: Image.asset(
                'assets/mascots/mascot_premium.png',
                width: 120,
                height: 120,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 12),
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

            // ── Purchase buttons (from RevenueCat offerings) ──
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_offering != null) ...[
              // Show available packages (monthly, annual, etc.)
              for (final pkg in _offering!.availablePackages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PackageButton(
                    package: pkg,
                    purchasing: _purchasing,
                    onTap: () => _purchase(pkg),
                  ),
                ),
            ] else ...[
              // Fallback: RC not configured or no offerings loaded.
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
            ],

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!.length > 120
                      ? '${_error!.substring(0, 120)}…'
                      : _error!,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.red.shade300,
                    fontSize: 12,
                  ),
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

/// Individual package button showing price and period.
class _PackageButton extends StatelessWidget {
  final Package package;
  final bool purchasing;
  final VoidCallback onTap;

  const _PackageButton({
    required this.package,
    required this.purchasing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final product = package.storeProduct;
    final isAnnual = package.packageType == PackageType.annual;

    return FilledButton(
      onPressed: purchasing ? null : onTap,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        backgroundColor: isAnnual ? AppColors.accent : AppColors.accent.withOpacity(0.7),
      ),
      child: purchasing
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Column(
              children: [
                Text(
                  isAnnual ? 'Annual — Best Value' : 'Monthly',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.priceString,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
              ],
            ),
    );
  }
}
