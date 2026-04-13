import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/user_profile.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../presentation/screens/auth/auth_screen.dart';
import '../../presentation/screens/chat/chat_screen.dart';
import '../../presentation/screens/content/content_screen.dart';
import '../../presentation/screens/creators/creator_detail_screen.dart';
import '../../presentation/screens/creators/creators_screen.dart';
import '../../presentation/screens/discover/discover_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/long_quiz/long_quiz_screen.dart';
import '../../presentation/screens/onboarding/onboarding_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/splash/splash_screen.dart';
import '../../presentation/screens/vault/vault_screen.dart';
import '../../presentation/widgets/main_scaffold.dart';

/// Router as a Riverpod provider so redirects can react to profile changes.
///
/// Redirect rules:
///   - If the user has NOT completed the Fast Quiz → force `/onboarding`.
///   - If they have and are sitting on `/onboarding` → push them to `/home`.
final appRouterProvider = Provider<GoRouter>((ref) {
  // Mirror profile state into a plain Listenable that GoRouter can subscribe
  // to for refresh notifications.
  final refresh = ValueNotifier<int>(0);
  ref.listen<UserProfile>(
    userProfileProvider,
    (_, __) => refresh.value++,
    fireImmediately: false,
  );

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    errorBuilder: (context, state) => _RouterErrorScreen(error: state.error),
    redirect: (context, state) {
      final profile = ref.read(userProfileProvider);
      final loc = state.matchedLocation;
      final fullLoc = state.uri.toString();
      final atOnboarding = loc == '/onboarding';
      final atSplash = loc == '/splash';
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
      // the user to /home — by then the session is already live.
      if (loc.contains('login-callback') ||
          fullLoc.contains('login-callback')) {
        return '/home';
      }

      // Splash is always allowed — it's the welcome gate.
      if (atSplash) return null;
      if (!done && !atOnboarding) return '/onboarding';
      if (done && atOnboarding) return '/home';
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
      ),
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthScreen(),
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
