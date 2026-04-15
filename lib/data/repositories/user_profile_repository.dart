import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
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
    _loadCompleter = Completer<void>();
    _load();
  }

  final UserProfileRepository _repo;
  final SupabaseSyncService _sync;

  /// Resolves once [_load] has hydrated state from SharedPreferences.
  ///
  /// Used by main.dart's auth listener to avoid the cold-start race where
  /// `AuthChangeEvent.signedIn` fires before [_load] completes — at that
  /// moment `state.id` is still null (anonymous initial state), the
  /// listener's "is this a different user?" check always resolves true,
  /// and it calls [reset] which wipes SharedPreferences. Awaiting
  /// [ensureLoaded] lets the listener compare a hydrated id against the
  /// incoming uid, so legitimate returning sessions are recognized.
  late Completer<void> _loadCompleter;
  Future<void> ensureLoaded() => _loadCompleter.future;

  Future<void> _load() async {
    state = await _repo.load();
    if (!_loadCompleter.isCompleted) _loadCompleter.complete();
  }

  /// After sign-in: pull remote profile and merge. Remote wins on conflict
  /// for fields it owns (id, alias, country, avatar, tier, quizCompletion).
  /// Local wins for fields the remote schema doesn't store yet (favorite
  /// genres, themes, watched IDs — those live in future tables).
  ///
  /// **quizCompletion is canonical on the remote** (Build 15 fix for the
  /// "Rayo McQueen" bug reported in Build 14 TestFlight): if the user
  /// signs in with a brand-new account, remote.quizCompletion is `none`
  /// and we MUST surface that to the router so it redirects to /onboarding.
  /// The old merge kept the local value when remote was `none`, which
  /// meant a prior-user's `fast`/`long` leaked through SharedPreferences
  /// into the new session and skipped the quiz (plus broke Home's 5 Gems
  /// because the new user never seeded their genres/platforms).
  ///
  /// The user-switch reset in main.dart ensures local state is
  /// [UserProfile.anonymous] before we land here when the session's
  /// user id has changed, so the "remote canonical" rule can't wipe a
  /// legitimate mid-flight local edit in practice.
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
    //
    // Build 16 fix — defensive merge for the "ghost row" case:
    //
    // The `handle_new_user` trigger inserts an empty profiles row on signup
    // (id + is_guest only; every other column NULL/default). Until the app
    // pushes the user's quiz answers, `pullProfile` legitimately returns a
    // row with `quiz_completion = none`, empty platforms/genres arrays, and
    // `session_length = medium` (the column default).
    //
    // The previous merge took remote values unconditionally, which meant:
    //   - A tokenRefresh firing after 15min of idle → remote's empty
    //     `quiz_completion = none` stomped the local `fast` → router
    //     redirected to /onboarding and the user saw the quiz again.
    //   - Cold start before pushProfile had ever landed a real payload
    //     → same wipe → "Rayo McQueen" style forced re-quiz.
    //
    // New policy:
    //   - quizCompletion escalates only (none < fast < long). Remote can
    //     upgrade local but never downgrade. A cross-device user who
    //     completed the Long Quiz elsewhere still gets it synced; the
    //     trigger row's `none` can't poison an already-completed session.
    //   - Arrays (platforms, genres, themes) treat empty-remote as "never
    //     populated" and preserve local. A user who actually empties these
    //     via a new quiz always passes through completeFastQuiz which
    //     pushes a non-empty list, so this heuristic can't mask a genuine
    //     clear. (They picked platforms in the quiz — it's never empty in
    //     practice.)
    //   - session_length, tier, alias, country, avatar keep remote-wins
    //     fallback to local (these are scalars with real defaults that the
    //     user can't "accidentally clear").
    //   - watchedIds still UNION so runtime "mark watched" hasn't-synced
    //     writes aren't wiped by a pull.
    final merged = state.copyWith(
      id: remote.id ?? state.id,
      alias: remote.alias ?? state.alias,
      country: remote.country ?? state.country,
      avatarKey: remote.avatarKey ?? state.avatarKey,
      tier: remote.tier,
      quizCompletion: _mergeQuizCompletion(
        local: state.quizCompletion,
        remote: remote.quizCompletion,
      ),
      activePlatforms: remote.activePlatforms.isEmpty
          ? state.activePlatforms
          : remote.activePlatforms,
      favoriteGenres: remote.favoriteGenres.isEmpty
          ? state.favoriteGenres
          : remote.favoriteGenres,
      sessionLength: remote.sessionLength,
      favoriteThemes: remote.favoriteThemes.isEmpty
          ? state.favoriteThemes
          : remote.favoriteThemes,
      watchedIds: {...state.watchedIds, ...remote.watchedIds},
    );
    state = merged;
    await _repo.save(merged);

    // Heal-on-pull: push local when the remote has holes that we can fill.
    //   - alias: the original case (user set alias pre-auth / pre-sync wire).
    //   - avatarKey (Build 16): same class of bug. Two TestFlight accounts
    //     had NULL avatar_key in `profiles` despite both users having
    //     selected pet avatars. Result: other users saw initials instead of
    //     the real avatar because `publicProfileByIdProvider` reads from the
    //     view, which only shows what's persisted in `profiles`. Heal by
    //     pushing on next refresh whenever remote is NULL and local has one.
    final needsAliasBackfill = remote.alias == null && state.alias != null;
    final needsAvatarBackfill =
        remote.avatarKey == null && state.avatarKey != null;
    if (needsAliasBackfill || needsAvatarBackfill) {
      try {
        await _sync.pushProfile(merged);
      } catch (_) {
        // Unique-violation (another user grabbed this alias first) or other
        // transient error. Best-effort: leave the local values as-is so the
        // user can rename and retry from Profile → Change alias.
      }
    }
  }

  Future<void> completeFastQuiz({
    required String country,
    required List<String> activePlatforms,
    required List<String> favoriteGenres,
  }) async {
    assert(activePlatforms.isNotEmpty,
        'Fast Quiz requires at least one active platform.');
    // CRITICAL: preserve the existing state (especially `id`, `alias`,
    // `tier`, `avatarKey`) when applying Fast Quiz answers. Using
    // `UserProfile.fromFastQuiz` here would build a fresh profile from
    // scratch and wipe the Supabase auth id pulled by `refreshFromRemote`,
    // making the app look "logged out" everywhere that reads `profile.id`
    // (including Settings.isSignedIn). Re-running fast quiz from settings
    // shouldn't regress quiz completion either, so we only upgrade.
    final next = state.copyWith(
      country: country,
      activePlatforms: activePlatforms,
      favoriteGenres: favoriteGenres,
      quizCompletion: state.quizCompletion == QuizCompletion.long
          ? QuizCompletion.long
          : QuizCompletion.fast,
    );
    state = next;
    await _repo.save(next);
    // Build 16: awaited (was fire-and-forget). The race on a fresh signup was:
    // user finishes quiz → push scheduled → app backgrounds → tokenRefreshed
    // fires → refreshFromRemote reads the still-empty ghost row → local
    // state gets stomped back to quizCompletion=none and Home boots into
    // /onboarding. Awaiting ensures the push lands before any subsequent
    // pull can observe the row.
    await _sync.pushProfile(next);
  }

  Future<void> completeLongQuiz(QuizAnswers answers) async {
    final next = state.withLongQuiz(answers);
    state = next;
    await _repo.save(next);
    // See completeFastQuiz — awaited to close the push-vs-pull race window.
    await _sync.pushProfile(next);
  }

  /// Quiz completion is monotonic: it can only move forward (none → fast → long).
  /// A pull from Supabase that returns `none` (e.g. the `handle_new_user`
  /// trigger ghost row, or a transient read failure that defaulted to none)
  /// must never downgrade a local `fast`/`long` — that was the Build 15
  /// "forced re-quiz after idle/cold-start" bug.
  QuizCompletion _mergeQuizCompletion({
    required QuizCompletion local,
    required QuizCompletion remote,
  }) {
    const rank = {
      QuizCompletion.none: 0,
      QuizCompletion.fast: 1,
      QuizCompletion.long: 2,
    };
    return rank[remote]! > rank[local]! ? remote : local;
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
    // Build 16 — awaited push so cross-user avatar reads
    // (`publicProfileByIdProvider`) observe the new key as soon as the
    // save completes. Previous fire-and-forget let the app race ahead of
    // the insert, which was the bug pattern behind Vivi/Chitoge's DB
    // rows having NULL avatar_key despite both having selected avatars.
    try {
      await _sync.pushProfile(next);
    } catch (_) {
      // Best-effort: never crash the settings flow on a transient sync
      // error. The heal-on-pull logic in refreshFromRemote catches
      // anything that didn't land here.
    }
  }

  /// Update the subscription tier (`'free'` or `'pro'`).
  ///
  /// Called by [SubscriptionController] whenever the RevenueCat
  /// `CustomerInfo` stream reports a change in the "Flixscope Pro"
  /// entitlement. This is the single path that keeps the Supabase
  /// mirror (`profiles.tier`) in sync with the actual billing state.
  ///
  /// Idempotent — calling with the same tier is a cheap no-op, which
  /// matters because RevenueCat may emit the initial snapshot AND a
  /// subsequent identical update on the same boot.
  Future<void> setTier(String tier) async {
    if (state.tier == tier) return;
    final next = state.copyWith(tier: tier);
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

/// Whether the current user has pro-level access.
///
/// True if:
///   - `tier == 'pro'` (paid subscription), OR
///   - The user is a verified creator (creators get premium as a perk).
///
/// Usage: `ref.watch(isProProvider)` replaces `profile.tier == 'pro'`.
/// Defined here so every screen can import it from one place.
/// The actual creator check is injected by creators_provider.dart
/// via [isCreatorOverride].
final isProProvider = Provider<bool>((ref) {
  final profile = ref.watch(userProfileProvider);
  if (profile.tier == 'pro') return true;
  return ref.watch(isCreatorOverride);
});

/// Set to `true` by creators_provider when the logged-in user has a
/// creator profile. Defaults to false.
final isCreatorOverride = StateProvider<bool>((ref) => false);

/// Build 16 — minimal public snapshot of another user's profile.
///
/// Backed by the `public.public_profiles` view (security-definer, exposes
/// only `id, alias, avatar_key`). Used to render cross-user avatars on the
/// Creators tab and creator detail screen — prior to this, `_SmartAvatar`
/// only rendered the real avatar for the currently-logged-in user because
/// it read from local `userProfileProvider`. Other users' profiles showed
/// initials even when they had a pet avatar selected.
class PublicProfile {
  final String id;
  final String? alias;
  final String? avatarKey;
  const PublicProfile({
    required this.id,
    this.alias,
    this.avatarKey,
  });
}

/// Fetches a single user's public profile row. Returns null if the lookup
/// fails (network, RLS, row missing). Callers fall back to initials — this
/// provider is strictly best-effort visual enhancement; no UI state should
/// block on it.
final publicProfileByIdProvider =
    FutureProvider.family<PublicProfile?, String>((ref, userId) async {
  if (!SupabaseConfig.isConfigured) return null;
  try {
    final sb = Supabase.instance.client;
    final rows = await sb
        .from('public_profiles')
        .select('id, alias, avatar_key')
        .eq('id', userId)
        .limit(1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return PublicProfile(
      id: r['id'] as String,
      alias: r['alias'] as String?,
      avatarKey: r['avatar_key'] as String?,
    );
  } catch (_) {
    return null;
  }
});
