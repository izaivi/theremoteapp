import 'dart:io' show Platform;
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat bootstrap.
///
/// Call [initRevenueCat] once from `main()`, after `WidgetsFlutterBinding`
/// but before `runApp()`. The API keys are provided via `--dart-define`:
///
/// ```
/// flutter run \
///   --dart-define=RC_APPLE_KEY=appl_xxx \
///   --dart-define=RC_GOOGLE_KEY=goog_xxx
/// ```
///
/// In test/sandbox mode you can use the test key from RevenueCat dashboard
/// (`test_MwkJBNlZMasBhvTRxNysQGjEQcf`). For production, generate separate
/// public Apple/Google keys from Apps & providers → API keys.
class RevenueCatConfig {
  static const String appleKey =
      String.fromEnvironment('RC_APPLE_KEY');
  static const String googleKey =
      String.fromEnvironment('RC_GOOGLE_KEY');

  /// The entitlement identifier configured in RevenueCat dashboard.
  /// Users who have this entitlement active are "Premium".
  static const String premiumEntitlement = 'Flixscope Pro';

  static bool get isConfigured {
    if (Platform.isIOS || Platform.isMacOS) return appleKey.isNotEmpty;
    if (Platform.isAndroid) return googleKey.isNotEmpty;
    return false;
  }

  static String get activeKey {
    if (Platform.isIOS || Platform.isMacOS) return appleKey;
    if (Platform.isAndroid) return googleKey;
    throw UnsupportedError('RevenueCat: unsupported platform');
  }
}

/// Initialize RevenueCat SDK. Safe to call when [RevenueCatConfig.isConfigured]
/// is false — it logs and returns, and the app runs in free-only mode.
Future<void> initRevenueCat() async {
  if (!RevenueCatConfig.isConfigured) {
    // ignore: avoid_print
    print('[revenuecat] skipped init — no RC_APPLE_KEY/RC_GOOGLE_KEY provided, '
        'running in free-only mode');
    return;
  }

  await Purchases.setLogLevel(LogLevel.debug);

  final config = PurchasesConfiguration(RevenueCatConfig.activeKey);
  await Purchases.configure(config);
}

/// Identify the RevenueCat user with our Supabase user ID so purchases
/// are tied to the account, not the device.
Future<void> identifyRevenueCatUser(String userId) async {
  if (!RevenueCatConfig.isConfigured) return;
  await Purchases.logIn(userId);
}

/// Reset RevenueCat to anonymous user (on sign-out).
Future<void> resetRevenueCatUser() async {
  if (!RevenueCatConfig.isConfigured) return;
  await Purchases.logOut();
}
