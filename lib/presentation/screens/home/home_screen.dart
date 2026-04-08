import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/mock/mock_content.dart';
import '../../../data/models/content.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/paywall_sheet.dart';
import '../../widgets/watcher_score_badge.dart';

/// Home — la pantalla que vende el producto.
///
/// 5 secciones ordenadas por intención del usuario:
///   1. Trending Now          — popular + de calidad
///   2. Exploding              — crecimiento acelerado
///   3. Quick Decision         — pelis cortas listas para hoy
///   4. 5 Gems                 — curaduría diaria (la joya del producto)
///   5. Don't Waste Your Time  — anti-recomendaciones (posicionamiento)
///
/// Todas las secciones son vistas sobre el mismo catálogo. Strings vía ARB.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final profile = ref.watch(userProfileProvider);
    final isPro = profile.tier == 'pro';

    // 5 Gems tease: si el user es free, las 2 gemas con menor Watcher Score
    // se ven claras y las 3 mejores quedan bloqueadas con blur + overlay.
    final allGems = [...MockContent.dailyGems]
      ..sort((a, b) => a.content.watcherScore.compareTo(b.content.watcherScore));
    final visibleGems = isPro ? allGems : allGems.take(2).toList();
    final lockedGems = isPro ? const <Gem>[] : allGems.skip(2).toList();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Header
          Text(
            l10n.homeTitle,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.homeTagline,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),

          // 1. Trending
          _ContentCarousel(
            title: l10n.sectionTrendingNow,
            subtitle: l10n.sectionTrendingSubtitle,
            items: MockContent.trending,
          ),
          const SizedBox(height: 24),

          // 2. Exploding
          _ContentCarousel(
            title: l10n.sectionExploding,
            subtitle: l10n.sectionExplodingSubtitle,
            items: MockContent.exploding,
            accent: Colors.orangeAccent,
          ),
          const SizedBox(height: 24),

          // 3. Quick Decision (muestra duración prominente)
          _ContentCarousel(
            title: l10n.sectionQuickDecision,
            subtitle: l10n.sectionQuickDecisionSubtitle,
            items: MockContent.quickDecision,
            showDuration: true,
          ),
          const SizedBox(height: 24),

          // 4. 5 Gems
          _SectionHeader(
            title: l10n.sectionFiveGems,
            subtitle: null,
          ),
          const SizedBox(height: 12),
          ...visibleGems.map((g) => _GemCard(gem: g)),
          ...lockedGems.map((g) => _LockedGemCard(gem: g)),
          if (lockedGems.isNotEmpty) ...[
            const SizedBox(height: 8),
            _LockedGemsTease(count: lockedGems.length),
          ],
          const SizedBox(height: 24),

          // 5. Don't waste — posicionamiento, estilo visual de advertencia
          _AvoidSection(
            title: l10n.sectionDontWaste,
            subtitle: l10n.sectionDontWasteSubtitle,
            items: MockContent.dontWaste,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? accent;
  const _SectionHeader({required this.title, this.subtitle, this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (accent != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Horizontal content carousel (Trending / Exploding / Quick Decision)
// ---------------------------------------------------------------------------

class _ContentCarousel extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Content> items;
  final bool showDuration;
  final Color? accent;

  const _ContentCarousel({
    required this.title,
    required this.subtitle,
    required this.items,
    this.showDuration = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title, subtitle: subtitle, accent: accent),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _ContentCard(
              content: items[i],
              showDuration: showDuration,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContentCard extends StatelessWidget {
  final Content content;
  final bool showDuration;
  const _ContentCard({required this.content, this.showDuration = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () => context.push('/content/${content.id}'),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 140,
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
                      child: _PosterImage(url: content.posterUrl),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.5),
                          ],
                          stops: const [0.6, 1.0],
                        ),
                      ),
                    ),
                  ),
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
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text(
              showDuration
                  ? l10n.contentDurationMin(content.durationMinutes)
                  : l10n.contentMeta(
                      content.year, content.availablePlatforms.join(", ")),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable poster loader with spinner + error fallback.
class _PosterImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  const _PosterImage({required this.url, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(color: AppColors.surface);
    }
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          color: AppColors.surface,
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.surface,
        child: const Icon(Icons.movie_outlined,
            color: AppColors.textMuted, size: 28),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gem card (sección 5 Gems)
// ---------------------------------------------------------------------------

class _GemCard extends StatelessWidget {
  final Gem gem;
  const _GemCard({required this.gem});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/content/${gem.content.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 84,
                child: _PosterImage(url: gem.content.posterUrl),
              ),
            ),
            const SizedBox(width: 12),
            WatcherScoreBadge(score: gem.content.watcherScore, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gem.content.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    gem.reason,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Locked Gem card (free tier tease) — poster blurreado, título con placeholder,
// Watcher Score como anillo sin número. Tap → paywall directo.
// ---------------------------------------------------------------------------

class _LockedGemCard extends StatelessWidget {
  final Gem gem;
  const _LockedGemCard({required this.gem});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => showPaywall(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Poster blurreado — se ve el color general pero no la imagen.
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 84,
                  child: ImageFiltered(
                    imageFilter:
                        ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: _PosterImage(url: gem.content.posterUrl),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ClipOval(
                child: ImageFiltered(
                  imageFilter:
                      ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: WatcherScoreBadge(
                    score: gem.content.watcherScore,
                    size: 48,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título con placeholder de guiones
                    Container(
                      height: 14,
                      width: 140,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: 200,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 10,
                      width: 160,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.lock_outline,
                size: 18,
                color: AppColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedGemsTease extends StatelessWidget {
  final int count;
  const _LockedGemsTease({required this.count});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () => showPaywall(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accent.withValues(alpha: 0.18),
              AppColors.accent.withValues(alpha: 0.06),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome,
                size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.fiveGemsLockedTease(count),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.fiveGemsLockedCta,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 12, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Don't Waste Your Time — estilo de advertencia
// ---------------------------------------------------------------------------

class _AvoidSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Content> items;
  const _AvoidSection({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: title,
          subtitle: subtitle,
          accent: Colors.redAccent,
        ),
        const SizedBox(height: 12),
        ...items.map((c) => _AvoidCard(content: c)),
      ],
    );
  }
}

class _AvoidCard extends StatelessWidget {
  final Content content;
  const _AvoidCard({required this.content});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () => context.push('/content/${content.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          WatcherScoreBadge(score: content.watcherScore, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Colors.redAccent,
                    decorationThickness: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.contentMeta(
                      content.year, content.availablePlatforms.join(", ")),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.redAccent.withValues(alpha: 0.7),
            size: 22,
          ),
        ],
      ),
      ),
    );
  }
}
