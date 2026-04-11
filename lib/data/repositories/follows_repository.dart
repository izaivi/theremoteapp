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
    if (wasFollowing) {
      _sync.deleteFollow(creatorId);
    } else {
      _sync.pushFollow(creatorId);
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
