import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/mock/mock_creators.dart';
import '../../../data/models/content.dart';
import '../../../data/models/creator.dart';
import '../../../data/repositories/catalog_provider.dart'; // contentByIdProvider
import '../../../data/repositories/creators_provider.dart';
import '../../../data/repositories/follows_repository.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../data/repositories/vault_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/paywall_sheet.dart';
import '../../widgets/user_avatar.dart';

/// Creators — trusted voices.
///
/// Layout (free total, no paywalls):
///   1. Header + tagline
///   2. Hero card: "NOT worth your time" (featured skipIt take)
///   3. Horizontal list of creators (avatar + alias + specialty)
///   4. Vertical feed of latest takes (worth it / quick take / skip it)
class CreatorsScreen extends ConsumerWidget {
  const CreatorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final creatorsAsync = ref.watch(creatorsProvider);
    final latestAsync = ref.watch(latestTakesProvider);
    final featuredSkipAsync = ref.watch(featuredSkipProvider);

    final creators = creatorsAsync.valueOrNull ?? MockCreators.creators;
    final latest = latestAsync.valueOrNull ?? [];
    final featuredSkip = featuredSkipAsync.valueOrNull;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.creatorsTitle,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.creatorsTagline,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                    ),
                  ],
                ),
              ),
              Image.asset(
                'assets/mascots/mascot_following.png',
                width: 64,
                height: 64,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ---- Featured skip card ----
          if (featuredSkip != null) _FeaturedSkipCard(take: featuredSkip),
          const SizedBox(height: 24),

          // ---- Creators carousel ----
          _SectionTitle(l10n.creatorsSectionAll),
          const SizedBox(height: 12),
          SizedBox(
            height: 138,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: creators.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) =>
                  _CreatorChip(creator: creators[i]),
            ),
          ),
          const SizedBox(height: 28),

          // ---- Latest takes feed ----
          _SectionTitle(l10n.creatorsSectionLatest),
          const SizedBox(height: 12),
          if (latest.isEmpty && latestAsync.isLoading)
            const Center(child: CircularProgressIndicator())
          else
            for (final take in latest)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TakeCard(take: take),
              ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      );
}

/// Colored-initials avatar (no network dependency for mock).
class _Avatar extends StatelessWidget {
  final String alias;
  final double size;
  const _Avatar({required this.alias, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final clean = alias.replaceAll('@', '');
    final initials = clean.isEmpty
        ? '?'
        : clean.length >= 2
            ? clean.substring(0, 2).toUpperCase()
            : clean.substring(0, 1).toUpperCase();

    // Deterministic color from alias hash.
    final hue = (clean.codeUnits.fold<int>(0, (a, b) => a + b) * 37) % 360;
    final bg = HSLColor.fromAHSL(1.0, hue.toDouble(), 0.55, 0.45).toColor();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Avatar that automatically shows the real profile photo when the creator
/// is the currently logged-in user, falling back to colored initials otherwise.
class _SmartAvatar extends StatelessWidget {
  final WidgetRef ref;
  final Creator creator;
  final double size;
  const _SmartAvatar({
    required this.ref,
    required this.creator,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final currentCreator = ref.watch(currentCreatorProvider).valueOrNull;
    final isMe = currentCreator?.id == creator.id;
    final profile = isMe ? ref.watch(userProfileProvider) : null;

    if (isMe && profile != null) {
      return UserAvatar(
        avatarKey: profile.avatarKey,
        seed: creator.alias,
        size: size,
        withBorder: false,
      );
    }
    return _Avatar(alias: creator.alias, size: size);
  }
}

// ---------------------------------------------------------------------------
// Featured skip card
// ---------------------------------------------------------------------------

class _FeaturedSkipCard extends ConsumerWidget {
  final CreatorTake take;
  const _FeaturedSkipCard({required this.take});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final contentAsync = ref.watch(contentByIdProvider(take.contentId));
    final content = contentAsync.valueOrNull;
    final creatorAsync = ref.watch(creatorByIdProvider(take.creatorId));
    final creator = creatorAsync.valueOrNull ?? MockCreators.byId(take.creatorId);
    if (content == null || creator == null) return const SizedBox.shrink();

    const danger = Color(0xFFE5484D);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            danger.withOpacity(0.22),
            Theme.of(context).colorScheme.surface,
          ],
        ),
        border: Border.all(color: danger.withOpacity(0.45), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.do_not_disturb_on_outlined,
                  color: danger, size: 18),
              const SizedBox(width: 6),
              Text(
                l10n.creatorsFeaturedSkip,
                style: const TextStyle(
                  color: danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster thumb
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 70,
                  height: 105,
                  child: _PosterThumb(url: content.posterUrl),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: danger.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${content.watcherScore}',
                            style: const TextStyle(
                                color: danger,
                                fontSize: 12,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${content.year}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      take.body,
                      style: const TextStyle(fontSize: 13, height: 1.35),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => context.push('/creator/${creator.id}'),
                      child: Row(
                        children: [
                          _SmartAvatar(ref: ref, creator: creator, size: 22),
                          const SizedBox(width: 6),
                          Text(
                            creator.alias,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          if (creator.isCurated) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                                size: 13, color: AppColors.accent),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TakeActions(content: content),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Creator chip (horizontal carousel)
// ---------------------------------------------------------------------------

class _CreatorChip extends ConsumerWidget {
  final Creator creator;
  const _CreatorChip({required this.creator});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFollowing = ref.watch(followsProvider).contains(creator.id);

    return GestureDetector(
      onTap: () => context.push('/creator/${creator.id}'),
      child: Container(
        width: 112,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFollowing
                ? AppColors.accent.withOpacity(0.6)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                _SmartAvatar(ref: ref, creator: creator, size: 52),
                if (creator.isCurated)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.verified,
                          size: 16, color: AppColors.accent),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              creator.alias,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              creator.specialty,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Take card (feed entry)
// ---------------------------------------------------------------------------

class _TakeCard extends ConsumerWidget {
  final CreatorTake take;
  const _TakeCard({required this.take});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Load content individually — the catalog is limited to 600 titles,
    // so takes for less-popular titles would silently disappear.
    final contentAsync = ref.watch(contentByIdProvider(take.contentId));
    final content = contentAsync.valueOrNull;
    final creatorAsync = ref.watch(creatorByIdProvider(take.creatorId));
    final creator = creatorAsync.valueOrNull ?? MockCreators.byId(take.creatorId);
    if (content == null) {
      if (contentAsync.isLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: SizedBox(
            height: 20, width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )),
        );
      }
      return const SizedBox.shrink();
    }
    if (creator == null) return const SizedBox.shrink();

    final verdictColor = switch (take.verdict) {
      CreatorVerdict.worthIt => AppColors.accent,
      CreatorVerdict.skipIt => const Color(0xFFE5484D),
    };
    final verdictLabel = switch (take.verdict) {
      CreatorVerdict.worthIt => l10n.creatorVerdictWorthIt,
      CreatorVerdict.skipIt => l10n.creatorVerdictSkipIt,
    };
    final verdictIcon = switch (take.verdict) {
      CreatorVerdict.worthIt => Icons.check_circle_outline,
      CreatorVerdict.skipIt => Icons.do_not_disturb_on_outlined,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Creator row
          GestureDetector(
            onTap: () => context.push('/creator/${creator.id}'),
            child: Row(
              children: [
                _SmartAvatar(ref: ref, creator: creator, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              creator.alias,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (creator.isCurated) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                                size: 13, color: AppColors.accent),
                          ],
                        ],
                      ),
                      Text(
                        creator.specialty,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: verdictColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: verdictColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(verdictIcon, size: 12, color: verdictColor),
                      const SizedBox(width: 4),
                      Text(
                        verdictLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: verdictColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Body
          Text(
            take.body,
            style: const TextStyle(fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          // Mini content info
          GestureDetector(
            onTap: () => context.push('/content/${content.id}'),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 40,
                      height: 60,
                      child: _PosterThumb(url: content.posterUrl),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          content.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${content.year} · ${content.genres.take(2).join(" · ")}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _WatcherChip(score: content.watcherScore),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _TakeActions(content: content),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions bar (▶ watch, ⭐ save, 👍 👎)
// ---------------------------------------------------------------------------

/// Local reaction state. Pre-auth this is in-memory only; survives while the
/// screen is alive. Keyed by content id so different takes about the same
/// title stay in sync visually.
/// Take actions — semantically split between "content signals" and
/// "take feedback", a distinction Vivi caught on 2026-04-08:
///
///   - **Save (🔖)** — content signal. Wired to [vaultProvider.watchlist]
///     because "save this title for later" is about the *movie*, not the
///     take. Surfaces under Vault → Watchlist.
///   - **👍 / 👎** — feedback on the creator's *review*, not on the movie.
///     ("Good call, creator" vs "I disagree with this take"). Kept as
///     ephemeral local UI state; will move to Supabase `take_reactions`
///     (user_id, take_id, reaction) when backend lands. NOT stored in vault.
///
/// The prior version wired thumbs to vault.loved / vault.notForMe, which
/// conflated "this take is helpful" with "I love this movie" — fixed.
enum _TakeReaction { none, up, down }

class _TakeActions extends ConsumerStatefulWidget {
  final Content content;
  const _TakeActions({required this.content});
  @override
  ConsumerState<_TakeActions> createState() => _TakeActionsState();
}

class _TakeActionsState extends ConsumerState<_TakeActions> {
  _TakeReaction _reaction = _TakeReaction.none;

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vault = ref.watch(vaultProvider);
    final ctrl = ref.read(vaultProvider.notifier);
    final saved = vault.isWatchlisted(widget.content.id);

    return Row(
      children: [
        _ActionBtn(
          icon: Icons.play_arrow_rounded,
          label: l10n.creatorActionWatch,
          onTap: () => context.push('/content/${widget.content.id}'),
        ),
        const SizedBox(width: 8),
        _ActionBtn(
          icon: saved ? Icons.bookmark : Icons.bookmark_border,
          label: l10n.creatorActionSave,
          active: saved,
          onTap: () async {
            final ok = await ctrl.toggleWatchlist(
              widget.content.id,
              isPro: ref.read(isProProvider),
            );
            if (!ok && context.mounted) {
              showPaywall(context);
              return;
            }
            if (!saved && context.mounted) {
              _snack(l10n.creatorTakeSaved);
            }
          },
        ),
        const SizedBox(width: 8),
        _ActionBtn(
          icon: _reaction == _TakeReaction.up
              ? Icons.thumb_up_alt
              : Icons.thumb_up_alt_outlined,
          active: _reaction == _TakeReaction.up,
          onTap: () {
            setState(() => _reaction = _reaction == _TakeReaction.up
                ? _TakeReaction.none
                : _TakeReaction.up);
            if (_reaction == _TakeReaction.up) {
              _snack(l10n.creatorTakeHelpfulRecorded);
            }
          },
        ),
        const SizedBox(width: 8),
        _ActionBtn(
          icon: _reaction == _TakeReaction.down
              ? Icons.thumb_down_alt
              : Icons.thumb_down_alt_outlined,
          active: _reaction == _TakeReaction.down,
          onTap: () {
            setState(() => _reaction = _reaction == _TakeReaction.down
                ? _TakeReaction.none
                : _TakeReaction.down);
            if (_reaction == _TakeReaction.down) {
              _snack(l10n.creatorTakeHelpfulRecorded);
            }
          },
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool active;
  const _ActionBtn({
    required this.icon,
    this.label,
    required this.onTap,
    this.active = false,
  });

  static const Color _blue = Color(0xFF4F8CFF);

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : _blue;
    final gradient = active
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _blue,
              _blue.withOpacity(0.75),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _blue.withOpacity(0.22),
              _blue.withOpacity(0.08),
            ],
          );

    return Expanded(
      flex: label != null ? 2 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? _blue : _blue.withOpacity(0.45),
            width: 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: _blue.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: fg),
                  if (label != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      label!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WatcherChip extends StatelessWidget {
  final int score;
  const _WatcherChip({required this.score});
  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? AppColors.accent
        : score >= 60
            ? Colors.amber
            : const Color(0xFFE5484D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        '$score',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _PosterThumb extends StatelessWidget {
  final String url;
  const _PosterThumb({required this.url});
  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        color: Colors.white.withOpacity(0.06),
        child: const Icon(Icons.movie_outlined, color: Colors.white38),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (c, child, p) =>
          p == null ? child : Container(color: Colors.white.withOpacity(0.05)),
      errorBuilder: (_, __, ___) => Container(
        color: Colors.white.withOpacity(0.06),
        child: const Icon(Icons.movie_outlined, color: Colors.white38),
      ),
    );
  }
}
