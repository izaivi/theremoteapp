import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/mock/mock_content.dart';
import '../../../data/mock/mock_creators.dart';
import '../../../data/models/content.dart';
import '../../../data/models/creator.dart';
import '../../../data/repositories/catalog_provider.dart';
import '../../../data/repositories/follows_repository.dart';
import '../../../data/repositories/ratings_repository.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../data/repositories/vault_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/watcher_score_badge.dart';

/// Vault — "Mi Bóveda". The user's personal library.
///
/// 5 tabs with distinct semantic sources (Vivi 2026-04-10 split):
///   1. Loved       — VaultState.loved (explicit ❤️ taps, independent from stars)
///   2. Ranking     — RatingsRepo all, grouped by star count
///   3. Watchlist   — VaultState.watchlist (🔖 saves)
///   4. Not for me  — VaultState.notForMe (explicit dismiss on content detail)
///   5. Following   — FollowsRepository (creators)
///
/// Header shows the user's avatar prominently — "seeing yourself" is a
/// strong ownership cue.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vault = ref.watch(vaultProvider);
    final follows = ref.watch(followsProvider);
    final ratings = ref.watch(ratingsProvider);
    final profile = ref.watch(userProfileProvider);

    // Build a lookup map from the real catalog (Supabase data).
    final catalog = ref.watch(catalogProvider).valueOrNull ?? [];
    final catalogMap = <String, Content>{
      for (final c in catalog) c.id: c,
    };

    // Loved = explicit ❤️ taps (vault.loved).
    // Independent from star ratings — 5★ means quality, ❤️ means personal fave.
    final loved = _resolveContent(vault.loved, catalogMap);
    final watchlist = _resolveContent(vault.watchlist, catalogMap);
    final notForMe = _resolveContent(vault.notForMe, catalogMap);
    final followedCreators = follows
        .map((id) => MockCreators.byId(id))
        .whereType<Creator>()
        .toList();
    final rankedCount = ratings.length;

    return SafeArea(
      child: Column(
        children: [
          // Header with avatar right
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.vaultTitle,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.alias != null && profile.alias!.isNotEmpty
                            ? 'Tu biblioteca personal, @${profile.alias}'
                            : l10n.vaultSubtitle,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => context.push('/settings'),
                  borderRadius: BorderRadius.circular(40),
                  child: UserAvatar(
                    avatarKey: profile.avatarKey,
                    seed: profile.alias ?? l10n.vaultTitle,
                    size: 72,
                    withBorder: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Tabs (scrollable to fit 5)
          TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: [
              Tab(text: '❤️ ${l10n.vaultTabLoved} (${loved.length})'),
              Tab(text: '⭐ ${l10n.vaultTabRanking} ($rankedCount)'),
              Tab(
                  text:
                      '🔖 ${l10n.vaultTabWatchlist} (${watchlist.length})'),
              Tab(text: '👎 ${l10n.vaultTabNotForMe} (${notForMe.length})'),
              Tab(
                  text:
                      '👥 ${l10n.vaultTabFollowing} (${followedCreators.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _ContentGrid(
                    items: loved,
                    emptyMsg: l10n.vaultEmptyLoved,
                    mascotName: 'loved'),
                _RankingView(
                    ratings: ratings,
                    catalogMap: catalogMap,
                    emptyMsg: l10n.vaultEmptyRanking,
                    mascotName: 'ranking'),
                _ContentGrid(
                    items: watchlist,
                    emptyMsg: l10n.vaultEmptyWatchlist,
                    mascotName: 'watchlist'),
                _ContentGrid(
                    items: notForMe,
                    emptyMsg: l10n.vaultEmptyNotForMe,
                    mascotName: 'notforme'),
                _FollowingList(
                    creators: followedCreators,
                    emptyMsg: l10n.vaultEmptyFollowing,
                    mascotName: 'following'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Resolve content IDs to Content objects using the real catalog first,
  /// falling back to MockContent for any old mock IDs still in local storage.
  List<Content> _resolveContent(
      Iterable<String> ids, Map<String, Content> catalogMap) {
    return ids
        .map((id) => catalogMap[id] ?? MockContent.byId(id))
        .whereType<Content>()
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Ranking view — titles grouped by star count, 5★ first down to 1★
// ---------------------------------------------------------------------------

class _RankingView extends StatelessWidget {
  final Map<String, int> ratings;
  final Map<String, Content> catalogMap;
  final String emptyMsg;
  final String mascotName;
  const _RankingView({
    required this.ratings,
    required this.catalogMap,
    required this.emptyMsg,
    required this.mascotName,
  });

  @override
  Widget build(BuildContext context) {
    if (ratings.isEmpty) {
      return _EmptyState(message: emptyMsg, mascotName: mascotName);
    }

    final grouped = <int, List<Content>>{};
    for (final e in ratings.entries) {
      final c = catalogMap[e.key] ?? MockContent.byId(e.key);
      if (c != null) grouped.putIfAbsent(e.value, () => []).add(c);
    }
    final starKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        for (final stars in starKeys) ...[
          _StarDivider(stars: stars, count: grouped[stars]!.length),
          const SizedBox(height: 10),
          for (final c in grouped[stars]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RankedCard(content: c, stars: stars),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Visual divider for each star group — colored bar + stars + count.
class _StarDivider extends StatelessWidget {
  final int stars;
  final int count;
  const _StarDivider({required this.stars, required this.count});

  @override
  Widget build(BuildContext context) {
    // Color gradient: 5★ = accent gold, 1★ = muted grey.
    final intensity = stars / 5.0;
    final barColor = Color.lerp(AppColors.textMuted, AppColors.accent, intensity)!;

    return Row(
      children: [
        Container(
          width: 3,
          height: 24,
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        for (var i = 0; i < 5; i++)
          Icon(
            i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 18,
            color: i < stars ? barColor : AppColors.textMuted.withOpacity(0.4),
          ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: TextStyle(
            color: barColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            color: barColor.withOpacity(0.2),
          ),
        ),
      ],
    );
  }
}

/// Horizontal card for a ranked title — poster + title + score + genres.
class _RankedCard extends StatelessWidget {
  final Content content;
  final int stars;
  const _RankedCard({required this.content, required this.stars});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/content/${content.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            // Poster
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 50,
                height: 75,
                child: content.posterUrl.isEmpty
                    ? Container(color: AppColors.surface)
                    : Image.network(
                        content.posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.surface,
                          child: const Icon(Icons.movie_outlined,
                              color: AppColors.textMuted, size: 20),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    content.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${content.year} · ${content.genres.take(2).join(" · ")}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Mini stars
                  Row(
                    children: [
                      for (var i = 0; i < 5; i++)
                        Icon(
                          i < stars
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 14,
                          color: i < stars
                              ? AppColors.accent
                              : AppColors.textMuted.withOpacity(0.4),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Watcher Score
            WatcherScoreBadge(score: content.watcherScore, size: 38),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Content poster grid (used for loved / watchlist / notForMe tabs)
// ---------------------------------------------------------------------------

class _ContentGrid extends StatelessWidget {
  final List<Content> items;
  final String emptyMsg;
  final String mascotName;
  const _ContentGrid({
    required this.items,
    required this.emptyMsg,
    required this.mascotName,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyState(message: emptyMsg, mascotName: mascotName);
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.58,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _PosterTile(content: items[i]),
    );
  }
}

class _PosterTile extends StatelessWidget {
  final Content content;
  const _PosterTile({required this.content});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/content/${content.id}'),
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: content.posterUrl.isEmpty
                        ? Container(color: AppColors.surface)
                        : Image.network(
                            content.posterUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.surface,
                              child: const Icon(Icons.movie_outlined,
                                  color: AppColors.textMuted),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: WatcherScoreBadge(
                      score: content.watcherScore, size: 30),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Following list (creators)
// ---------------------------------------------------------------------------

class _FollowingList extends StatelessWidget {
  final List<Creator> creators;
  final String emptyMsg;
  final String mascotName;
  const _FollowingList({
    required this.creators,
    required this.emptyMsg,
    required this.mascotName,
  });

  @override
  Widget build(BuildContext context) {
    if (creators.isEmpty) {
      return _EmptyState(message: emptyMsg, mascotName: mascotName);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: creators.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final c = creators[i];
        return InkWell(
          onTap: () => context.push('/creator/${c.id}'),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                _CreatorInitials(alias: c.alias),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            c.alias,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          if (c.isCurated) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                                size: 14, color: AppColors.accent),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.specialty,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white54),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CreatorInitials extends StatelessWidget {
  final String alias;
  const _CreatorInitials({required this.alias});
  @override
  Widget build(BuildContext context) {
    var hash = 0;
    for (final c in alias.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    final bg = HSLColor.fromAHSL(1.0, hue, 0.55, 0.45).toColor();
    final clean = alias.replaceAll('@', '');
    final letters = clean.isEmpty
        ? '?'
        : (clean.length >= 2
            ? clean.substring(0, 2).toUpperCase()
            : clean[0].toUpperCase());
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: Text(
        letters,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

/// Empty state for any Vault tab. Uses a named mascot illustration
/// (same art family as the app icon + default avatars) so each empty
/// tab has its own expression — loved = hearts in eyes, ranking =
/// thinking pose, not-for-me = drama queen rejecting, etc.
///
/// [mascotName] maps to `assets/mascots/mascot_<name>.png`. If the PNG
/// hasn't been dropped in yet, degrades to a neutral icon via
/// [Image.asset]'s errorBuilder — safe to ship before the art lands.
class _EmptyState extends StatelessWidget {
  final String message;
  final String mascotName;
  const _EmptyState({required this.message, required this.mascotName});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.9,
              child: Image.asset(
                'assets/mascots/mascot_$mascotName.png',
                width: 140,
                height: 140,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.bookmark_border,
                  size: 64,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
