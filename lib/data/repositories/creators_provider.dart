import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
import '../mock/mock_creators.dart';
import '../models/content.dart';
import '../models/creator.dart';
import 'auth_repository.dart';
import 'blocks_repository.dart';
import 'catalog_provider.dart';
import 'user_profile_repository.dart';

/// ------------------------------------------------------------------
/// Creators provider — reads from Supabase `creators` + `creator_takes`
/// when connected, falls back to mock data in local-only mode.
/// ------------------------------------------------------------------

/// All creators, sorted by followers (descending).
///
/// Build 16 — watches `blocksProvider` so blocking a creator instantly
/// removes them from the grid everywhere without any manual invalidation.
/// Own creator profile (if any) is never filtered.
final creatorsProvider = FutureProvider<List<Creator>>((ref) async {
  if (!SupabaseConfig.isConfigured) return MockCreators.creators;

  final sb = Supabase.instance.client;
  final rows = await sb
      .from('creators')
      .select()
      .order('followers_count', ascending: false);

  final blocked = ref.watch(blocksProvider);
  return rows
      .map(_mapCreator)
      .where((c) => c.userId == null || !blocked.contains(c.userId))
      .toList();
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
///
/// Build 16 — filters out takes authored by blocked creators. The map of
/// creator_id → user_id is loaded up front so the filter runs without
/// another round-trip per take. Watching `blocksProvider` makes this
/// reactive: a new block immediately drops that creator's takes from the
/// feed. Takes whose creator row no longer exists (shouldn't happen with
/// the FK constraint, but defensive) fall through the filter unchanged.
final latestTakesProvider = FutureProvider<List<CreatorTake>>((ref) async {
  if (!SupabaseConfig.isConfigured) return MockCreators.latestTakes;

  final sb = Supabase.instance.client;
  final rows = await sb
      .from('creator_takes')
      .select()
      .order('created_at', ascending: false)
      .limit(50);

  final takes = rows.map(_mapTake).toList();
  final blocked = ref.watch(blocksProvider);
  if (blocked.isEmpty) return takes;

  final creators = await ref.watch(creatorsProvider.future);
  final creatorUserIds = <String, String?>{
    for (final c in creators) c.id: c.userId,
  };
  return takes.where((t) {
    final uid = creatorUserIds[t.creatorId];
    return uid == null || !blocked.contains(uid);
  }).toList();
});

/// Takes by a specific creator.
///
/// Build 16 — if the creator is blocked we return empty. Keeps the detail
/// screen consistent with the grid (the Block button on the creator profile
/// already hides the profile content; this guards the edge case where a
/// deep link lands on a blocked creator's takes list).
final takesByCreatorProvider =
    FutureProvider.family<List<CreatorTake>, String>((ref, creatorId) async {
  if (!SupabaseConfig.isConfigured) return MockCreators.takesBy(creatorId);

  final sb = Supabase.instance.client;
  final rows = await sb
      .from('creator_takes')
      .select()
      .eq('creator_id', creatorId)
      .order('created_at', ascending: false);

  final takes = rows.map(_mapTake).toList();
  final blocked = ref.watch(blocksProvider);
  if (blocked.isEmpty) return takes;

  // Resolve this creator's user_id to decide if we should hide everything.
  final creator = await ref.watch(creatorByIdProvider(creatorId).future);
  if (creator?.userId != null && blocked.contains(creator!.userId)) {
    return const <CreatorTake>[];
  }
  return takes;
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
///
/// Build 16 — bilingual takes:
///   * `originalLanguage` ('en' or 'es') is stored on the row so the
///     `translate-take` Edge Function knows which side the creator
///     authored and which side it must fill in.
///   * The body goes into BOTH `body` (legacy column, kept for fallback)
///     AND `body_<originalLanguage>` (new column the locale-aware reader
///     prefers) in a single insert. This means new takes render correctly
///     in their original language immediately, even before DeepL responds.
///   * After the insert succeeds we kick off the translate-take Edge
///     Function fire-and-forget. If it fails (DeepL down, quota exceeded,
///     network blip) the take simply stays single-language; the reader
///     falls back to whichever side is populated. A future retry mechanism
///     can re-invoke for `body_<other> IS NULL` rows.
Future<bool> submitTake({
  required String creatorId,
  required int contentId,
  required String verdict,
  required String body,
  required String originalLanguage, // 'en' | 'es' — Build 16
}) async {
  try {
    final sb = Supabase.instance.client;
    final payload = <String, dynamic>{
      'creator_id': creatorId,
      'content_id': contentId,
      'verdict': verdict,
      'body': body,
      'original_language': originalLanguage,
    };
    // Mirror body into the matching language column so the locale-aware
    // reader has something to show in the original locale immediately.
    payload[originalLanguage == 'es' ? 'body_es' : 'body_en'] = body;

    final inserted = await sb
        .from('creator_takes')
        .insert(payload)
        .select('id')
        .single();
    final newId = inserted['id'] as String?;
    if (newId != null) {
      // Fire-and-forget: don't block UX waiting on DeepL.
      _invokeTranslateTake(newId);
    }
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
///
/// Build 16 — bilingual takes:
///   * The new body overwrites both `body` (legacy) and
///     `body_<originalLanguage>` (so the original-language column always
///     reflects what the creator actually wrote).
///   * The OPPOSITE column is **wiped to NULL** so the Edge Function will
///     re-translate it on the next invocation. Without this wipe, the
///     skip-rule "target_already_filled" would refuse to retranslate and
///     the user would see a stale translation that no longer matches the
///     edited original. (Vivi's manual ES translations are protected
///     differently: they only get wiped if Vivi herself edits the EN.)
///   * The translate-take Edge Function runs fire-and-forget afterwards.
Future<bool> updateTake({
  required String takeId,
  required String verdict,
  required String body,
  required int currentEditCount,
  required String originalLanguage, // 'en' | 'es' — Build 16
}) async {
  if (currentEditCount >= 2) return false;
  try {
    final sb = Supabase.instance.client;
    // ignore: avoid_print
    print('[updateTake] updating take=$takeId, editCount=$currentEditCount→${currentEditCount + 1}');
    final patch = <String, dynamic>{
      'verdict': verdict,
      'body': body,
      'edit_count': currentEditCount + 1,
      'original_language': originalLanguage,
    };
    if (originalLanguage == 'es') {
      patch['body_es'] = body;
      patch['body_en'] = null; // force retranslation
    } else {
      patch['body_en'] = body;
      patch['body_es'] = null; // force retranslation
    }
    await sb.from('creator_takes').update(patch).eq('id', takeId);
    // ignore: avoid_print
    print('[updateTake] success');
    _invokeTranslateTake(takeId);
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('[updateTake] ERROR: $e');
    return false;
  }
}

/// Fire-and-forget invocation of the translate-take Edge Function.
///
/// Build 16 — runs in the background after a take insert/update. The
/// caller doesn't await this: the take is already persisted and shows in
/// the creator's original language; the translation backfills the other
/// side a second or two later. Failures are logged and swallowed so a
/// flaky DeepL response never blocks the create/edit flow.
///
/// Auth: we pass the user's session JWT **explicitly** in the
/// Authorization header. Without this the supabase_flutter SDK falls
/// back to the anon key when the session cache isn't fresh enough on
/// the underlying functions client, and the Edge Function rejects that
/// with 401 at `userClient.auth.getUser(jwt)` (this was the Build 16
/// bug — all 11 of Vivi's takes silently skipped translation).
///
/// Edge Function then checks `take.creator_id == auth.uid()` (403 else).
void _invokeTranslateTake(String takeId) {
  () async {
    try {
      final sb = Supabase.instance.client;
      final session = sb.auth.currentSession;
      if (session == null) {
        // ignore: avoid_print
        print('[translateTake] take=$takeId SKIP: no active session');
        return;
      }
      final res = await sb.functions.invoke(
        'translate-take',
        body: {'take_id': takeId},
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      // ignore: avoid_print
      print('[translateTake] take=$takeId status=${res.status} data=${res.data}');
    } catch (e) {
      // ignore: avoid_print
      print('[translateTake] take=$takeId ERROR: $e');
    }
  }();
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
    // Build 16 — pulled through so Block / Report flows can resolve this
    // creator to an auth user id. Null for system-seeded curated critics.
    userId: r['user_id'] as String?,
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
    // Build 16 — bilingual columns. Nullable on the row because the
    // `translate-take` Edge Function fills the non-original side
    // asynchronously, and brand-new takes appear with only one side
    // populated until DeepL responds. The locale-aware getter on the model
    // (`localizedBody`) handles the fallback chain.
    bodyEn: r['body_en'] as String?,
    bodyEs: r['body_es'] as String?,
    originalLanguage: r['original_language'] as String?,
    editCount: r['edit_count'] as int? ?? 0,
    createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ??
        DateTime.now(),
  );
}
