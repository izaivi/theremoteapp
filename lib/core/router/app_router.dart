import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/user_profile.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../presentation/screens/chat/chat_screen.dart';
import '../../presentation/screens/content/content_screen.dart';
import '../../presentation/screens/creators/creator_detail_screen.dart';
import '../../presentation/screens/creators/creators_screen.dart';
import '../../presentation/screens/discover/discover_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/onboarding/onboarding_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/splash/splash_screen.dart';
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
    redirect: (context, state) {
      final profile = ref.read(userProfileProvider);
      final loc = state.matchedLocation;
      final atOnboarding = loc == '/onboarding';
      final atSplash = loc == '/splash';
      final done = profile.quizCompletion != QuizCompletion.none;

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
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(
              path: '/discover', builder: (_, __) => const DiscoverScreen()),
          GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
          GoRoute(
              path: '/creators', builder: (_, __) => const CreatorsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
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
    ],
  );
});
