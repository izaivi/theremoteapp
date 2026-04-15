import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/user_profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../presentation/screens/auth/auth_screen.dart';
import '../../presentation/screens/auth/otp_verify_screen.dart';
import '../../presentation/screens/chat/chat_screen.dart';
import '../../presentation/screens/content/content_screen.dart';
import '../../presentation/screens/creators/creator_detail_screen.dart';
import '../../presentation/screens/creators/creators_screen.dart';
import '../../presentation/screens/discover/discover_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/legal/legal_viewer_screen.dart';
import '../../presentation/screens/long_quiz/long_quiz_screen.dart';
import '../../presentation/screens/onboarding/onboarding_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/settings/blocked_creators_screen.dart';
import '../../presentation/screens/splash/splash_screen.dart';
import '../../presentation/screens/vault/vault_screen.dart';
import '../../presentation/widgets/main_scaffold.dart';

/// Router as a Riverpod provider so redirects can react to profile and
/// auth state changes.
///
/// Flow: **Splash → Auth → Quiz (Onboarding) → Home**
///
/// Redirect rules:
///   - `/splash` and `/auth` are always allowed (no gating).
///   - If the user is NOT signed in → force `/auth`.
///   - If signed in but quiz NOT done → force `/onboarding`.
///   - If quiz done and sitting on `/onboarding` → push to `/home`.
final appRouterProvider = Provider<GoRouter>((ref) {
  // Mirror profile + auth state into a plain Listenable that GoRouter can
  // subscribe to for refresh notifications. We re-evaluate redirects whenever
  // either changes — e.g. user signs in (auth state) or finishes the quiz
  // (profile state).
  final refresh = ValueNotifier<int>(0);
  ref.listen<UserProfile>(
    userProfileProvider,
    (_, __) => refresh.value++,
    fireImmediately: false,
  );
  ref.listen(
    authStateChangesProvider,
    (_, __) => refresh.value++,
    fireImmediately: false,
  );

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    errorBuilder: (context, state) => _RouterErrorScreen(error: state.error),
    redirect: (context, state) {
      final profile = ref.read(userProfileProvider);
      final user = ref.read(currentUserProvider);
      final loc = state.matchedLocation;
      final fullLoc = state.uri.toString();
      final atOnboarding = loc == '/onboarding';
      final atSplash = loc == '/splash';
      // `/auth` and any subpath like `/auth/otp` — all are pre-auth surfaces
      // that should NOT bounce the user back to /auth itself.
      final atAuth = loc == '/auth' || loc.startsWith('/auth/');
      final signedIn = user != null;
      final done = profile.quizCompletion != QuizCompletion.none;

      // Auth deep-link catch-all. When Supabase finishes an OAuth or Magic
      // Link flow it hands iOS a URL like
      //   io.theremote://login-callback/?code=<pkce>#
      // `supabase_flutter` intercepts that URL via its own deep-link handler
      // and closes the session behind the scenes. BUT the same URL also gets
      // delivered to the Flutter engine's route parser, which asks go_router
      // to match it — and since `login-callback` is not a declared route,
      // the errorBuilder kicks in ("Something went off the rails"). Swallow
      // it here: if we see any URL that smells like the auth callback, send
      // the user to /home — by then the session is already live, and the
      // redirect rules below will bounce them to /onboarding if the quiz
      // still needs doing.
      if (loc.contains('login-callback') ||
          fullLoc.contains('login-callback')) {
        return '/home';
      }

      // Welcome gate: show splash only to users without a live session.
      // If Supabase restored a session from secure storage (typical cold
      // start for returning users), skip the welcome screen entirely and
      // send them straight to the quiz or home. Without this, the app
      // always asks returning users to "sign in again" after a cold start
      // because the CTA on splash unconditionally goes to /auth.
      if (atSplash) {
        if (signedIn) return done ? '/home' : '/onboarding';
        return null;
      }
      // Auth screen is always reachable — it's the sign-in surface and
      // also handles re-auth from Settings for signed-in users.
      if (atAuth) return null;

      // Not signed in → must authenticate first. Splash and Auth are the
      // only pre-auth surfaces; everything else bounces here.
      if (!signedIn) return '/auth';

      // Signed in but quiz not done → quiz is mandatory before catalog.
      if (!done && !atOnboarding) return '/onboarding';

      // Quiz already done and somehow back on /onboarding → home,
      // UNLESS the user explicitly entered retake mode from Settings
      // (Fase 3 "Change my preferences"). The retake flag is a query
      // param on the URL so it survives deep-linking and doesn't need
      // global state. See Profile → "Taste profile" section.
      final isRetake = state.uri.queryParameters['retake'] == '1';
      if (done && atOnboarding && !isRetake) return '/home';

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, __) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/discover',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: DiscoverScreen()),
          ),
          GoRoute(
            path: '/chat',
            pageBuilder: (_, __) => const NoTransitionPage(child: ChatScreen()),
          ),
          GoRoute(
            path: '/creators',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: CreatorsScreen()),
          ),
          GoRoute(
            path: '/vault',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: VaultScreen()),
          ),
        ],
      ),
      // Settings lives outside the shell — pushed as a modal-ish route from
      // the Home header gear icon. Keeps the bottom nav focused on primary
      // content surfaces (Home · Discover · Vault · Creators · Chat).
      GoRoute(
        path: '/settings',
        builder: (_, __) => const ProfileScreen(),
        routes: [
          // Build 16 — Apple UGC compliance. Lists the user's blocked
          // creators with an Unblock action per row.
          GoRoute(
            path: 'blocked',
            builder: (_, __) => const BlockedCreatorsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthScreen(),
        routes: [
          // Magic Link OTP verification — pushed from /auth after the user
          // requests a code. Email is passed via `extra`.
          GoRoute(
            path: 'otp',
            builder: (_, state) {
              final email = state.extra is String ? state.extra as String : '';
              return OtpVerifyScreen(email: email);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/content/:id',
        builder: (_, state) =>
            ContentScreen(contentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/creator/:id',
        builder: (_, state) =>
            CreatorDetailScreen(creatorId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/long-quiz',
        builder: (_, __) => const LongQuizScreen(),
      ),
      // Legal — Build 16 / Apple UGC compliance. `/legal/:doc` where
      // :doc is 'terms' or 'guidelines'. Privacy is a direct URL launch
      // (no route, handled inline at the call-site).
      GoRoute(
        path: '/legal/:doc',
        builder: (context, state) {
          final doc = state.pathParameters['doc'];
          final l10n = AppLocalizations.of(context)!;
          switch (doc) {
            case 'terms':
              return LegalViewerScreen(
                assetPath: LegalDocs.termsAsset,
                title: l10n.legalTermsTitle,
                webUrl: LegalDocs.termsWebUrl,
              );
            case 'guidelines':
              return LegalViewerScreen(
                assetPath: LegalDocs.guidelinesAsset,
                title: l10n.legalGuidelinesTitle,
                webUrl: LegalDocs.guidelinesWebUrl,
              );
            default:
              return const _RouterErrorScreen();
          }
        },
      ),
    ],
  );
});

/// Fallback screen shown by GoRouter when a route doesn't exist or a
/// builder throws. Uses the confused mascot so even errors feel on-brand.
class _RouterErrorScreen extends StatelessWidget {
  final Exception? error;
  const _RouterErrorScreen({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/mascots/mascot_confused.png',
                  width: 160,
                  height: 160,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.error_outline,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Something went off the rails",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  error?.toString() ??
                      "We couldn't find what you were looking for.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
