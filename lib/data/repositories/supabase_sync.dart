import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
import '../models/user_profile.dart';
import 'vault_repository.dart';

/// Thin wrapper around Supabase tables for the 4 user-owned datasets.
///
/// Used by the controllers as a fire-and-forget remote mirror: on every
/// local mutation, the controller persists to SharedPreferences (source
/// of truth for offline) AND calls the matching `pushX` method here.
/// If `Supabase.instance.client.auth.currentUser` is null we silently
/// no-op so unauthenticated / local-only mode keeps working.
///
/// On sign-in, [pullAll] does a one-shot reconciliation:
///   - Pulls all remote rows for the current user.
///   - Returns them as Dart structures so the controllers can merge with
///     whatever they had locally and re-emit state.
///
/// Conflict policy (Fase 0): **last write wins, remote on tie**. Good
/// enough until we get real multi-device users complaining.
class SupabaseSyncService {
  SupabaseSyncService();

  SupabaseClient? get _client {
    if (!SupabaseConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  String? get _uid => _client?.auth.currentUser?.id;

  bool get isSignedIn => _uid != null;

  // ---------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------

  Future<UserProfile?> pullProfile() async {
    final c = _client;
    final uid = _uid;
    if (c == null || uid == null) return null;
    try {
      final row = await c.from('profiles').select().eq('id', uid).maybeSingle();
      if (row == null) return null;
      return UserProfile(
        id: row['id'] as String?,
        alias: row['alias'] as String?,
        country: row['country'] as String?,
        avatarKey: row['avatar_key'] as String?,
        tier: (row['tier'] as String?) ?? 'free',
        quizCompletion: QuizCompletion.values.firstWhere(
          (e) => e.name == (row['quiz_completion'] as String?),
          orElse: () => QuizCompletion.none,
        ),
        activePlatforms: _stringArray(row['active_platforms']),
        favoriteGenres: _stringArray(row['favorite_genres']),
        sessionLength: SessionLength.values.firstWhere(
          (e) => e.name == (row['session_length'] as String?),
          orElse: () => SessionLength.medium,
        ),
        favoriteThemes: _stringArray(row['favorite_themes']),
        // watched_canon_ids is the Long Quiz bootstrap seed (seenCanonIds +
        // lovedRecentIds). We merge it into the in-memory `watchedIds` set
        // so the engine's awarenessScore path sees them as already-watched
        // without a separate code branch. The user's running "I watched this"
        // mutations still push via the (future) user_watched table — this
        // column is immutable after the Long Quiz completes except when the
        // user re-runs the Long Quiz.
        watchedIds: _stringArray(row['watched_canon_ids']).toSet(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> pushProfile(UserProfile p) async {
    final c = _client;
    final uid = _uid;
    if (c == null || uid == null) return;
    try {
      await c.from('profiles').upsert({
        'id': uid,
        'alias': p.alias,
        'country': p.country,
        'avatar_key': p.avatarKey,
        'tier': p.tier,
        'quiz_completion': p.quizCompletion.name,
        'active_platforms': p.activePlatforms,
        'favorite_genres': p.favoriteGenres,
        'session_length': p.sessionLength.name,
        'favorite_themes': p.favoriteThemes,
        // Watched ids pushed here are the Long Quiz seed only. Runtime
        // "I marked this as watched" writes go through the ratings /
        // watched path — don't overwrite the seed from normal behavior.
        'watched_canon_ids': p.watchedIds.toList(),
      });
    } on PostgrestException catch (e) {
      // Surface unique_violation so callers (setAlias) can show a friendly
      // message. Everything else stays fire-and-forget.
      if (e.code == '23505') rethrow;
    } catch (_) {
      // best-effort: never crash UI on a sync failure
    }
  }

  /// Postgrest returns `text[]` columns as `List<dynamic>`. Normalize to a
  /// `List<String>`, tolerating nulls and non-string entries (defensively —
  /// the check constraint on session_length is the only enum we enforce
  /// at the DB; string arrays are free-form so we trust the client writer).
  List<String> _stringArray(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList();
  }

  /// Returns `true` if [alias] is not yet taken by another user.
  /// Case-insensitive. Returns `true` on network errors (optimistic) so a
  /// transient failure doesn't block the user — the DB unique index is
  /// the ultimate source of truth.
  Future<bool> isAliasAvailable(String alias) async {
    final c = _client;
    if (c == null) return true;
    final trimmed = alias.trim();
    if (trimmed.isEmpty) return true;
    try {
      // Consultamos la VISTA `public_profiles` (solo id/alias/avatar_key) en
      // vez de la tabla `profiles` directamente. Post checkpoint de seguridad
      // 2026-04-09, las policies de `profiles` son owner-only (`TO authenticated`
      // + `auth.uid() = id`), así que la tabla ya no es legible cross-user.
      // La vista es `security_definer` y solo expone 3 columnas no sensibles.
      final rows = await c
          .from('public_profiles')
          .select('id')
          .ilike('alias', trimmed)
          .limit(1);
      if (rows.isEmpty) return true;
      // If the only match is the current user, it's still "available".
      final uid = _uid;
      if (uid != null && rows.first['id'] == uid) return true;
      return false;
    } catch (_) {
      return true;
    }
  }

  // ---------------------------------------------------------------------
  // Ratings
  // ---------------------------------------------------------------------

  Future<Map<String, int>> pullRatings() async {
    final c = _client;
    final uid = _uid;
    if (c == null || uid == null) return const {};
    try {
      final rows = await c
          .from('user_ratings')
          .select('content_id,stars')
          .eq('user_id', uid);
      return {
        for (final r in (rows as List))
          r['content_id'].toString(): (r['stars'] as num).toInt()
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> pushRating(String contentId, int stars) async {
    final c = _client;
    final uid = _uid;
    if (c == null || uid == null) return;
    try {
      await c.from('user_ratings').upsert({
        'user_id': uid,
        'content_id': contentId,
        'stars': stars,
      });
    } catch (e) {
      // Best-effort sync. Log in debug so a silent schema/RLS regression
      // doesn't hide itself like the user_vault CHECK bug did (2026-04-14).
      if (kDebugMode) debugPrint('[sync] pushRating failed: $e');
    }
  }

  Future<void> deleteRating(String contentId) async {
    final c = _client;
    final uid = _uid;
    if (c == null || uid == null) return;
    try {
      await c
          .from('user_ratings')
          .delete()
          .eq('user_id', uid)
          .eq('content_id', contentId);
    } catch (e) {
      if (kDebugMode) debugPrint('[sync] deleteRating failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Vault (loved + watchlist + not_for_me)
  // ---------------------------------------------------------------------

  Future<VaultState> pullVault() async {
    final c = _client;
    final uid = _uid;
    if (c == null || uid == null) return VaultState.empty;
    try {
      final rows = await c
          .from('user_vault')
          .select('content_id,bucket')
          .eq('user_id', uid);
      final loved = <String>{};
      final watchlist = <String>{};
      final notForMe = <String>{};
      for (final r in (rows as List)) {
        final id = r['content_id'].toString();
        switch (r['bucket'] as String) {
          case 'loved':
            loved.add(id);
            break;
          case 'watchlist':
            watchlist.add(id);
            break;
          case 'not_for_me':
            notForMe.add(id);
            break;
        }
      }
      return VaultState(loved: loved, watchlist: watchlist, notForMe: notForMe);
    } catch (_) {
      return VaultState.empty;
    }
  }

  Future<void> pushVaultBucket(String contentId, String bucket) async {
    final c = _client;
    final uid = _uid;
    if (c == null || uid == null) return;
    try {
      await c.from('user_vault').upsert({
        'user_id': uid,
        'content_id': contentId,
        'bucket': bucket,
      });
    } catch (e) {
      // 2026-04-14: this catch previously swallowed a CHECK violation for
      // bucket='loved' that wasn't in the original constraint. Loved items
      // were silently never persisted to Supabase, so they disappeared after
      // flutter clean. Never silence this again — log in debug at minimum.
      if (kDebugMode) {
        debugPrint('[sync] pushVaultBucket($contentId, $bucket) failed: $e');
      }
    }
  }

  Future<void> deleteVaultEntry(String contentId) async {
    final c = _client;
    final uid = _uid;
    if (c == null || uid == null) return;
    try {
      await c
          .from('user_vault')
          .delete()
          .eq('user_id', uid)
          .eq('content_id', contentId);
    } catch (e) {
      if (kDebugMode) debugPrint('[sync] deleteVaultEntry failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Follows
  // ---------------------------------------------------------------------

  Future<Set<String>> pullFollows() async {
    final c = _client;
    final uid = _uid;
    if (c == null || uid == null) return const {};
    try {
      final rows =
          await c.from('user_follows').select('creator_id').eq('user_id', uid);
      return {for (final r in (rows as List)) r['creator_id'] as String};
    } catch (_) {
      return const {};
    }
  }

  Future<void> pushFollow(String creatorId) async {
    final c = _client;
    final uid = _uid;
    if (c == null || uid == null) return;
    try {
      await c.from('user_follows').upsert({
        'user_id': uid,
        'creator_id': creatorId,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[sync] pushFollow failed: $e');
    }
  }

  Future<void> deleteFollow(String creatorId) async {
    final c = _client;
    final uid = _uid;
    if (c == null || uid == null) return;
    try {
      await c
          .from('user_follows')
          .delete()
          .eq('user_id', uid)
          .eq('creator_id', creatorId);
    } catch (e) {
      if (kDebugMode) debugPrint('[sync] deleteFollow failed: $e');
    }
  }
}

final supabaseSyncProvider =
    Provider<SupabaseSyncService>((ref) => SupabaseSyncService());
