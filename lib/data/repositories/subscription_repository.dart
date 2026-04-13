import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/revenuecat/revenuecat_client.dart';

/// Subscription state — tracks whether the user has the Premium entitlement.
///
/// The single source of truth is RevenueCat's [CustomerInfo]. We cache
/// the latest snapshot in a [StateNotifier] so the rest of the app can
/// just read `ref.watch(subscriptionProvider).isPremium` without calling
/// the SDK every frame.
///
/// When [RevenueCatConfig.isConfigured] is false (no API key), the app
/// runs in "free-only" mode: [isPremium] is always false and the paywall
/// screen can be hidden entirely.
class SubscriptionState {
  final bool isPremium;
  final bool isLoading;

  /// The active offering from RevenueCat (monthly, annual, lifetime packages).
  /// Null until [SubscriptionController.loadOfferings] completes or when
  /// RevenueCat is not configured.
  final Offerings? offerings;

  const SubscriptionState({
    this.isPremium = false,
    this.isLoading = false,
    this.offerings,
  });

  SubscriptionState copyWith({
    bool? isPremium,
    bool? isLoading,
    Offerings? offerings,
  }) =>
      SubscriptionState(
        isPremium: isPremium ?? this.isPremium,
        isLoading: isLoading ?? this.isLoading,
        offerings: offerings ?? this.offerings,
      );
}

class SubscriptionController extends StateNotifier<SubscriptionState> {
  SubscriptionController() : super(const SubscriptionState()) {
    _init();
  }

  // -----------------------------------------------------------------------
  // Init — listen to CustomerInfo changes from RevenueCat.
  // -----------------------------------------------------------------------

  void _init() {
    if (!RevenueCatConfig.isConfigured) return;

    // RevenueCat emits a CustomerInfo stream whenever entitlements change
    // (purchase, restore, expiration, billing issue, etc.).
    Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);

    // Fetch the current state right away so we don't start with isPremium=false
    // and then flicker to true a moment later.
    _refreshCustomerInfo();
  }

  void _onCustomerInfoUpdated(CustomerInfo info) {
    state = state.copyWith(
      isPremium: _hasPremium(info),
    );
  }

  Future<void> _refreshCustomerInfo() async {
    try {
      final info = await Purchases.getCustomerInfo();
      state = state.copyWith(isPremium: _hasPremium(info));
    } catch (_) {
      // Network error or SDK not ready — keep previous state.
    }
  }

  static bool _hasPremium(CustomerInfo info) {
    return info.entitlements.all[RevenueCatConfig.premiumEntitlement]?.isActive ??
        false;
  }

  // -----------------------------------------------------------------------
  // Offerings — load available packages for the paywall UI.
  // -----------------------------------------------------------------------

  /// Fetch the current offerings from RevenueCat. Call this when the paywall
  /// screen mounts; the result is cached in state so subsequent reads are free.
  Future<void> loadOfferings() async {
    if (!RevenueCatConfig.isConfigured) return;
    if (state.offerings != null) return; // already loaded

    state = state.copyWith(isLoading: true);
    try {
      final offerings = await Purchases.getOfferings();
      state = state.copyWith(offerings: offerings, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  // -----------------------------------------------------------------------
  // Purchase — trigger the native payment sheet.
  // -----------------------------------------------------------------------

  /// Purchase a specific [Package] (monthly, annual, or lifetime).
  /// Returns `true` if the purchase succeeded and the user is now premium.
  Future<bool> purchase(Package package) async {
    if (!RevenueCatConfig.isConfigured) return false;

    state = state.copyWith(isLoading: true);
    try {
      final result = await Purchases.purchasePackage(package);
      final premium = _hasPremium(result);
      state = state.copyWith(isPremium: premium, isLoading: false);
      return premium;
    } on PurchasesErrorCode catch (_) {
      // User cancelled or billing error — stay on the paywall.
      state = state.copyWith(isLoading: false);
      return false;
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // Restore — for users who reinstall or switch devices.
  // -----------------------------------------------------------------------

  /// Restore purchases. Returns `true` if the user now has premium.
  Future<bool> restorePurchases() async {
    if (!RevenueCatConfig.isConfigured) return false;

    state = state.copyWith(isLoading: true);
    try {
      final info = await Purchases.restorePurchases();
      final premium = _hasPremium(info);
      state = state.copyWith(isPremium: premium, isLoading: false);
      return premium;
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  @override
  void dispose() {
    // Remove the listener to avoid leaks.
    if (RevenueCatConfig.isConfigured) {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfoUpdated);
    }
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final subscriptionProvider =
    StateNotifierProvider<SubscriptionController, SubscriptionState>(
  (ref) => SubscriptionController(),
);

/// Convenience — most call sites just need a bool.
final isPremiumProvider = Provider<bool>(
  (ref) => ref.watch(subscriptionProvider).isPremium,
);
