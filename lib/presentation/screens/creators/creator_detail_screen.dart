import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/prefs/language_prefs.dart'; // uiLocaleProvider — Build 16 bilingual takes
import '../../../core/theme/app_colors.dart';
import '../../../data/mock/mock_creators.dart';
import '../../../data/models/content.dart';
import '../../../data/models/creator.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/blocks_repository.dart';
import '../../../data/repositories/catalog_provider.dart';
import '../../../data/repositories/creators_provider.dart';
import '../../../data/repositories/follows_repository.dart';
import '../../../data/repositories/reports_repository.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/take_context_menu.dart';
import '../../widgets/user_avatar.dart';

/// Shared confirm-block dialog. Used from the app-bar ⋯ menu on the
/// creator profile and from the per-take context menu. Invokes
/// `blocksProvider.notifier.block` and surfaces success/failure as a
/// snackbar. Safe to call with a non-mounted context — it no-ops after
/// the await.
Future<void> _confirmBlock(
  BuildContext context,
  WidgetRef ref, {
  required String alias,
  required String userId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(l10n.blockConfirmTitle(alias)),
      content: Text(l10n.blockConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.blockConfirmCta),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final success =
      await ref.read(blocksProvider.notifier).block(userId);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(success ? l10n.blockedState : l10n.reportError),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}

/// Individual creator profile: bio + stats + their takes.
class CreatorDetailScreen extends ConsumerWidget {
  final String creatorId;
  const CreatorDetailScreen({super.key, required this.creatorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final creatorAsync = ref.watch(creatorByIdProvider(creatorId));
    final creator = creatorAsync.valueOrNull ?? MockCreators.byId(creatorId);

    if (creator == null) {
      return Scaffold(
        appBar: AppBar(),
        body: creatorAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const Center(child: Text('Creator not found')),
      );
    }

    final isFollowing = ref.watch(followsProvider).contains(creator.id);
    final takesAsync = ref.watch(takesByCreatorProvider(creator.id));
    final takes = takesAsync.valueOrNull ?? MockCreators.takesBy(creator.id);

    // Detect if the current user owns this creator profile.
    final currentCreator = ref.watch(currentCreatorProvider).valueOrNull;
    final isOwnProfile = currentCreator?.id == creator.id;

    // Build 16 — block state. A creator without a resolvable user_id
    // (curated system creators pre-Build-16) can't be blocked; hide the
    // control in that case.
    final blocked = ref.watch(blocksProvider);
    final blockableUid = creator.userId;
    final isBlocked =
        blockableUid != null && blocked.contains(blockableUid);
    final canBlock =
        !isOwnProfile && blockableUid != null && ref.watch(currentUserProvider) != null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        // Build 16 — ⋯ menu gives Report + (when blockable) Block against
        // the whole creator profile. Hidden on own profile.
        actions: [
          if (!isOwnProfile)
            TakeContextMenuButton(
              targetType: ReportTargetType.creatorProfile,
              targetId: creator.id,
              iconColor: Colors.white70,
              onBlock: canBlock && !isBlocked
                  ? () => _confirmBlock(
                        context,
                        ref,
                        alias: creator.alias,
                        userId: blockableUid!,
                      )
                  : null,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            // Header
            Row(
              children: [
                _BigAvatar(creatorId: creator.id, alias: creator.alias, isCurated: creator.isCurated),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              creator.alias,
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (creator.isCurated) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified,
                                size: 18, color: AppColors.accent),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        creator.specialty,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.creatorsFollowersCount(creator.followersCount),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              creator.bio,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            // Hide follow button on own profile. When this creator is
            // already blocked we swap the Follow CTA for a gentle
            // "Blocked — tap to unblock" affordance; following a user
            // you've also blocked is nonsensical, so the two controls
            // are mutually exclusive.
            if (!isOwnProfile)
              SizedBox(
                width: double.infinity,
                child: isBlocked
                    ? OutlinedButton.icon(
                        onPressed: () async {
                          await ref
                              .read(blocksProvider.notifier)
                              .unblock(blockableUid!);
                        },
                        icon: const Icon(Icons.block, size: 18),
                        label: Text(l10n.unblockAction),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: () async {
                          // `toggle` now awaits the remote upsert/delete so the
                          // `trg_follower_count` trigger on `user_follows` has
                          // already run by the time we invalidate below. Before
                          // the awaited version, the re-read raced the INSERT
                          // and showed the pre-toggle count until app restart.
                          await ref
                              .read(followsProvider.notifier)
                              .toggle(creator.id);
                          // Refresh both the detail view and the global creators
                          // list so the counter updates in every surface that
                          // displays it (detail header + creators grid).
                          ref.invalidate(creatorByIdProvider(creator.id));
                          ref.invalidate(creatorsProvider);
                        },
                        icon: Icon(
                            isFollowing ? Icons.check : Icons.add,
                            size: 18),
                        label: Text(isFollowing
                            ? l10n.creatorsFollowing
                            : l10n.creatorsFollow),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isFollowing ? Colors.white12 : AppColors.accent,
                          foregroundColor:
                              isFollowing ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
            const SizedBox(height: 28),
            Text(
              isOwnProfile ? 'My Takes' : l10n.creatorDetailTakes,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final t in takes)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DetailTakeRow(
                  take: t,
                  isOwn: isOwnProfile,
                  creator: creator,
                ),
              ),
            if (takes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  isOwnProfile
                      ? 'No takes yet — go review a title!'
                      : '—',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BigAvatar extends ConsumerWidget {
  final String creatorId;
  final String alias;
  final bool isCurated;
  const _BigAvatar({
    required this.creatorId,
    required this.alias,
    required this.isCurated,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentCreator = ref.watch(currentCreatorProvider).valueOrNull;
    final isMe = currentCreator?.id == creatorId;

    // Build 16 — resolve cross-user avatars via public_profiles. Mirrors
    // _SmartAvatar on creators_screen so the profile-detail hero image
    // matches what's shown in the carousel / feed.
    String? resolvedAvatarKey;
    if (isMe) {
      resolvedAvatarKey = ref.watch(userProfileProvider).avatarKey;
    } else {
      final creatorAsync = ref.watch(creatorByIdProvider(creatorId));
      final uid = creatorAsync.valueOrNull?.userId;
      if (uid != null) {
        resolvedAvatarKey =
            ref.watch(publicProfileByIdProvider(uid)).valueOrNull?.avatarKey;
      }
    }

    final Widget avatarContent;
    if (resolvedAvatarKey != null) {
      avatarContent = UserAvatar(
        avatarKey: resolvedAvatarKey,
        seed: alias,
        size: 84,
        withBorder: false,
      );
    } else {
      final clean = alias.replaceAll('@', '');
      final initials = clean.length >= 2
          ? clean.substring(0, 2).toUpperCase()
          : clean.toUpperCase();
      final hue = (clean.codeUnits.fold<int>(0, (a, b) => a + b) * 37) % 360;
      final bg = HSLColor.fromAHSL(1.0, hue.toDouble(), 0.55, 0.45).toColor();

      avatarContent = Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          border: Border.all(
            color: isCurated ? AppColors.accent : Colors.white24,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
    }

    return Stack(
      children: [
        avatarContent,
        if (isCurated)
          const Positioned(
            right: 0,
            bottom: 0,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.accent,
              child: Icon(Icons.verified, size: 14, color: Colors.black),
            ),
          ),
      ],
    );
  }
}

class _DetailTakeRow extends ConsumerWidget {
  final CreatorTake take;
  final bool isOwn;
  final Creator? creator;
  const _DetailTakeRow({
    required this.take,
    this.isOwn = false,
    this.creator,
  });

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete take?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFE5484D))),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await deleteTake(takeId: take.id);
    if (!context.mounted) return;

    if (ok) {
      ref.invalidate(latestTakesProvider);
      ref.invalidate(takesByCreatorProvider(take.creatorId));
      ref.invalidate(featuredSkipProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Take deleted.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete. Try again.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _openEditSheet(BuildContext context, Content content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditTakeSheet(
        creator: creator!,
        content: content,
        existingTake: take,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Load content individually — the catalog is limited to 600 titles,
    // so takes for less-popular titles would silently disappear.
    final contentAsync = ref.watch(contentByIdProvider(take.contentId));
    final content = contentAsync.valueOrNull;
    if (content == null) {
      // Still loading or not found — show placeholder while loading.
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

    final verdictColor = switch (take.verdict) {
      CreatorVerdict.worthIt => AppColors.accent,
      CreatorVerdict.skipIt => const Color(0xFFE5484D),
    };
    final verdictLabel = switch (take.verdict) {
      CreatorVerdict.worthIt => l10n.creatorVerdictWorthIt,
      CreatorVerdict.skipIt => l10n.creatorVerdictSkipIt,
    };

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _TakeDetailSheet(
          take: take,
          content: content,
          creator: creator,
          verdictColor: verdictColor,
          verdictLabel: verdictLabel,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 52,
                height: 78,
                child: content.posterUrl.isEmpty
                    ? Container(color: Colors.white12)
                    : Image.network(
                        content.posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: Colors.white12),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          content.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: verdictColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                          border:
                              Border.all(color: verdictColor.withOpacity(0.4)),
                        ),
                        child: Text(
                          verdictLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: verdictColor,
                          ),
                        ),
                      ),
                      // Build 16 — Report/Block menu on takes authored by
                      // OTHERS. Own takes already have Edit/Delete below,
                      // so no need for the menu there.
                      if (!isOwn && creator != null)
                        TakeContextMenuButton(
                          targetType: ReportTargetType.creatorTake,
                          targetId: take.id,
                          iconColor: Colors.white54,
                          onBlock: (creator!.userId != null &&
                                  ref.watch(currentUserProvider) != null &&
                                  !ref
                                      .watch(blocksProvider)
                                      .contains(creator!.userId))
                              ? () => _confirmBlock(
                                    context,
                                    ref,
                                    alias: creator!.alias,
                                    userId: creator!.userId!,
                                  )
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // Build 16 — locale-aware. Falls back gracefully when the
                    // active-locale column hasn't been populated yet.
                    take.localizedBody(
                      ref.watch(uiLocaleProvider)?.languageCode,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                  // Edit / Delete controls for own takes
                  if (isOwn) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (take.canEdit)
                          GestureDetector(
                            onTap: () => _openEditSheet(context, content),
                            child: Row(
                              children: [
                                const Icon(Icons.edit_outlined,
                                    size: 14, color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  'Edit (${take.editsRemaining} left)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!take.canEdit)
                          const Text(
                            'No edits remaining',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _confirmDelete(context, ref),
                          child: const Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 14, color: Color(0xFFE5484D)),
                              SizedBox(width: 4),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFE5484D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit sheet used from creator_detail_screen — mirrors _WriteTakeSheet
/// from content_screen but lives here to avoid cross-file private access.
class _EditTakeSheet extends ConsumerStatefulWidget {
  final Creator creator;
  final Content content;
  final CreatorTake existingTake;
  const _EditTakeSheet({
    required this.creator,
    required this.content,
    required this.existingTake,
  });

  @override
  ConsumerState<_EditTakeSheet> createState() => _EditTakeSheetState();
}

class _EditTakeSheetState extends ConsumerState<_EditTakeSheet> {
  final _controller = TextEditingController();
  late String _verdict;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Build 16 — pre-load the editor with whatever the user sees in the
    // UI for their active locale (not the legacy `body` column). Without
    // this a creator browsing in ES who taps "edit" on a take they'd been
    // reading in ES would see the EN original in the editor and overwrite
    // the wrong column on save.
    final locale = ref.read(uiLocaleProvider)?.languageCode;
    _controller.text = widget.existingTake.localizedBody(locale);
    _verdict = switch (widget.existingTake.verdict) {
      CreatorVerdict.worthIt => 'worth_it',
      CreatorVerdict.skipIt => 'skip_it',
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    setState(() => _submitting = true);

    // Build 16 — record authoring locale; defaults to 'en' (launch language).
    final activeLocale = ref.read(uiLocaleProvider)?.languageCode;
    final originalLanguage = activeLocale == 'es' ? 'es' : 'en';

    final ok = await updateTake(
      takeId: widget.existingTake.id,
      verdict: _verdict,
      body: body,
      currentEditCount: widget.existingTake.editCount,
      originalLanguage: originalLanguage,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      ref.invalidate(latestTakesProvider);
      ref.invalidate(takesByCreatorProvider(widget.creator.id));
      ref.invalidate(featuredSkipProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Take updated!'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save. Try again.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.existingTake.editsRemaining;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Edit take on "${widget.content.title}"',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '$remaining edit${remaining == 1 ? '' : 's'} remaining',
            style: TextStyle(
              fontSize: 12,
              color: remaining <= 1
                  ? const Color(0xFFE5484D)
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          // Verdict selector
          Row(
            children: [
              _EditVerdictChip(
                label: 'Worth It', icon: Icons.check_circle_outline,
                color: AppColors.accent, selected: _verdict == 'worth_it',
                onTap: () => setState(() => _verdict = 'worth_it'),
              ),
              const SizedBox(width: 8),
              _EditVerdictChip(
                label: 'Skip It', icon: Icons.do_not_disturb_on_outlined,
                color: const Color(0xFFE5484D), selected: _verdict == 'skip_it',
                onTap: () => setState(() => _verdict = 'skip_it'),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Text('Save Edit'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Build 16 — full-body read sheet shown when a creator-profile take row
/// is tapped. Replaces the old behavior (which pushed to the content
/// detail screen) so readers can actually see the whole take without the
/// 3-line ellipsis of the row summary. The "View title" button preserves
/// one-tap access to the content detail screen for the cases where the
/// user actually wanted the movie page.
class _TakeDetailSheet extends ConsumerWidget {
  final CreatorTake take;
  final Content content;
  final Creator? creator;
  final Color verdictColor;
  final String verdictLabel;
  const _TakeDetailSheet({
    required this.take,
    required this.content,
    required this.creator,
    required this.verdictColor,
    required this.verdictLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(uiLocaleProvider)?.languageCode;
    final body = take.localizedBody(locale);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            // Title strip: poster + title + verdict chip.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 52,
                    height: 78,
                    child: content.posterUrl.isEmpty
                        ? Container(color: Colors.white12)
                        : Image.network(
                            content.posterUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: Colors.white12),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        content.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: verdictColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: verdictColor.withOpacity(0.4)),
                        ),
                        child: Text(
                          verdictLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: verdictColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (creator != null)
              Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 14,
                      color: Theme.of(context).textTheme.bodySmall?.color),
                  const SizedBox(width: 4),
                  Text(
                    creator!.alias,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                child: Text(
                  body,
                  style: const TextStyle(fontSize: 15, height: 1.45),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/content/${content.id}');
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View title'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Verdict chip for the edit sheet (mirrors _VerdictChip in content_screen).
class _EditVerdictChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _EditVerdictChip({
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
