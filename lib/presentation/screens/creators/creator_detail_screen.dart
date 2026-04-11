import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/mock/mock_creators.dart';
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
              l10n.creatorDetailTakes,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final t in takes)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DetailTakeRow(take: t),
              ),
            if (takes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '—',
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
  const _DetailTakeRow({required this.take});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final catalog = ref.watch(catalogProvider).valueOrNull ?? [];
    final content = catalog.where((c) => c.id == take.contentId).firstOrNull;
    if (content == null) return const SizedBox.shrink();

    final verdictColor = switch (take.verdict) {
      CreatorVerdict.worthIt => AppColors.accent,
      CreatorVerdict.skipIt => const Color(0xFFE5484D),
      CreatorVerdict.quickTake => Colors.white70,
    };
    final verdictLabel = switch (take.verdict) {
      CreatorVerdict.worthIt => l10n.creatorVerdictWorthIt,
      CreatorVerdict.skipIt => l10n.creatorVerdictSkipIt,
      CreatorVerdict.quickTake => l10n.creatorVerdictQuickTake,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
