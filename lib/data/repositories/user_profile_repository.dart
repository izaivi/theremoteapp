import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import 'supabase_sync.dart';

/// Persists [UserProfile] locally via SharedPreferences as a JSON blob.
///
/// In Fase 1 del backend this will sync to Supabase `profiles`. Until then,
/// everything stays local. Kept as plain JSON (no freezed codegen) to match
/// the rest of `data/models/` bootstrap approach.
/// Thrown by [UserProfileController.setAlias] when another user already
/// owns the requested alias (Postgres unique_violation, SQLSTATE 23505).
class AliasTakenException implements Exception {
  const AliasTakenException();
  @override
  String toString() => 'AliasTakenException';
}

class UserProfileRepository {
  static const _key = 'user.profile.v1';

  Future<UserProfile> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return UserProfile.anonymous;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _fromJson(json);
    } catch (_) {
      // Corrupted blob — reset rather than crash.
      return UserProfile.anonymous;
    }
  }

  Future<void> save(UserProfile profile) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(_toJson(profile)));
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }

  // ---- JSON codec -----------------------------------------------------------

  Map<String, dynamic> _toJson(UserProfile p) => {
        'id': p.id,
        'alias': p.alias,
        'country': p.country,
        'activePlatforms': p.activePlatforms,
        'favoriteGenres': p.favoriteGenres,
        'sessionLength': p.sessionLength.name,
        'favoriteThemes': p.favoriteThemes,
        'watchedIds': p.watchedIds.toList(),
        'dismissedIds': p.dismissedIds.toList(),
        'quizCompletion': p.quizCompletion.name,
        'tier': p.tier,
        'avatarKey': p.avatarKey,
      };

  UserProfile _fromJson(Map<String, dynamic> j) {
    return UserProfile(
      id: j['id'] as String?,
      alias: j['alias'] as String?,
      country: j['country'] as String?,
      activePlatforms: (j['activePlatforms'] as List?)?.cast<String>() ?? const [],
      favoriteGenres: (j['favoriteGenres'] as List?)?.cast<String>() ?? const [],
      sessionLength: SessionLength.values.firstWhere(
        (e) => e.name == j['sessionLength'],
        orElse: () => SessionLength.medium,
      ),
      favoriteThemes: (j['favoriteThemes'] as List?)?.cast<String>() ?? const [],
      watchedIds: ((j['watchedIds'] as List?)?.cast<String>() ?? const []).toSet(),
      dismissedIds:
          ((j['dismissedIds'] as List?)?.cast<String>() ?? const []).toSet(),
      quizCompletion: QuizCompletion.values.firstWhere(
        (e) => e.name == j['quizCompletion'],
        orElse: () => QuizCompletion.none,
      ),
      tier: j['tier'] as String? ?? 'free',
      avatarKey: j['avatarKey'] as String?,
    );
  }
}

final userProfileRepositoryProvider =
    Provider<UserProfileRepository>((ref) => UserProfileRepository());

/// Global source of truth for the current user's profile.
///
/// Loads from disk on first read. Every mutation persists immediately so
/// there's no "save" button anywhere — the UI is always a reflection of
/// the stored state. Router redirects watch this to gate Home behind
/// onboarding completion.
class UserProfileController extends StateNotifier<UserProfile> {
  UserProfileController(this._repo, this._sync) : super(UserProfile.anonymous) {
    _load();
  }

  final UserProfileRepository _repo;
  final SupabaseSyncService _sync;

  Future<void> _load() async {
    state = await _repo.load();
  }

  /// After sign-in: pull remote profile and merge. Remote wins on conflict
  /// for fields it has, local wins for fields the remote schema doesn't
  /// store yet (favorite genres, themes, watched IDs — those live in
  /// future tables).
  Future<void> refreshFromRemote() async {
    if (!_sync.isSignedIn) return;
    final remote = await _sync.pullProfile();
    if (remote == null) {
      // Brand new account (no row yet) — seed with whatever we have locally.
      try {
        await _sync.pushProfile(state);
      } catch (_) {
        // 23505 or network error — don't block sign-in. User can re-save
        // alias manually from Profile → Change alias.
      }
      return;
    }
    // Merge: remote wins on fields it owns. For alias specifically, if the
    // remote doesn't have one but local does, we attempt a backfill push so
    // users who set an alias pre-auth (or pre-sync-wire) don't lose it.
    final merged = state.copyWith(
      id: remote.id ?? state.id,
      alias: remote.alias ?? state.alias,
      country: remote.country ?? state.country,
      avatarKey: remote.avatarKey ?? state.avatarKey,
      tier: remote.tier,
      quizCompletion: remote.quizCompletion != QuizCompletion.none
          ? remote.quizCompletion
          : state.quizCompletion,
    );
    state = merged;
    await _repo.save(merged);

    final needsBackfill = remote.alias == null && state.alias != null;
    if (needsBackfill) {
      try {
        await _sync.pushProfile(merged);
      } catch (_) {
        // Unique-violation (another user grabbed this alias first) or other
        // transient error. Best-effort: leave the local alias as-is so the
        // user can rename and retry from Profile → Change alias.
      }
    }
  }

  Future<void> completeFastQuiz({
    required String country,
    required List<String> activePlatforms,
    required List<String> favoriteGenres,
  }) async {
    final next = UserProfile.fromFastQuiz(
      country: country,
      activePlatforms: activePlatforms,
      favoriteGenres: favoriteGenres,
    );
    state = next;
    await _repo.save(next);
    _sync.pushProfile(next);
  }

  Future<void> completeLongQuiz(QuizAnswers answers) async {
    final next = state.withLongQuiz(answers);
    state = next;
    await _repo.save(next);
    _sync.pushProfile(next);
  }

  Future<void> markWatched(String contentId) async {
    final next = state.copyWith(watchedIds: {...state.watchedIds, contentId});
    state = next;
    await _repo.save(next);
  }

  Future<void> dismiss(String contentId) async {
    final next =
        state.copyWith(dismissedIds: {...state.dismissedIds, contentId});
    state = next;
    await _repo.save(next);
  }

  /// Change avatar. Accepts any of the [UserProfile.avatarKey] encodings.
  /// Pass `null` to clear back to initials fallback.
  /// Throws [AliasTakenException] if Supabase rejects with unique_violation.
  /// On success the local state is updated optimistically and the remote
  /// push runs inline (awaited) so the caller can react to the error.
  Future<void> setAlias(String alias) async {
    final prev = state;
    final next = state.copyWith(alias: alias);
    state = next;
    await _repo.save(next);
    try {
      await _sync.pushProfile(next);
    } on Object catch (e) {
      // Roll back local state on unique_violation so UI stays in sync.
      final msg = e.toString();
      if (msg.contains('23505') || msg.contains('profiles_alias_unique_ci')) {
        state = prev;
        await _repo.save(prev);
        throw const AliasTakenException();
      }
      // Other errors: local write stays, sync was best-effort anyway.
    }
  }

  Future<void> setAvatar(String? avatarKey) async {
    final next = state.copyWith(avatarKey: avatarKey);
    state = next;
    await _repo.save(next);
    _sync.pushProfile(next);
  }

  /// Hard reset — used from dev / debug / settings "sign out".
  Future<void> reset() async {
    state = UserProfile.anonymous;
    await _repo.clear();
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileController, UserProfile>(
  (ref) => UserProfileController(
    ref.watch(userProfileRepositoryProvider),
    ref.watch(supabaseSyncProvider),
  ),
);
