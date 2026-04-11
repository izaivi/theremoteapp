import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/mock/mock_creators.dart';
import '../../../data/models/content.dart';
import '../../../data/models/creator.dart';
import '../../../data/repositories/catalog_provider.dart';
import '../../../data/repositories/creators_provider.dart';
import '../../../data/repositories/follows_repository.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/user_avatar.dart';

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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
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
            // Hide follow button on own profile
            if (!isOwnProfile)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      ref.read(followsProvider.notifier).toggle(creator.id),
                  icon: Icon(
                      isFollowing ? Icons.check : Icons.add,
                      size: 18),
                  label: Text(isFollowing
                      ? l10n.creatorsFollowing
                      : l10n.creatorsFollow),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isFollowing ? Colors.white12 : AppColors.accent,
                    foregroundColor: isFollowing ? Colors.white : Colors.black,
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
    final profile = isMe ? ref.watch(userProfileProvider) : null;

    final Widget avatarContent;
    if (isMe && profile != null) {
      avatarContent = UserAvatar(
        avatarKey: profile.avatarKey,
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
    final catalog = ref.watch(catalogProvider).valueOrNull ?? [];
    final content = catalog.where((c) => c.id == take.contentId).firstOrNull;
    if (content == null) return const SizedBox.shrink();

    final verdictColor = switch (take.verdict) {
      CreatorVerdict.worthIt => AppColors.accent,
      CreatorVerdict.skipIt => const Color(0xFFE5484D),
    };
    final verdictLabel = switch (take.verdict) {
      CreatorVerdict.worthIt => l10n.creatorVerdictWorthIt,
      CreatorVerdict.skipIt => l10n.creatorVerdictSkipIt,
    };

    return GestureDetector(
      onTap: () => context.push('/content/${content.id}'),
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
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    take.body,
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
    _controller.text = widget.existingTake.body;
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

    final ok = await updateTake(
      takeId: widget.existingTake.id,
      verdict: _verdict,
      body: body,
      currentEditCount: widget.existingTake.editCount,
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
