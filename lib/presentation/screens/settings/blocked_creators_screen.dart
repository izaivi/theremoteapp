import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repositories/blocks_repository.dart';
import '../../../l10n/app_localizations.dart';

/// Settings → Blocked creators.
///
/// Build 16 — Apple UGC compliance. Lists every `auth.users.id` in the
/// current user's `user_blocks` set, resolves it to the creator alias /
/// avatar (when that blocked user is also a creator — the common case,
/// since the primary place to block someone from is their creator
/// profile), and offers an Unblock button per row.
///
/// Blocked users who are NOT creators (e.g. a quick-take-only account the
/// user blocked from a quick-take context menu — reserved for future) are
/// shown with their auth uid abbreviated. Unblock still works.
class BlockedCreatorsScreen extends ConsumerStatefulWidget {
  const BlockedCreatorsScreen({super.key});

  @override
  ConsumerState<BlockedCreatorsScreen> createState() =>
      _BlockedCreatorsScreenState();
}

class _BlockedCreatorsScreenState
    extends ConsumerState<BlockedCreatorsScreen> {
  Future<List<_BlockedRow>>? _rowsFuture;
  Set<String> _lastBlocked = const <String>{};

  @override
  void initState() {
    super.initState();
    // Prime with current state; reload via didChangeDependencies when
    // blocks change.
    _lastBlocked = ref.read(blocksProvider);
    _rowsFuture = _loadRows(_lastBlocked);
  }

  Future<List<_BlockedRow>> _loadRows(Set<String> blockedIds) async {
    if (blockedIds.isEmpty) return const <_BlockedRow>[];
    try {
      final sb = Supabase.instance.client;
      // Join-free: fetch creators whose user_id is in the blocked set.
      // Anyone not represented in creators just renders as a raw uid.
      final rows = await sb
          .from('creators')
          .select('id, user_id, alias, avatar_url, specialty')
          .inFilter('user_id', blockedIds.toList());

      final byUserId = <String, Map<String, dynamic>>{
        for (final r in rows) (r['user_id'] as String): r,
      };
      return blockedIds.map((uid) {
        final row = byUserId[uid];
        return _BlockedRow(
          blockedUserId: uid,
          creatorId: row?['id'] as String?,
          alias: row?['alias'] as String?,
          avatarUrl: row?['avatar_url'] as String?,
          specialty: row?['specialty'] as String?,
        );
      }).toList();
    } catch (_) {
      // Fall back to bare-uuid rows so at least the Unblock button works.
      return blockedIds
          .map((uid) => _BlockedRow(blockedUserId: uid))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // React to block set changes — on unblock the list should refresh
    // locally without a manual pull. Cheap since the query is tiny.
    final currentBlocked = ref.watch(blocksProvider);
    if (currentBlocked != _lastBlocked) {
      _lastBlocked = currentBlocked;
      _rowsFuture = _loadRows(currentBlocked);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.blockedCreatorsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<_BlockedRow>>(
          future: _rowsFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.data ?? const <_BlockedRow>[];
            if (rows.isEmpty) return _EmptyState(l10n: l10n);
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: rows.length + 1,
              separatorBuilder: (_, i) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      l10n.blockedCreatorsHelp,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                  );
                }
                final row = rows[i - 1];
                return _BlockedRowTile(row: row);
              },
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppLocalizations l10n;
  const _EmptyState({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 48, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              l10n.blockedCreatorsEmpty,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedRow {
  final String blockedUserId;
  final String? creatorId;
  final String? alias;
  final String? avatarUrl;
  final String? specialty;

  _BlockedRow({
    required this.blockedUserId,
    this.creatorId,
    this.alias,
    this.avatarUrl,
    this.specialty,
  });
}

class _BlockedRowTile extends ConsumerStatefulWidget {
  final _BlockedRow row;
  const _BlockedRowTile({required this.row});

  @override
  ConsumerState<_BlockedRowTile> createState() => _BlockedRowTileState();
}

class _BlockedRowTileState extends ConsumerState<_BlockedRowTile> {
  bool _working = false;

  Future<void> _unblock() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _working = true);
    final ok = await ref
        .read(blocksProvider.notifier)
        .unblock(widget.row.blockedUserId);
    if (!mounted) return;
    setState(() => _working = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.reportError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final row = widget.row;
    final displayName = row.alias ??
        'User ${row.blockedUserId.substring(0, 8)}';
    final subtitle = row.specialty ?? row.blockedUserId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          _Avatar(
            alias: row.alias,
            avatarUrl: row.avatarUrl,
            fallbackSeed: row.blockedUserId,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: _working ? null : _unblock,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: AppColors.accent.withOpacity(0.6)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _working
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    l10n.unblockAction,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? alias;
  final String? avatarUrl;
  final String fallbackSeed;
  const _Avatar({
    required this.alias,
    required this.avatarUrl,
    required this.fallbackSeed,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.startsWith('http')) {
      return ClipOval(
        child: Image.network(
          avatarUrl!,
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initials(),
        ),
      );
    }
    return _initials();
  }

  Widget _initials() {
    final seed = (alias ?? fallbackSeed).replaceAll('@', '');
    final initials = seed.length >= 2
        ? seed.substring(0, 2).toUpperCase()
        : seed.toUpperCase();
    final hue = (seed.codeUnits.fold<int>(0, (a, b) => a + b) * 37) % 360;
    final bg = HSLColor.fromAHSL(1.0, hue.toDouble(), 0.55, 0.45).toColor();
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
