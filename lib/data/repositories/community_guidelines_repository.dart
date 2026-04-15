import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';

/// Build 16 — Apple App Store Guideline 1.2 (UGC) compliance.
///
/// Tracks whether the current user has accepted Community Guidelines.
/// The first time a user attempts to publish ANY take (quick or creator)
/// the compose sheet is preceded by a modal asking them to Accept. On
/// accept we stamp `profiles.community_guidelines_accepted_at` and the
/// modal never appears again for that account.
///
/// We keep this as a StateNotifier + FutureProvider pair (similar to
/// blocks) so the UI can react instantly after accept without waiting
/// for a full profile reload.
class CommunityGuidelinesNotifier extends StateNotifier<bool> {
  final Ref _ref;

  // state = true when already accepted. Default false so the first
  // `ensure()` call after sign-in forces a server check.
  CommunityGuidelinesNotifier(this._ref) : super(false) {
    _load();
  }

  Future<void> _load() async {
    final user = _ref.read(currentUserProvider);
    if (user == null) {
      state = false;
      return;
    }
    try {
      final sb = Supabase.instance.client;
      final row = await sb
          .from('profiles')
          .select('community_guidelines_accepted_at')
          .eq('id', user.id)
          .maybeSingle();
      state = row != null &&
          row['community_guidelines_accepted_at'] != null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[community-guidelines] load error: $e');
      }
      // Fail closed — treat as not accepted so the modal shows. Better
      // to double-ask than to let a publish slip past.
      state = false;
    }
  }

  /// Called after sign-in / sign-out to reset or re-fetch.
  Future<void> refresh() => _load();

  /// Wipe local state — used on sign-out.
  void clearLocal() {
    state = false;
  }

  /// Persist acceptance to Supabase and flip local state to true.
  /// Returns true on success. On network failure we still flip local
  /// state so the user isn't re-prompted immediately within the same
  /// session — the server stamp will reconcile on next load.
  Future<bool> accept() async {
    final user = _ref.read(currentUserProvider);
    if (user == null) return false;
    // Optimistic flip so the publish flow can continue immediately.
    state = true;
    try {
      final sb = Supabase.instance.client;
      await sb
          .from('profiles')
          .update({
            'community_guidelines_accepted_at':
                DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', user.id);
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[community-guidelines] accept error: $e');
      }
      // Don't roll back local state — see docstring. The next refresh
      // will repair if the server really didn't get the write.
      return false;
    }
  }
}

/// `true` when the current user has already accepted the guidelines.
final communityGuidelinesAcceptedProvider =
    StateNotifierProvider<CommunityGuidelinesNotifier, bool>((ref) {
  final notifier = CommunityGuidelinesNotifier(ref);
  // Re-load when auth flips.
  ref.listen(authStateChangesProvider, (_, __) => notifier.refresh());
  return notifier;
});
