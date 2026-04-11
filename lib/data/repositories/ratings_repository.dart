import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_sync.dart';

/// Ratings — the user's personal star ratings per content.
///
/// Intentionally separate from [VaultRepository] even though both get shown
/// in Mi Bóveda: a rating is a precise scalar signal (1–5 stars) that feeds
/// the recommendation engine's taste model, while vault buckets are coarse
/// actions (save / dismiss). Mixing them in one blob would conflate
/// semantics that the engine wants to treat differently.
///
/// Mental model inside the Vault screen:
///   - **Loved** tab  = titles rated 5 stars ∪ long-quiz `lovedRecentIds`.
///   - **Ranking** tab = every rated title, grouped by star value.
///
/// When backend lands this moves to Supabase `ratings (user_id, content_id,
/// stars, created_at)`. Until then, a single JSON blob in SharedPreferences.
class RatingsRepository {
  static const _key = 'ratings.v1';

  Future<Map<String, int>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return const <String, int>{};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return const <String, int>{};
    }
  }

  Future<void> save(Map<String, int> ratings) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(ratings));
  }
}

final ratingsRepositoryProvider =
    Provider<RatingsRepository>((ref) => RatingsRepository());

class RatingsController extends StateNotifier<Map<String, int>> {
  RatingsController(this._repo, this._sync) : super(const <String, int>{}) {
    _load();
  }

  final RatingsRepository _repo;
  final SupabaseSyncService _sync;

  Future<void> _load() async {
    state = await _repo.load();
  }

  /// Pull remote ratings and merge with local. Called after sign-in.
  /// Last-write-wins: remote overrides local for any overlapping ID.
  Future<void> refreshFromRemote() async {
    if (!_sync.isSignedIn) return;
    final remote = await _sync.pullRatings();
    final merged = {...state, ...remote};
    state = merged;
    await _repo.save(merged);
  }

  /// Wipe local state and storage. Used on sign-out / user switch.
  Future<void> clearLocal() async {
    state = const <String, int>{};
    await _repo.save(const <String, int>{});
  }

  int? ratingFor(String contentId) => state[contentId];

  /// Set a rating. Passing [stars] = 0 clears it (user un-rated).
  Future<void> setRating(String contentId, int stars) async {
    assert(stars >= 0 && stars <= 5);
    final next = {...state};
    if (stars == 0) {
      next.remove(contentId);
    } else {
      next[contentId] = stars;
    }
    state = next;
    await _repo.save(next);
    // Fire-and-forget remote sync.
    if (stars == 0) {
      _sync.deleteRating(contentId);
    } else {
      _sync.pushRating(contentId, stars);
    }
  }

  /// Convenience getters for Vault tabs.
  Iterable<String> get fiveStarIds =>
      state.entries.where((e) => e.value == 5).map((e) => e.key);

  /// All rated IDs grouped by star count (descending).
  Map<int, List<String>> groupedByStars() {
    final out = <int, List<String>>{};
    for (final e in state.entries) {
      out.putIfAbsent(e.value, () => []).add(e.key);
    }
    return out;
  }
}

final ratingsProvider =
    StateNotifierProvider<RatingsController, Map<String, int>>(
  (ref) => RatingsController(
    ref.watch(ratingsRepositoryProvider),
    ref.watch(supabaseSyncProvider),
  ),
);
