import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';

/// Manages the current user's block list.
///
/// Build 16 — Apple UGC compliance. One-way blocks: the blocker stops
/// seeing the blocked user's content everywhere; the blocked user is NOT
/// notified and can still see the blocker's content. This matches the
/// pattern most social apps use (TikTok is two-way, Instagram is also
/// two-way, but Twitter/X and Reddit are one-way — we picked one-way for
/// simplicity, per Vivi's decision).
///
/// State holds the set of `blocked_id` (auth.users.id) currently blocked
/// by the signed-in user. Follow the same pattern as [FollowsController]:
///   - optimistic local state flip
///   - awaited remote insert/delete so providers that read from Supabase
///     (e.g., `latestTakesProvider`) see the updated block set on the next
///     invalidate
///   - graceful no-op when offline / not signed in
///
/// Table: `public.user_blocks(blocker_id, blocked_id, created_at)`
/// RLS: user sees/modifies only their own rows.
class BlocksController extends StateNotifier<Set<String>> {
  BlocksController(this._ref) : super(const <String>{}) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final user = _ref.read(currentUserProvider);
    if (user == null) {
      state = const <String>{};
      return;
    }
    try {
      final sb = Supabase.instance.client;
      final rows = await sb
          .from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', user.id);
      state = rows
          .map((r) => r['blocked_id'] as String)
          .toSet();
    } catch (e) {
      if (kDebugMode) debugPrint('[blocks] load error: $e');
      state = const <String>{};
    }
  }

  /// Reload from the server. Called after auth state flips (sign-in / out)
  /// via a Riverpod listener.
  Future<void> refresh() => _load();

  /// Wipe local state. Used on sign-out.
  void clearLocal() {
    state = const <String>{};
  }

  bool isBlocked(String userId) => state.contains(userId);

  /// Block another user. Awaited — so callers that invalidate feed
  /// providers immediately after can rely on RLS-side filtering to be
  /// consistent.
  Future<bool> block(String blockedUserId) async {
    final user = _ref.read(currentUserProvider);
    if (user == null) return false;
    if (user.id == blockedUserId) return false; // CHECK constraint would fail.

    // Optimistic update.
    state = {...state, blockedUserId};
    try {
      final sb = Supabase.instance.client;
      await sb.from('user_blocks').insert({
        'blocker_id': user.id,
        'blocked_id': blockedUserId,
      });
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[blocks] block error: $e');
      // Roll back optimistic flip on failure.
      state = {...state}..remove(blockedUserId);
      return false;
    }
  }

  /// Unblock. Symmetric to [block].
  Future<bool> unblock(String blockedUserId) async {
    final user = _ref.read(currentUserProvider);
    if (user == null) return false;

    state = {...state}..remove(blockedUserId);
    try {
      final sb = Supabase.instance.client;
      await sb
          .from('user_blocks')
          .delete()
          .eq('blocker_id', user.id)
          .eq('blocked_id', blockedUserId);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[blocks] unblock error: $e');
      // Re-insert into local state if remote failed.
      state = {...state, blockedUserId};
      return false;
    }
  }
}

final blocksProvider =
    StateNotifierProvider<BlocksController, Set<String>>((ref) {
  final controller = BlocksController(ref);
  // Reload when auth flips (sign-in / sign-out). Without this, an old
  // user's block list would bleed into a new session until restart.
  ref.listen(currentUserProvider, (prev, next) {
    if (prev?.id != next?.id) controller.refresh();
  });
  return controller;
});
