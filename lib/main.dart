import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/prefs/language_prefs.dart';
import 'core/router/app_router.dart';
import 'core/revenuecat/revenuecat_client.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/follows_repository.dart';
import 'data/repositories/quick_takes_provider.dart';
import 'data/repositories/ratings_repository.dart';
import 'data/repositories/subscription_repository.dart';
import 'data/repositories/user_profile_repository.dart';
import 'data/repositories/vault_repository.dart';
import 'l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Supabase before the app mounts. If no credentials were
  // provided via --dart-define, this is a no-op and the app runs in
  // local-only mode (SharedPreferences fallback).
  await initSupabase();

  // Initialize RevenueCat for in-app purchases. Same graceful fallback:
  // no RC_APPLE_KEY/RC_GOOGLE_KEY → free-only mode (no paywall).
  await initRevenueCat();

  runApp(const ProviderScope(child: TheRemoteApp()));
}

class TheRemoteApp extends ConsumerWidget {
  const TheRemoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(uiLocaleProvider);
    final router = ref.watch(appRouterProvider);

    // Force-instantiate the SubscriptionController so the RevenueCat
    // CustomerInfo listener registers at boot. Without this read, nothing
    // else in the app watches `subscriptionProvider`, so the controller
    // would never initialize, the entitlement stream would never fire, and
    // `profiles.tier` would never sync from RevenueCat → Supabase. That
    // was the root cause of "paywall greets me but every padlock stays
    // locked" in Build 12. StateNotifierProvider is keepAlive by default,
    // so a single read is enough to keep it around.
    ref.read(subscriptionProvider);

    // When the auth state flips to "signed in" (any provider, including
    // anonymous), pull all 4 user-owned datasets from Supabase and merge
    // them into local state. The push direction is handled fire-and-forget
    // by each controller mutation method.
    ref.listen(authStateChangesProvider, (prev, next) {
      next.whenData((state) async {
        if (state.event == AuthChangeEvent.signedIn) {
          // Switch user context for the per-account datasets (vault, ratings,
          // follows) — these MUST wipe-then-pull to avoid leaking rows across
          // accounts.
          //
          // Profile reset rule (Build 15, "Rayo McQueen" fix):
          //   reset the local profile ONLY when the incoming session's user
          //   id differs from the one already cached locally. That's the
          //   real "user switch" case (including anonymous → real, real A
          //   → real B, or a fresh install re-signing in). For a token
          //   refresh or a re-emit of the same session, ids match and we
          //   skip the reset — which is what the old "never reset" comment
          //   was actually trying to protect against (black/flashing Home
          //   because quizCompletion briefly flipped to `none` during the
          //   pre-`refreshFromRemote` window).
          //
          // Without this reset, SharedPreferences kept the previous user's
          // `quizCompletion = fast/long`, and combined with the old
          // asymmetric merge in refreshFromRemote (local wins when remote
          // is `none`), a brand-new account got shoved straight to /home,
          // skipping the quiz and leaving 5 Gems empty.
          //
          // Identify RevenueCat user so purchases are tied to the Supabase
          // account, not the device. Must happen before any purchase calls.
          final uid = state.session?.user.id;
          if (uid != null) await identifyRevenueCatUser(uid);

          final currentProfileId = ref.read(userProfileProvider).id;
          if (currentProfileId != uid) {
            await ref.read(userProfileProvider.notifier).reset();
          }

          await ref.read(ratingsProvider.notifier).clearLocal();
          await ref.read(vaultProvider.notifier).clear();
          await ref.read(followsProvider.notifier).clearLocal();
          // Nuke any cached FutureProvider.family results that keyed by the
          // OLD user's id (quick takes "my vote" state, today-count, etc.).
          // Without this, the previous user's thumbs-up state bleeds into
          // the new session until the screen is cold-rebuilt.
          ref.invalidate(quickTakesByContentProvider);
          ref.invalidate(quickTakesTodayCountProvider);
          await ref.read(userProfileProvider.notifier).refreshFromRemote();
          await ref.read(ratingsProvider.notifier).refreshFromRemote();
          await ref.read(vaultProvider.notifier).refreshFromRemote();
          await ref.read(followsProvider.notifier).refreshFromRemote();
          // After identify + profile pull, ask RevenueCat for the fresh
          // entitlement snapshot tied to THIS Supabase user. Covers:
          //   - Returning users who purchased on another device.
          //   - Users whose entitlement renewed/expired while signed out.
          // Passive refresh — no store password prompt.
          await ref.read(subscriptionProvider.notifier).refreshCustomerInfo();
        } else if (state.event == AuthChangeEvent.tokenRefreshed ||
            state.event == AuthChangeEvent.userUpdated) {
          ref.read(userProfileProvider.notifier).refreshFromRemote();
          ref.read(ratingsProvider.notifier).refreshFromRemote();
          ref.read(vaultProvider.notifier).refreshFromRemote();
          ref.read(followsProvider.notifier).refreshFromRemote();
        } else if (state.event == AuthChangeEvent.signedOut) {
          // Reset RevenueCat to anonymous — detaches purchases from the
          // previous account so the next sign-in starts clean.
          await resetRevenueCatUser();

          await ref.read(userProfileProvider.notifier).reset();
          await ref.read(ratingsProvider.notifier).clearLocal();
          await ref.read(vaultProvider.notifier).clear();
          await ref.read(followsProvider.notifier).clearLocal();
          ref.invalidate(quickTakesByContentProvider);
          ref.invalidate(quickTakesTodayCountProvider);
        }
      });
    });

    return MaterialApp.router(
      title: 'Flixscope',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: router,

      // i18n — only EN and ES are supported.
      // Resolution rules live in `uiLocaleProvider`:
      //   1. User override from Profile → Settings wins.
      //   2. Else device locale: es-* → ES, anything else → EN.
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
