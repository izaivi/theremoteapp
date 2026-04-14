import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/revenuecat/revenuecat_client.dart';
import 'user_profile_repository.dart';

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
  SubscriptionController(this._ref) : super(const SubscriptionState()) {
    _init();
  }

  final Ref _ref;

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
    final premium = _hasPremium(info);
    if (premium == state.isPremium) return;
    state = state.copyWith(isPremium: premium);
    _syncTierToProfile(premium);
  }

  Future<void> _refreshCustomerInfo() async => refreshCustomerInfo();

  /// Passive refresh of the RevenueCat entitlement snapshot.
  ///
  /// Safe to call after sign-in to pick up entitlements the freshly-
  /// identified user already owns (e.g. purchased on another device).
  /// Unlike `restorePurchases`, this never prompts for a store password —
  /// it just asks the SDK for the latest cached CustomerInfo.
  Future<void> refreshCustomerInfo() async {
    if (!RevenueCatConfig.isConfigured) return;
    try {
      final info = await Purchases.getCustomerInfo();
      final premium = _hasPremium(info);
      if (premium == state.isPremium) return;
      state = state.copyWith(isPremium: premium);
      _syncTierToProfile(premium);
    } catch (_) {
      // Network error or SDK not ready — keep previous state.
    }
  }

  /// Mirror the RevenueCat entitlement state to the user profile so every
  /// gate in the UI (`isProProvider`, `profile.tier == 'pro'`, etc.) sees
  /// the change. This is the bridge that used to be missing: before this
  /// sync, a successful purchase would flash "Welcome" but every padlock
  /// stayed locked because the Supabase mirror never learned about it.
  void _syncTierToProfile(bool premium) {
    final tier = premium ? 'pro' : 'free';
    // `setTier` is idempotent AND fire-and-forgets the Supabase push, so
    // a slow network won't block the RevenueCat listener.
    _ref.read(userProfileProvider.notifier).setTier(tier);
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
      final changed = premium != state.isPremium;
      state = state.copyWith(isPremium: premium, isLoading: false);
      if (changed) _syncTierToProfile(premium);
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
      final changed = premium != state.isPremium;
      state = state.copyWith(isPremium: premium, isLoading: false);
      if (changed) _syncTierToProfile(premium);
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
  (ref) => SubscriptionController(ref),
);

/// Convenience — most call sites just need a bool.
final isPremiumProvider = Provider<bool>(
  (ref) => ref.watch(subscriptionProvider).isPremium,
);
