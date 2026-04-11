import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/mock/mock_content.dart';
import '../../../data/models/content.dart';
import '../../../data/models/creator.dart';
import '../../../data/models/signals.dart';
import '../../../data/repositories/catalog_provider.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/creators_provider.dart';
import '../../../data/repositories/ratings_repository.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../data/repositories/vault_repository.dart';
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
    final contentAsync = ref.watch(contentByIdProvider(contentId));

    return contentAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (content) => _buildDetail(context, ref, l10n, content),
    );
  }

  Widget _buildDetail(
      BuildContext context, WidgetRef ref, AppLocalizations l10n, Content? content) {
    if (content == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Content "$contentId" not found.')),
      );
    }

    // FansSay and QuickTakes are still mock — real social signals come in Fase 2.
    final fansSay = MockContent.fansSayFor(contentId);
    final takes = MockContent.quickTakesFor(contentId);
    final profile = ref.watch(userProfileProvider);
    final isAuthed = ref.watch(currentUserProvider) != null;
    final currentCreator = ref.watch(currentCreatorProvider).valueOrNull;

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
              const SizedBox(height: 16),
              _MyRatingBar(contentId: content.id),
              if (currentCreator != null) ...[
                const SizedBox(height: 12),
                _WriteTakeButton(
                  creator: currentCreator,
                  content: content,
                ),
              ],
              const SizedBox(height: 8),
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
                child: content.availablePlatforms.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16, color: AppColors.textMuted),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Not available on any streaming platform in your region right now.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _PlatformChips(content: content),
              ),
              const SizedBox(height: 120),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: isAuthed
          ? null
          : _UserActionsBar(l10n: l10n, isAuthed: isAuthed),
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
    context.push('/auth');
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

// ---------------------------------------------------------------------------
// Platform chips — tappable to open streaming app deep links
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Write Take button + bottom sheet (only visible for creators)
// ---------------------------------------------------------------------------

class _WriteTakeButton extends StatelessWidget {
  final Creator creator;
  final Content content;
  const _WriteTakeButton({required this.creator, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.background,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _WriteTakeSheet(
            creator: creator,
            content: content,
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.accent.withOpacity(0.2),
                AppColors.accent.withOpacity(0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.edit_note, size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                'Write a Take as ${creator.alias}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WriteTakeSheet extends StatefulWidget {
  final Creator creator;
  final Content content;
  const _WriteTakeSheet({required this.creator, required this.content});

  @override
  State<_WriteTakeSheet> createState() => _WriteTakeSheetState();
}

class _WriteTakeSheetState extends State<_WriteTakeSheet> {
  final _controller = TextEditingController();
  String _verdict = 'worth_it';
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;

    setState(() => _submitting = true);

    final tmdbId = int.tryParse(widget.content.id);
    if (tmdbId == null) {
      setState(() => _submitting = false);
      return;
    }

    final ok = await submitTake(
      creatorId: widget.creator.id,
      contentId: tmdbId,
      verdict: _verdict,
      body: body,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Take published!'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to publish. Try again.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Title
          Text(
            'Take on "${widget.content.title}"',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Posting as ${widget.creator.alias}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          // Verdict selector
          Row(
            children: [
              _VerdictChip(
                label: 'Worth It',
                icon: Icons.check_circle_outline,
                color: AppColors.accent,
                selected: _verdict == 'worth_it',
                onTap: () => setState(() => _verdict = 'worth_it'),
              ),
              const SizedBox(width: 8),
              _VerdictChip(
                label: 'Skip It',
                icon: Icons.do_not_disturb_on_outlined,
                color: const Color(0xFFE5484D),
                selected: _verdict == 'skip_it',
                onTap: () => setState(() => _verdict = 'skip_it'),
              ),
              const SizedBox(width: 8),
              _VerdictChip(
                label: 'Quick Take',
                icon: Icons.chat_bubble_outline,
                color: Colors.white70,
                selected: _verdict == 'quick_take',
                onTap: () => setState(() => _verdict = 'quick_take'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Text field
          TextField(
            controller: _controller,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'What do you think about this title?',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 12),
          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text('Publish Take'),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerdictChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _VerdictChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : Colors.white.withOpacity(0.15),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: selected ? color : AppColors.textMuted),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformChips extends StatelessWidget {
  final Content content;
  const _PlatformChips({required this.content});

  Future<void> _openDeepLink(BuildContext context, String platform) async {
    final link = content.platformDeepLinks[platform];
    if (link == null || link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No direct link available for $platform'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final uri = Uri.parse(link);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Fallback: try opening anyway (some custom schemes won't report
      // canLaunch but still work).
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open $platform'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in content.availablePlatforms)
            InkWell(
              onTap: () => _openDeepLink(context, p),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: content.platformDeepLinks.containsKey(p)
                      ? AppColors.accent.withOpacity(0.15)
                      : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: content.platformDeepLinks.containsKey(p)
                      ? Border.all(
                          color: AppColors.accent.withOpacity(0.4), width: 1)
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (content.platformDeepLinks.containsKey(p)) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.open_in_new,
                          size: 12, color: AppColors.accent),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My rating bar — 5-star input wired to [ratingsProvider]. Tapping a star
// sets the rating; tapping the same star again clears it. Also exposes a
// "Not for me" toggle that writes to [vaultProvider.notForMe] (the
// authoritative dismiss channel — replaces the creators-thumb semantic
// confusion from the prior version).
// ---------------------------------------------------------------------------

class _MyRatingBar extends ConsumerWidget {
  final String contentId;
  const _MyRatingBar({required this.contentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(ratingsProvider)[contentId] ?? 0;
    final vault = ref.watch(vaultProvider);
    final dismissed = vault.isNotForMe(contentId);
    final loved = vault.isLoved(contentId);
    final saved = vault.isWatchlisted(contentId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.contentMyRating,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        InkWell(
                          onTap: () {
                            final next = (current == i) ? 0 : i;
                            ref
                                .read(ratingsProvider.notifier)
                                .setRating(contentId, next);
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              i <= current
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 28,
                              color: i <= current
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ❤️ Loved — "me encanta", personal favorite
            InkWell(
              onTap: () =>
                  ref.read(vaultProvider.notifier).toggleLoved(contentId),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: loved
                      ? AppColors.accent.withOpacity(0.18)
                      : Colors.transparent,
                  border: Border.all(
                    color: loved
                        ? AppColors.accent
                        : Colors.white.withOpacity(0.15),
                  ),
                ),
                child: Icon(
                  loved ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: loved ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 🔖 Watchlist — "ver después"
            InkWell(
              onTap: () =>
                  ref.read(vaultProvider.notifier).toggleWatchlist(contentId),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: saved
                      ? const Color(0xFF4F8CFF).withOpacity(0.18)
                      : Colors.transparent,
                  border: Border.all(
                    color: saved
                        ? const Color(0xFF4F8CFF)
                        : Colors.white.withOpacity(0.15),
                  ),
                ),
                child: Icon(
                  saved ? Icons.bookmark : Icons.bookmark_border,
                  size: 18,
                  color: saved
                      ? const Color(0xFF4F8CFF)
                      : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 👎 Not for me toggle
            InkWell(
              onTap: () =>
                  ref.read(vaultProvider.notifier).toggleNotForMe(contentId),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: dismissed
                      ? Colors.redAccent.withOpacity(0.18)
                      : Colors.transparent,
                  border: Border.all(
                    color: dismissed
                        ? Colors.redAccent
                        : Colors.white.withOpacity(0.15),
                  ),
                ),
                child: Icon(
                  dismissed
                      ? Icons.thumb_down_alt
                      : Icons.thumb_down_alt_outlined,
                  size: 16,
                  color: dismissed
                      ? Colors.redAccent
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
