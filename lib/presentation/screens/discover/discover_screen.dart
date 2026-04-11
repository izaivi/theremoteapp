import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/content.dart';
import '../../../data/repositories/catalog_provider.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/paywall_sheet.dart';
import '../../widgets/watcher_score_badge.dart';

/// Discover — exploración con búsqueda y filtros.
///
/// Dos estados de layout:
///   - **Idle** (sin query, sin filtros activos): secciones verticales con
///     carousels horizontales (estilo lista, reusa el feel de Home pero con
///     otros ejes: Popular en tu región, Joyas escondidas, <90min, bingeable
///     de fin de semana).
///   - **Active** (búsqueda o filtro activo): grid 2 columnas con todos los
///     resultados que matchean, card con poster + Watcher Score flotante.
///
/// Filtros Free: género, plataforma, tipo, duración, min Watcher Score.
/// Filtros Premium: drop-off, trust, consenso, rango de años, otras regiones
/// (bloqueados con 🔒, tap → paywall).
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Free filters
  final Set<String> _genres = {};
  final Set<String> _platforms = {};
  ContentType? _type;
  _DurationBucket? _duration;
  int _minScore = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _query.isNotEmpty ||
      _genres.isNotEmpty ||
      _platforms.isNotEmpty ||
      _type != null ||
      _duration != null ||
      _minScore > 0;

  List<Content> _applyFilters(List<Content> source) {
    return source.where((c) {
      if (_query.isNotEmpty &&
          !c.title.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      if (_genres.isNotEmpty &&
          !c.genres.any((g) => _genres.contains(g))) {
        return false;
      }
      if (_platforms.isNotEmpty &&
          !c.availablePlatforms.any((p) => _platforms.contains(p))) {
        return false;
      }
      if (_type != null && c.type != _type) return false;
      if (_duration != null) {
        final m = c.durationMinutes;
        switch (_duration!) {
          case _DurationBucket.short:
            if (m >= 90) return false;
            break;
          case _DurationBucket.medium:
            if (m < 90 || m > 150) return false;
            break;
          case _DurationBucket.long:
            if (m <= 150) return false;
            break;
        }
      }
      if (c.watcherScore < _minScore) return false;
      return true;
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _searchCtrl.clear();
      _query = '';
      _genres.clear();
      _platforms.clear();
      _type = null;
      _duration = null;
      _minScore = 0;
    });
  }

  void _openFilters() {
    final profile = ref.read(userProfileProvider);
    final isPro = profile.tier == 'pro';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FiltersSheet(
        isPro: isPro,
        initialGenres: _genres,
        initialPlatforms: _platforms,
        initialType: _type,
        initialDuration: _duration,
        initialMinScore: _minScore,
        onApply: (g, p, t, d, s) {
          setState(() {
            _genres
              ..clear()
              ..addAll(g);
            _platforms
              ..clear()
              ..addAll(p);
            _type = t;
            _duration = d;
            _minScore = s;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profile = ref.watch(userProfileProvider);
    final showLongQuizBanner =
        !_hasActiveFilters && profile.quizCompletion != QuizCompletion.long;
    return SafeArea(
      child: Column(
        children: [
          // --- Search bar + filter button ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: l10n.discoverSearchHint,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _FilterIconButton(
                  active: _hasActiveFilters,
                  onTap: _openFilters,
                ),
              ],
            ),
          ),
          // --- Active filters bar ---
          if (_hasActiveFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.discoverResultsCount(
                          _applyFilters(ref.watch(catalogProvider).valueOrNull ?? []).length),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearFilters,
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(l10n.discoverClearFilters),
                  ),
                ],
              ),
            ),
          // --- Long quiz banner (idle + fast-only) ---
          if (showLongQuizBanner)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _LongQuizBanner(),
            ),
          // --- Content area ---
          Expanded(
            child: ref.watch(catalogProvider).when(
              data: (catalog) => _hasActiveFilters
                  ? _ResultsGrid(items: _applyFilters(catalog))
                  : _IdleSections(l10n: l10n, catalog: catalog),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DurationBucket { short, medium, long }

// ---------------------------------------------------------------------------
// Idle state — vertical sections with horizontal carousels
// ---------------------------------------------------------------------------

class _IdleSections extends StatelessWidget {
  final AppLocalizations l10n;
  final List<Content> catalog;
  const _IdleSections({required this.l10n, required this.catalog});

  @override
  Widget build(BuildContext context) {
    // Reuse the catalog for different "lenses".
    final popular = catalog
        .where((c) => c.availablePlatforms.isNotEmpty)
        .take(20)
        .toList();
    // "Under the radar" = pool NAVEGABLE de joyas de bajo ruido.
    final underRadar = catalog
        .where((c) => c.imdbScore != null && c.imdbScore! >= 7.0)
        .skip(20)
        .take(15)
        .toList();
    final under90 = catalog
        .where((c) => c.type == ContentType.movie && c.durationMinutes > 0 && c.durationMinutes < 90)
        .take(15)
        .toList();
    final bingeable = catalog
        .where((c) => c.type == ContentType.series)
        .take(15)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
      children: [
        _Carousel(title: l10n.discoverSectionPopularRegion, items: popular),
        _Carousel(title: l10n.discoverSectionUnderRadar, items: underRadar),
        _Carousel(title: l10n.discoverSectionUnder90, items: under90),
        _Carousel(title: l10n.discoverSectionBingeable, items: bingeable),
      ],
    );
  }
}

class _Carousel extends StatelessWidget {
  final String title;
  final List<Content> items;
  const _Carousel({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
        ),
        SizedBox(
          height: 252,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _PosterCard(content: items[i], width: 130),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Active state — 2-column grid of poster cards
// ---------------------------------------------------------------------------

class _ResultsGrid extends StatelessWidget {
  final List<Content> items;
  const _ResultsGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/mascots/mascot_search.png',
                width: 140,
                height: 140,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.search_off,
                  size: 48,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.discoverEmpty,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.56,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _PosterCard(content: items[i], width: null),
    );
  }
}

// ---------------------------------------------------------------------------
// Poster card — used in both idle carousels and results grid
// ---------------------------------------------------------------------------

class _PosterCard extends StatelessWidget {
  final Content content;
  final double? width;
  const _PosterCard({required this.content, required this.width});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/content/${content.id}'),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: content.posterUrl.isEmpty
                          ? Container(color: AppColors.surface)
                          : Image.network(
                              content.posterUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  color: AppColors.surface,
                                  child: const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.surface,
                                child: const Icon(Icons.movie_outlined,
                                    color: AppColors.textMuted, size: 32),
                              ),
                            ),
                    ),
                  ),
                  // Gradient for title legibility at bottom
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                          stops: const [0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Watcher Score badge top-right
                  Positioned(
                    top: 8,
                    right: 8,
                    child: WatcherScoreBadge(
                      score: content.watcherScore,
                      size: 36,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              content.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            Text(
              content.genres.take(2).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter icon button with active dot indicator
// ---------------------------------------------------------------------------

class _FilterIconButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _FilterIconButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: active
              ? Border.all(color: AppColors.accent, width: 1.5)
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.tune, size: 20),
            if (active)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters bottom sheet
// ---------------------------------------------------------------------------

class _FiltersSheet extends StatefulWidget {
  final bool isPro;
  final Set<String> initialGenres;
  final Set<String> initialPlatforms;
  final ContentType? initialType;
  final _DurationBucket? initialDuration;
  final int initialMinScore;
  final void Function(
    Set<String> genres,
    Set<String> platforms,
    ContentType? type,
    _DurationBucket? duration,
    int minScore,
  ) onApply;

  const _FiltersSheet({
    required this.isPro,
    required this.initialGenres,
    required this.initialPlatforms,
    required this.initialType,
    required this.initialDuration,
    required this.initialMinScore,
    required this.onApply,
  });

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late Set<String> _genres;
  late Set<String> _platforms;
  late ContentType? _type;
  late _DurationBucket? _duration;
  late int _minScore;

  @override
  void initState() {
    super.initState();
    _genres = {...widget.initialGenres};
    _platforms = {...widget.initialPlatforms};
    _type = widget.initialType;
    _duration = widget.initialDuration;
    _minScore = widget.initialMinScore;
  }

  static const _allGenres = [
    'Drama',
    'Comedy',
    'Thriller',
    'Sci-Fi',
    'Romance',
    'Action',
    'Horror',
    'Documentary',
    'Animation',
    'Crime',
    'History',
    'Mystery',
  ];
  static const _allPlatforms = [
    'Netflix',
    'Disney+',
    'HBO/Max',
    'Apple TV+',
    'Prime Video',
    'Crunchyroll',
    'Paramount+',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  l10n.discoverFilters,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _genres.clear();
                      _platforms.clear();
                      _type = null;
                      _duration = null;
                      _minScore = 0;
                    });
                  },
                  child: Text(l10n.discoverClearFilters),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                _FilterGroup(
                  title: l10n.filterGroupGenre,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final g in _allGenres)
                        _Chip(
                          label: g,
                          selected: _genres.contains(g),
                          onTap: () => setState(() {
                            _genres.contains(g)
                                ? _genres.remove(g)
                                : _genres.add(g);
                          }),
                        ),
                    ],
                  ),
                ),
                _FilterGroup(
                  title: l10n.filterGroupPlatform,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _allPlatforms)
                        _Chip(
                          label: p,
                          selected: _platforms.contains(p),
                          onTap: () => setState(() {
                            _platforms.contains(p)
                                ? _platforms.remove(p)
                                : _platforms.add(p);
                          }),
                        ),
                    ],
                  ),
                ),
                _FilterGroup(
                  title: l10n.filterGroupType,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      _Chip(
                        label: l10n.filterTypeMovie,
                        selected: _type == ContentType.movie,
                        onTap: () => setState(() => _type =
                            _type == ContentType.movie
                                ? null
                                : ContentType.movie),
                      ),
                      _Chip(
                        label: l10n.filterTypeSeries,
                        selected: _type == ContentType.series,
                        onTap: () => setState(() => _type =
                            _type == ContentType.series
                                ? null
                                : ContentType.series),
                      ),
                    ],
                  ),
                ),
                _FilterGroup(
                  title: l10n.filterGroupDuration,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      _Chip(
                        label: l10n.filterDurationShort,
                        selected: _duration == _DurationBucket.short,
                        onTap: () => setState(() => _duration =
                            _duration == _DurationBucket.short
                                ? null
                                : _DurationBucket.short),
                      ),
                      _Chip(
                        label: l10n.filterDurationMedium,
                        selected: _duration == _DurationBucket.medium,
                        onTap: () => setState(() => _duration =
                            _duration == _DurationBucket.medium
                                ? null
                                : _DurationBucket.medium),
                      ),
                      _Chip(
                        label: l10n.filterDurationLong,
                        selected: _duration == _DurationBucket.long,
                        onTap: () => setState(() => _duration =
                            _duration == _DurationBucket.long
                                ? null
                                : _DurationBucket.long),
                      ),
                    ],
                  ),
                ),
                _FilterGroup(
                  title: '${l10n.filterGroupMinScore}: $_minScore',
                  child: Slider(
                    value: _minScore.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '$_minScore',
                    onChanged: (v) => setState(() => _minScore = v.round()),
                  ),
                ),
                _FilterGroup(
                  title: l10n.filterGroupAdvanced,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _LockedChip(
                          label: l10n.filterAdvancedDropoff,
                          isPro: widget.isPro),
                      _LockedChip(
                          label: l10n.filterAdvancedTrust,
                          isPro: widget.isPro),
                      _LockedChip(
                          label: l10n.filterAdvancedConsensus,
                          isPro: widget.isPro),
                      _LockedChip(
                          label: l10n.filterAdvancedYearRange,
                          isPro: widget.isPro),
                      _LockedChip(
                          label: l10n.filterAdvancedOtherRegions,
                          isPro: widget.isPro),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () {
                  widget.onApply(
                      _genres, _platforms, _type, _duration, _minScore);
                  Navigator.pop(context);
                },
                child: Text(
                  l10n.discoverFilters,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  final String title;
  final Widget child;
  const _FilterGroup({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.accent
                : AppColors.textMuted.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _LockedChip extends StatelessWidget {
  final String label;
  final bool isPro;
  const _LockedChip({required this.label, required this.isPro});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        if (isPro) return; // pro user could use it — no-op for stub
        showPaywall(context);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 13, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Long quiz banner (idle state, fast-only users)
// ---------------------------------------------------------------------------

class _LongQuizBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => context.push('/long-quiz'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.accent.withOpacity(0.28),
              const Color(0xFF4F8CFF).withOpacity(0.18),
            ],
          ),
          border: Border.all(color: AppColors.accent.withOpacity(0.55)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.22),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent),
              ),
              child: const Icon(Icons.tune,
                  color: AppColors.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.discoverLongQuizBanner,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.discoverLongQuizBannerSub,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_rounded,
                color: AppColors.accent, size: 20),
          ],
        ),
      ),
    );
  }
}
