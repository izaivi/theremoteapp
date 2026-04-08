import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/mock/mock_content.dart';
import '../../../data/models/content.dart';
import '../../../data/models/signals.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/watcher_score_badge.dart';

/// Content detail — where both functions of the product meet:
///
///   1. SHOW all signals for a title (Watcher Score + breakdown + variance
///      + "Remote Fans Say" aggregate + individual quick takes + availability).
///
///   2. CAPTURE signal from the current user (rate, worth-my-time, quick take,
///      mark as seen). This is the first hard login gate — anonymous users
///      see everything but cannot contribute. The gate matches the auth
///      decision taken on 2026-04-07.
class ContentScreen extends ConsumerWidget {
  final String contentId;
  const ContentScreen({super.key, required this.contentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final content = MockContent.byId(contentId);

    if (content == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Content "$contentId" not found.')),
      );
    }

    final fansSay = MockContent.fansSayFor(contentId);
    final takes = MockContent.quickTakesFor(contentId);
    final profile = ref.watch(userProfileProvider);
    final isAuthed = profile.id != null; // mock: siempre false hasta Supabase

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 340,
            backgroundColor: AppColors.background,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go('/home'),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                content.title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15),
              ),
              centerTitle: true,
              titlePadding: const EdgeInsets.only(bottom: 14),
              background: _HeroBackdrop(content: content),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              _Header(content: content),
              const SizedBox(height: 16),
              _SignalsBlock(content: content, l10n: l10n),
              const SizedBox(height: 24),
              _Section(
                title: l10n.contentSectionSynopsis,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text(
                    content.synopsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _Section(
                title: l10n.contentSectionFansSay,
                child: _FansSayBlock(stats: fansSay, l10n: l10n),
              ),
              const SizedBox(height: 24),
              _Section(
                title: l10n.contentSectionQuickTakes,
                child: _QuickTakesBlock(takes: takes, l10n: l10n),
              ),
              const SizedBox(height: 24),
              _Section(
                title: l10n.contentSectionAvailable,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in content.availablePlatforms)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            p,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 120),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: _UserActionsBar(
        l10n: l10n,
        isAuthed: isAuthed,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero backdrop — blurred poster filling the SliverAppBar, with a sharp
// poster floating in the center. Apple TV / Letterboxd style.
// ---------------------------------------------------------------------------

class _HeroBackdrop extends StatelessWidget {
  final Content content;
  const _HeroBackdrop({required this.content});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred backdrop
        if (content.posterUrl.isNotEmpty)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Image.network(
              content.posterUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: AppColors.surface),
            ),
          )
        else
          Container(color: AppColors.surface),
        // Dark gradient for legibility
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background.withValues(alpha: 0.5),
                AppColors.background.withValues(alpha: 0.7),
                AppColors.background,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        // Centered sharp poster
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 40, bottom: 40),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: content.posterUrl.isEmpty
                      ? Container(color: AppColors.surface)
                      : Image.network(
                          content.posterUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.surface,
                            child: const Icon(Icons.movie_outlined,
                                color: AppColors.textMuted, size: 48),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final Content content;
  const _Header({required this.content});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WatcherScoreBadge(score: content.watcherScore, size: 84),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.contentMeta(
                      content.year, content.availablePlatforms.join(", ")),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${content.genres.join(" · ")}  ·  ${l10n.contentDurationMin(content.durationMinutes)}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Signals (Watcher Score breakdown row)
// ---------------------------------------------------------------------------

class _SignalsBlock extends StatelessWidget {
  final Content content;
  final AppLocalizations l10n;
  const _SignalsBlock({required this.content, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _Stat(label: l10n.contentTrustScore, value: '${content.trustScore}'),
            _StatDivider(),
            _Stat(label: l10n.contentVariance, value: '${content.variance}'),
            _StatDivider(),
            _Stat(
              label: 'IMDb',
              value: content.imdbScore?.toStringAsFixed(1) ?? '—',
            ),
            _StatDivider(),
            _Stat(
              label: 'Meta',
              value: content.metacriticScore?.toString() ?? '—',
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            label,
            style:
                const TextStyle(color: AppColors.textMuted, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 30,
        color: AppColors.textMuted.withValues(alpha: 0.25),
        margin: const EdgeInsets.symmetric(horizontal: 6),
      );
}

// ---------------------------------------------------------------------------
// Section wrapper
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: AppColors.accent,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fans Say aggregate
// ---------------------------------------------------------------------------

class _FansSayBlock extends StatelessWidget {
  final FansSayStats? stats;
  final AppLocalizations l10n;
  const _FansSayBlock({required this.stats, required this.l10n});

  @override
  Widget build(BuildContext context) {
    if (stats == null || !stats!.hasEnoughSignal) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Text(
          l10n.fansSayNotEnough,
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }
    final s = stats!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Line(
              icon: Icons.check_circle_outline,
              text: l10n.fansSayCompletion(s.completionRate),
            ),
            const SizedBox(height: 8),
            _Line(
              icon: Icons.thumb_up_outlined,
              text: l10n.fansSayWorth(s.worthMyTimePct),
            ),
            const SizedBox(height: 8),
            _Line(
              icon: Icons.star_outline,
              text: l10n.fansSayRating(s.avgRating.toStringAsFixed(1)),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.fansSaySample(s.sampleSize),
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Line({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// Quick takes list
// ---------------------------------------------------------------------------

class _QuickTakesBlock extends StatelessWidget {
  final List<QuickTake> takes;
  final AppLocalizations l10n;
  const _QuickTakesBlock({required this.takes, required this.l10n});

  @override
  Widget build(BuildContext context) {
    if (takes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Text(
          l10n.contentNoTakes,
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        children: [
          for (final t in takes) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        t.alias,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.accent,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      if (t.rating != null)
                        Row(
                          children: [
                            const Icon(Icons.star,
                                size: 14, color: AppColors.scoreGood),
                            const SizedBox(width: 3),
                            Text(
                              '${t.rating}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.body,
                    style: const TextStyle(
                        fontSize: 14, height: 1.35, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User action bar (hard login gate)
// ---------------------------------------------------------------------------

class _UserActionsBar extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isAuthed;
  const _UserActionsBar({required this.l10n, required this.isAuthed});

  void _gate(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.contentLoginGate,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.apple),
              label: const Text('Sign in with Apple'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.contentLoginGateCta),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(
            top: BorderSide(color: AppColors.surfaceElevated, width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _ActionBtn(
                icon: Icons.star_outline,
                label: l10n.contentActionRate,
                onTap: () => _gate(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionBtn(
                icon: Icons.thumb_up_outlined,
                label: l10n.contentActionWorth,
                onTap: () => _gate(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionBtn(
                icon: Icons.edit_outlined,
                label: l10n.contentActionTake,
                onTap: () => _gate(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: AppColors.textPrimary),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
