import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
import '../mock/mock_creators.dart';
import '../models/content.dart';
import '../models/creator.dart';
import 'auth_repository.dart';
import 'catalog_provider.dart';
import 'user_profile_repository.dart';

/// ------------------------------------------------------------------
/// Creators provider — reads from Supabase `creators` + `creator_takes`
/// when connected, falls back to mock data in local-only mode.
/// ------------------------------------------------------------------

/// All creators, sorted by followers (descending).
final creatorsProvider = FutureProvider<List<Creator>>((ref) async {
  if (!SupabaseConfig.isConfigured) return MockCreators.creators;

  final sb = Supabase.instance.client;
  final rows = await sb
      .from('creators')
      .select()
      .order('followers_count', ascending: false);

  return rows.map(_mapCreator).toList();
});

/// Single creator by ID.
final creatorByIdProvider =
    FutureProvider.family<Creator?, String>((ref, id) async {
  if (!SupabaseConfig.isConfigured) return MockCreators.byId(id);

  final sb = Supabase.instance.client;
  final rows = await sb.from('creators').select().eq('id', id).limit(1);
  if (rows.isEmpty) return MockCreators.byId(id);
  return _mapCreator(rows.first);
});

/// All takes, newest first.
final latestTakesProvider = FutureProvider<List<CreatorTake>>((ref) async {
  if (!SupabaseConfig.isConfigured) return MockCreators.latestTakes;

  final sb = Supabase.instance.client;
  final rows = await sb
      .from('creator_takes')
      .select()
      .order('created_at', ascending: false)
      .limit(50);

  return rows.map(_mapTake).toList();
});

/// Takes by a specific creator.
final takesByCreatorProvider =
    FutureProvider.family<List<CreatorTake>, String>((ref, creatorId) async {
  if (!SupabaseConfig.isConfigured) return MockCreators.takesBy(creatorId);

  final sb = Supabase.instance.client;
  final rows = await sb
      .from('creator_takes')
      .select()
      .eq('creator_id', creatorId)
      .order('created_at', ascending: false);

  return rows.map(_mapTake).toList();
});

/// Featured "skip it" take — newest skip_it verdict.
final featuredSkipProvider = FutureProvider<CreatorTake?>((ref) async {
  if (!SupabaseConfig.isConfigured) return MockCreators.featuredSkip;

  final sb = Supabase.instance.client;
  final rows = await sb
      .from('creator_takes')
      .select()
      .eq('verdict', 'skip_it')
      .order('created_at', ascending: false)
      .limit(1);

  if (rows.isEmpty) return null;
  return _mapTake(rows.first);
});

/// Resolve a take's content_id to a Content object via the catalog.
final takeContentProvider =
    FutureProvider.family<Content?, int>((ref, contentId) async {
  final catalog = await ref.watch(catalogProvider.future);
  final idStr = contentId.toString();
  return catalog.where((c) => c.id == idStr).firstOrNull;
});

/// Whether the current user is a registered creator.
/// Returns their Creator record if yes, null if not.
final currentCreatorProvider = FutureProvider<Creator?>((ref) async {
  if (!SupabaseConfig.isConfigured) return null;

  final user = ref.watch(currentUserProvider);
  if (user == null) {
    // ignore: avoid_print
    print('[currentCreatorProvider] no user logged in');
    ref.read(isCreatorOverride.notifier).state = false;
    return null;
  }

  // ignore: avoid_print
  print('[currentCreatorProvider] querying creators for user_id=${user.id}');
  final sb = Supabase.instance.client;
  final rows =
      await sb.from('creators').select().eq('user_id', user.id).limit(1);
  // ignore: avoid_print
  print('[currentCreatorProvider] found ${rows.length} rows');
  if (rows.isEmpty) {
    ref.read(isCreatorOverride.notifier).state = false;
    return null;
  }

  // Creators get pro-level access as a perk.
  ref.read(isCreatorOverride.notifier).state = true;
  return _mapCreator(rows.first);
});

/// Submit a new take. Returns true on success.
Future<bool> submitTake({
  required String creatorId,
  required int contentId,
  required String verdict,
  required String body,
}) async {
  try {
    final sb = Supabase.instance.client;
    await sb.from('creator_takes').insert({
      'creator_id': creatorId,
      'content_id': contentId,
      'verdict': verdict,
      'body': body,
    });
    return true;
  } catch (e) {
    // Log the actual error so silent failures become visible.
    // ignore: avoid_print
    print('[submitTake] ERROR: $e');
    return false;
  }
}

/// Edit an existing take. Increments edit_count. Returns true on success.
/// Fails if edit_count is already >= 2.
Future<bool> updateTake({
  required String takeId,
  required String verdict,
  required String body,
  required int currentEditCount,
}) async {
  if (currentEditCount >= 2) return false;
  try {
    final sb = Supabase.instance.client;
    // ignore: avoid_print
    print('[updateTake] updating take=$takeId, editCount=$currentEditCount→${currentEditCount + 1}');
    await sb.from('creator_takes').update({
      'verdict': verdict,
      'body': body,
      'edit_count': currentEditCount + 1,
    }).eq('id', takeId);
    // ignore: avoid_print
    print('[updateTake] success');
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('[updateTake] ERROR: $e');
    return false;
  }
}

/// Delete a take entirely. Returns true on success.
Future<bool> deleteTake({required String takeId}) async {
  try {
    final sb = Supabase.instance.client;
    // ignore: avoid_print
    print('[deleteTake] deleting take=$takeId');
    await sb.from('creator_takes').delete().eq('id', takeId);
    // ignore: avoid_print
    print('[deleteTake] success');
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('[deleteTake] ERROR: $e');
    return false;
  }
}

// ---------------------------------------------------------------------------
// Mappers
// ---------------------------------------------------------------------------

Creator _mapCreator(Map<String, dynamic> r) {
  return Creator(
    id: r['id'] as String,
    alias: r['alias'] as String? ?? '?',
    bio: r['bio'] as String? ?? '',
    specialty: r['specialty'] as String? ?? '',
    avatarUrl: r['avatar_url'] as String?,
    isCurated: r['is_curated'] as bool? ?? false,
    followersCount: r['followers_count'] as int? ?? 0,
  );
}

CreatorTake _mapTake(Map<String, dynamic> r) {
  final verdictStr = r['verdict'] as String? ?? 'worth_it';
  final verdict = switch (verdictStr) {
    'skip_it' => CreatorVerdict.skipIt,
    _ => CreatorVerdict.worthIt,
  };
  return CreatorTake(
    id: r['id'] as String,
    creatorId: r['creator_id'] as String,
    contentId: (r['content_id'] as int).toString(),
    verdict: verdict,
    body: r['body'] as String? ?? '',
    editCount: r['edit_count'] as int? ?? 0,
    createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ??
        DateTime.now(),
  );
}
