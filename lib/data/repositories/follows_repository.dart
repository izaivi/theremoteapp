import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_sync.dart';

/// Persists the set of creator IDs the user follows.
///
/// Lives separate from [UserProfile] on purpose: follows change often
/// and we want the profile blob to stay compact. Moves to Supabase
/// `follows` (user_id, creator_id) when backend lands.
class FollowsRepository {
  static const _key = 'follows.creators.v1';

  Future<Set<String>> load() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_key) ?? const <String>[]).toSet();
  }

  Future<void> save(Set<String> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, ids.toList());
  }
}

final followsRepositoryProvider =
    Provider<FollowsRepository>((ref) => FollowsRepository());

class FollowsController extends StateNotifier<Set<String>> {
  FollowsController(this._repo, this._sync) : super(const <String>{}) {
    _load();
  }

  final FollowsRepository _repo;
  final SupabaseSyncService _sync;

  Future<void> _load() async {
    state = await _repo.load();
  }

  Future<void> refreshFromRemote() async {
    if (!_sync.isSignedIn) return;
    final remote = await _sync.pullFollows();
    final merged = {...state, ...remote};
    state = merged;
    await _repo.save(merged);
  }

  /// Wipe local state and storage. Used on sign-out / user switch.
  Future<void> clearLocal() async {
    state = const <String>{};
    await _repo.save(const <String>{});
  }

  bool isFollowing(String creatorId) => state.contains(creatorId);

  /// Toggle follow/unfollow for a creator.
  ///
  /// IMPORTANT: the remote sync is **awaited** before this method returns.
  /// The previous fire-and-forget version caused a race where callers would
  /// invalidate `creatorByIdProvider` and re-read `creators.followers_count`
  /// *before* the INSERT/DELETE on `user_follows` had hit the DB, so the
  /// counter column (maintained by trigger `trg_follower_count`) still
  /// reflected the pre-toggle value. Result: Vivi would tap Follow, see
  /// "0 followers", then see "1 follower" only after a full app restart.
  ///
  /// The local state + SharedPreferences save happens optimistically so the
  /// button flips to "Following" immediately; the remote await only adds
  /// latency to the parent's post-await work (typically a provider
  /// invalidate), which is exactly where we need the server to be
  /// up-to-date.
  Future<void> toggle(String creatorId) async {
    final next = {...state};
    final wasFollowing = next.contains(creatorId);
    if (wasFollowing) {
      next.remove(creatorId);
    } else {
      next.add(creatorId);
    }
    state = next;
    await _repo.save(next);
    // Await the remote write so the counter trigger has run by the time
    // the caller invalidates the creator provider. `pushFollow` /
    // `deleteFollow` already swallow errors internally, so awaiting them
    // cannot propagate failures — worst case the remote silently no-ops
    // and the local state is still correct.
    if (wasFollowing) {
      await _sync.deleteFollow(creatorId);
    } else {
      await _sync.pushFollow(creatorId);
    }
  }
}

final followsProvider =
    StateNotifierProvider<FollowsController, Set<String>>(
  (ref) => FollowsController(
    ref.watch(followsRepositoryProvider),
    ref.watch(supabaseSyncProvider),
  ),
);
