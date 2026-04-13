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

    // When the auth state flips to "signed in" (any provider, including
    // anonymous), pull all 4 user-owned datasets from Supabase and merge
    // them into local state. The push direction is handled fire-and-forget
    // by each controller mutation method.
    ref.listen(authStateChangesProvider, (prev, next) {
      next.whenData((state) async {
        if (state.event == AuthChangeEvent.signedIn) {
          // Switch user context for the per-account datasets (vault, ratings,
          // follows) — these MUST wipe-then-pull to avoid leaking rows across
          // accounts. We deliberately DO NOT reset the profile: doing so
          // would flip quizCompletion to `none`, which causes the router's
          // profile listener to briefly redirect to /onboarding and then
          // back to /home, manifesting as a black/flashing Home on login.
          // It would also nuke any alias the user set locally before a push
          // round-tripped to Supabase, leading to data loss on subsequent
          // sign-ins. refreshFromRemote handles the profile switch safely.

          // Identify RevenueCat user so purchases are tied to the Supabase
          // account, not the device. Must happen before any purchase calls.
          final uid = state.session?.user.id;
          if (uid != null) await identifyRevenueCatUser(uid);

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
