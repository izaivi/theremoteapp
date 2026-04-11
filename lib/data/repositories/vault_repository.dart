import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_sync.dart';

/// Vault — "Mi Bóveda". The user's personal library of content signals.
///
/// Kept separate from [UserProfile] for the same reason as [FollowsRepository]:
/// these sets mutate frequently (every tap on a card) and we want the profile
/// blob to stay compact. Moves to Supabase `vault` when backend lands.
///
/// Three mutually-exclusive buckets:
///   - [loved]       : explicit ❤️ / heart. Personal fave, independent from ★ rating.
///   - [watchlist]   : 🔖 saved for later, not yet watched.
///   - [notForMe]    : 👎 explicit dismiss. Excluded from future recs.
///
/// Mutual exclusion: adding a content to any bucket removes it from the others.
/// This matches the way users think about a title — "I love it" and "not for
/// me" are contradictory states, not tags.
class VaultState {
  final Set<String> loved;
  final Set<String> watchlist;
  final Set<String> notForMe;

  const VaultState({
    this.loved = const <String>{},
    this.watchlist = const <String>{},
    this.notForMe = const <String>{},
  });

  static const empty = VaultState();

  VaultState copyWith({
    Set<String>? loved,
    Set<String>? watchlist,
    Set<String>? notForMe,
  }) =>
      VaultState(
        loved: loved ?? this.loved,
        watchlist: watchlist ?? this.watchlist,
        notForMe: notForMe ?? this.notForMe,
      );

  bool isLoved(String id) => loved.contains(id);
  bool isWatchlisted(String id) => watchlist.contains(id);
  bool isNotForMe(String id) => notForMe.contains(id);
}

class VaultRepository {
  static const _key = 'vault.v1';

  Future<VaultState> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return VaultState.empty;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return VaultState(
        loved: ((j['loved'] as List?)?.cast<String>() ?? const []).toSet(),
        watchlist:
            ((j['watchlist'] as List?)?.cast<String>() ?? const []).toSet(),
        notForMe:
            ((j['notForMe'] as List?)?.cast<String>() ?? const []).toSet(),
      );
    } catch (_) {
      return VaultState.empty;
    }
  }

  Future<void> save(VaultState s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode({
        'loved': s.loved.toList(),
        'watchlist': s.watchlist.toList(),
        'notForMe': s.notForMe.toList(),
      }),
    );
  }
}

final vaultRepositoryProvider =
    Provider<VaultRepository>((ref) => VaultRepository());

class VaultController extends StateNotifier<VaultState> {
  VaultController(this._repo, this._sync) : super(VaultState.empty) {
    _load();
  }

  final VaultRepository _repo;
  final SupabaseSyncService _sync;

  Future<void> _load() async {
    state = await _repo.load();
  }

  /// Pull remote vault and merge with local. Called after sign-in.
  Future<void> refreshFromRemote() async {
    if (!_sync.isSignedIn) return;
    final remote = await _sync.pullVault();
    final merged = VaultState(
      loved: {...state.loved, ...remote.loved},
      watchlist: {...state.watchlist, ...remote.watchlist},
      notForMe: {...state.notForMe, ...remote.notForMe},
    );
    await _persist(merged);
  }

  Future<void> _persist(VaultState next) async {
    state = next;
    await _repo.save(next);
  }

  /// Toggle loved. Removes from watchlist + notForMe if present (mutex).
  Future<void> toggleLoved(String id) async {
    if (state.isLoved(id)) {
      await _persist(state.copyWith(loved: {...state.loved}..remove(id)));
      _sync.deleteVaultEntry(id);
      return;
    }
    await _persist(state.copyWith(
      loved: {...state.loved, id},
      watchlist: {...state.watchlist}..remove(id),
      notForMe: {...state.notForMe}..remove(id),
    ));
    _sync.pushVaultBucket(id, 'loved');
  }

  /// Toggle watchlist. Removes from loved + notForMe if present.
  Future<void> toggleWatchlist(String id) async {
    if (state.isWatchlisted(id)) {
      await _persist(
          state.copyWith(watchlist: {...state.watchlist}..remove(id)));
      _sync.deleteVaultEntry(id);
      return;
    }
    await _persist(state.copyWith(
      watchlist: {...state.watchlist, id},
      loved: {...state.loved}..remove(id),
      notForMe: {...state.notForMe}..remove(id),
    ));
    _sync.pushVaultBucket(id, 'watchlist');
  }

  /// Toggle notForMe. Removes from loved + watchlist if present.
  Future<void> toggleNotForMe(String id) async {
    if (state.isNotForMe(id)) {
      await _persist(
          state.copyWith(notForMe: {...state.notForMe}..remove(id)));
      _sync.deleteVaultEntry(id);
      return;
    }
    await _persist(state.copyWith(
      notForMe: {...state.notForMe, id},
      loved: {...state.loved}..remove(id),
      watchlist: {...state.watchlist}..remove(id),
    ));
    _sync.pushVaultBucket(id, 'not_for_me');
  }

  Future<void> clear() async {
    await _persist(VaultState.empty);
  }
}

final vaultProvider =
    StateNotifierProvider<VaultController, VaultState>(
  (ref) => VaultController(
    ref.watch(vaultRepositoryProvider),
    ref.watch(supabaseSyncProvider),
  ),
);
