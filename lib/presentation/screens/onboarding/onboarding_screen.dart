import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/prefs/language_prefs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/repositories/catalog_provider.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../l10n/app_localizations.dart';

/// Fast Quiz onboarding — 3 mandatory steps before the user can see Home.
///
/// Step 1: Country (auto-detected, confirmable, from P1 + P2 launch list).
/// Step 2: Active streaming platforms (min 1 — assert enforced in model).
/// Step 3: Favorite genres (min 3).
///
/// Total target: ≤60 seconds. Long Quiz is promptable later from Profile.
///
/// The decisions here (country, platforms, genres) are persisted via
/// `UserProfileController.completeFastQuiz`, which triggers a router
/// redirect from `/onboarding` to `/home`.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  // Selections
  String? _country;
  final Set<String> _platforms = {};
  final Set<String> _genres = {};

  // Ordered by streaming market size + geographic grouping (North America,
  // LATAM, Europe). Source: Digital TV Research 2024 + Statista SVOD reports.
  static const _countryCodes = [
    'US',
    'CA',
    'MX',
    'BR',
    'AR',
    'CO',
    'CL',
    'ES',
    'GB',
    'IE',
    'FR',
    'DE',
    'IT',
    'NL',
    'PT',
    'SE',
    'XX', // Rest of the world — falls back to system country or 'US' in effectiveCountryProvider.
  ];

  static const _platformOptions = [
    'Netflix',
    'Disney+',
    'HBO/Max',
    'Apple TV+',
    'Prime Video',
    'Crunchyroll',
    'Paramount+',
    'Peacock',
    'MUBI',
  ];

  // (raw catalog value, arb key)
  static const _genreOptions = <(String, String)>[
    ('Drama', 'drama'),
    ('Comedy', 'comedy'),
    ('Thriller', 'thriller'),
    ('Sci-Fi', 'scifi'),
    ('Romance', 'romance'),
    ('Action', 'action'),
    ('Horror', 'horror'),
    ('Documentary', 'documentary'),
    ('Animation', 'animation'),
    ('Anime', 'anime'),
    ('Crime', 'crime'),
    ('History', 'history'),
    ('Mystery', 'mystery'),
  ];

  /// Retake mode: true when the user entered via
  /// Settings → "Change my preferences" (URL has `?retake=1`). In that
  /// case the screen pre-fills with the current profile values and, on
  /// finish, invalidates taste-dependent providers + returns to /settings
  /// instead of /home. Normal first-time onboarding is retake == false.
  bool _retake = false;

  @override
  void initState() {
    super.initState();
    // Seed country + retake pre-fill from the live profile.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final retake =
          GoRouterState.of(context).uri.queryParameters['retake'] == '1';
      final profile = ref.read(userProfileProvider);
      final detected = ref.read(effectiveCountryProvider);

      setState(() {
        _retake = retake;

        // Country: if retake and profile has a stored country, honour it;
        // otherwise fall back to detected (normal onboarding).
        if (retake && profile.country != null &&
            _countryCodes.contains(profile.country)) {
          _country = profile.country;
        } else if (_countryCodes.contains(detected)) {
          _country = detected;
        } else {
          _country = 'US';
        }

        // Retake: pre-populate platforms + genres from the profile so
        // the user tweaks instead of re-entering from scratch.
        if (retake) {
          _platforms
            ..clear()
            ..addAll(
              profile.activePlatforms.where(_platformOptions.contains),
            );
          final genreKeys = _genreOptions.map((e) => e.$2).toSet();
          _genres
            ..clear()
            ..addAll(profile.favoriteGenres.where(genreKeys.contains));
        }
      });
    });
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  bool get _canAdvance {
    switch (_index) {
      case 0:
        return _country != null;
      case 1:
        return _platforms.isNotEmpty;
      case 2:
        return _genres.length >= 3;
      default:
        return false;
    }
  }

  Future<void> _next() async {
    if (_index < 2) {
      setState(() => _index++);
      _page.animateToPage(_index,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic);
      return;
    }
    // Finish — persist quiz answers. `completeFastQuiz` is idempotent and
    // upgrade-only on quizCompletion, so a retake from a Long-completed
    // user stays at Long (see user_profile_repository.dart).
    await ref.read(userProfileProvider.notifier).completeFastQuiz(
          country: _country!,
          activePlatforms: _platforms.toList(),
          favoriteGenres: _genres.toList(),
        );

    if (!mounted) return;

    if (_retake) {
      // Refresh Home rows immediately so the user sees the effect of
      // the new platforms/genres without waiting for the next daily seed.
      invalidateTasteRows(ref);
      final messenger = ScaffoldMessenger.of(context);
      context.go('/settings');
      // Defer SnackBar one frame so the Settings scaffold is mounted
      // before we try to attach to its ScaffoldMessenger.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Preferences updated'),
            duration: Duration(seconds: 2),
          ),
        );
      });
      return;
    }

    // First-time onboarding: Auth already happened before the quiz
    // (Splash → Auth → Quiz → Home), so the session is live by the
    // time we land here. Go straight home.
    context.go('/home');
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index--);
    _page.animateToPage(_index,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.onboardingWelcome,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    l10n.onboardingStepOf(_index + 1, 3),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.onboardingWelcomeSub,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (_index + 1) / 3,
                minHeight: 3,
                backgroundColor: AppColors.surface,
              ),
              const SizedBox(height: 20),

              Expanded(
                child: PageView(
                  controller: _page,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _CountryStep(
                      selected: _country,
                      codes: _countryCodes,
                      onSelect: (c) => setState(() => _country = c),
                    ),
                    _PlatformStep(
                      options: _platformOptions,
                      selected: _platforms,
                      onToggle: (p) => setState(() {
                        _platforms.contains(p)
                            ? _platforms.remove(p)
                            : _platforms.add(p);
                      }),
                    ),
                    _GenresStep(
                      options: _genreOptions,
                      selected: _genres,
                      onToggle: (g) => setState(() {
                        _genres.contains(g)
                            ? _genres.remove(g)
                            : _genres.add(g);
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_index > 0)
                    TextButton(
                      onPressed: _back,
                      child: Text(l10n.onboardingBack),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _canAdvance ? _next : null,
                    child: Text(_index < 2
                        ? l10n.onboardingNext
                        : l10n.onboardingFinish),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Steps
// ---------------------------------------------------------------------------

class _StepShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _StepShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Expanded(child: child),
      ],
    );
  }
}

class _CountryStep extends StatelessWidget {
  final String? selected;
  final List<String> codes;
  final ValueChanged<String> onSelect;
  const _CountryStep({
    required this.selected,
    required this.codes,
    required this.onSelect,
  });

  String _label(AppLocalizations l10n, String code) {
    switch (code) {
      case 'US':
        return l10n.countryUs;
      case 'MX':
        return l10n.countryMx;
      case 'ES':
        return l10n.countryEs;
      case 'AR':
        return l10n.countryAr;
      case 'CO':
        return l10n.countryCo;
      case 'CL':
        return l10n.countryCl;
      case 'GB':
        return l10n.countryUk;
      case 'CA':
        return l10n.countryCa;
      case 'BR':
        return l10n.countryBr;
      case 'IE':
        return l10n.countryIe;
      case 'FR':
        return l10n.countryFr;
      case 'DE':
        return l10n.countryDe;
      case 'IT':
        return l10n.countryIt;
      case 'NL':
        return l10n.countryNl;
      case 'PT':
        return l10n.countryPt;
      case 'SE':
        return l10n.countrySe;
      case 'XX':
        return l10n.countryOther;
      default:
        return code;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _StepShell(
      title: l10n.onboardingStep1Title,
      subtitle: l10n.onboardingStep1Sub,
      child: ListView.separated(
        itemCount: codes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final c = codes[i];
          final isSel = c == selected;
          return InkWell(
            onTap: () => onSelect(c),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSel ? AppColors.accent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _label(l10n, c),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  if (isSel)
                    const Icon(Icons.check_circle,
                        color: AppColors.accent, size: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlatformStep extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _PlatformStep({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _StepShell(
      title: l10n.onboardingStep2Title,
      subtitle: l10n.onboardingStep2Sub,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.onboardingPlatformsHint,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in options)
                    _ChoiceChip(
                      label: p,
                      selected: selected.contains(p),
                      onTap: () => onToggle(p),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GenresStep extends StatelessWidget {
  final List<(String, String)> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _GenresStep({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  String _label(AppLocalizations l10n, String key) {
    switch (key) {
      case 'drama':
        return l10n.genreDrama;
      case 'comedy':
        return l10n.genreComedy;
      case 'thriller':
        return l10n.genreThriller;
      case 'scifi':
        return l10n.genreSciFi;
      case 'romance':
        return l10n.genreRomance;
      case 'action':
        return l10n.genreAction;
      case 'horror':
        return l10n.genreHorror;
      case 'documentary':
        return l10n.genreDocumentary;
      case 'animation':
        return l10n.genreAnimation;
      case 'anime':
        return l10n.genreAnime;
      case 'crime':
        return l10n.genreCrime;
      case 'history':
        return l10n.genreHistory;
      case 'mystery':
        return l10n.genreMystery;
      default:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _StepShell(
      title: l10n.onboardingStep3Title,
      subtitle: l10n.onboardingStep3Sub,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.onboardingGenresHint,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (rawValue, labelKey) in options)
                    _ChoiceChip(
                      label: _label(l10n, labelKey),
                      selected: selected.contains(rawValue),
                      onTap: () => onToggle(rawValue),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.textMuted,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
