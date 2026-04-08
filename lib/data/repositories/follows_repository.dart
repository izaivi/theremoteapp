import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  FollowsController(this._repo) : super(const <String>{}) {
    _load();
  }

  final FollowsRepository _repo;

  Future<void> _load() async {
    state = await _repo.load();
  }

  bool isFollowing(String creatorId) => state.contains(creatorId);

  Future<void> toggle(String creatorId) async {
    final next = {...state};
    if (next.contains(creatorId)) {
      next.remove(creatorId);
    } else {
      next.add(creatorId);
    }
    state = next;
    await _repo.save(next);
  }
}

final followsProvider =
    StateNotifierProvider<FollowsController, Set<String>>(
  (ref) => FollowsController(ref.watch(followsRepositoryProvider)),
);
