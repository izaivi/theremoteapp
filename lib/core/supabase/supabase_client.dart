import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase client bootstrap.
///
/// Call [initSupabase] exactly once from `main()` before `runApp()`. After
/// that, the global [Supabase.instance.client] is available everywhere.
///
/// The URL and anon key are pulled from `--dart-define` at build time so
/// we never commit secrets to git. To run locally:
///
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGc...
/// ```
///
/// For convenience during dev you can put those in a `.vscode/launch.json`
/// or an `.env` file you load with a runner script — just **never** hardcode
/// them in source.
///
/// The anon key is safe to ship in the client binary (it's scoped by RLS),
/// but we still prefer `--dart-define` so we can rotate without rebuilding
/// the app shell and so staging/prod keys don't cross-contaminate.
class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // ---- Sign in with Apple ------------------------------------------------
  // Services ID registered in developer.apple.com → used as the OAuth
  // `client_id` for the web/Supabase flow. Distinct from the iOS bundle ID.
  static const String appleServicesId = 'com.punkytigerlabs.theremote.signin';

  // ---- Google Sign In ----------------------------------------------------
  // iOS OAuth Client ID (Application type: iOS, Bundle: com.punkytigerlabs.theremote).
  // Used by the google_sign_in plugin to launch the native iOS flow.
  static const String googleIosClientId =
      '64121881188-t7oljdru0mpff5doo7evi0i9gdk6fu9p.apps.googleusercontent.com';

  // Web OAuth Client ID (Application type: Web). Supabase uses this as the
  // `audience` when validating Google ID tokens. Both must be added to the
  // Google provider in Supabase Auth → Providers (Web first, then iOS).
  static const String googleServerClientId =
      '64121881188-rudqv1t4a857lvkmjcv9durdlfo5rbop.apps.googleusercontent.com';

  /// True if both values were provided at build time. When false, the app
  /// runs in "offline-only" mode using SharedPreferences — exactly the
  /// state of the world before Fase 0. This lets Vivi keep developing
  /// without Supabase credentials and lets us gracefully degrade if a
  /// build is shipped without the `--dart-define`s (better than crashing
  /// on launch).
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

/// Initialize Supabase. Safe to call when [SupabaseConfig.isConfigured]
/// is false — it just logs and returns, and the rest of the app falls
/// back to local-only storage.
Future<void> initSupabase() async {
  if (!SupabaseConfig.isConfigured) {
    // ignore: avoid_print
    print('[supabase] skipped init — no SUPABASE_URL/ANON_KEY provided, '
        'running in local-only mode');
    return;
  }
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    // Debug logs only in debug builds; never in release.
    debug: false,
  );
}

/// Shorthand accessor. Use sparingly — most code should go through the
/// repository layer, not talk to Supabase directly.
SupabaseClient get supabase => Supabase.instance.client;
