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
      });
    } on PostgrestException catch (e) {
      // Surface unique_violation so callers (setAlias) can show a friendly
      // message. Everything else stays fire-and-forget.
      if (e.code == '23505') rethrow;
    } catch (_) {
      // best-effort: never crash UI on a sync failure
    }
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
          (r['content_id'] as String): (r['stars'] as num).toInt()
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
    } catch (_) {}
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
    } catch (_) {}
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
        final id = r['content_id'] as String;
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
    } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
  }
}

final supabaseSyncProvider =
    Provider<SupabaseSyncService>((ref) => SupabaseSyncService());
