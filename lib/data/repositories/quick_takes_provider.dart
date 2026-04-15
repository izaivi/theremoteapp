import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
import '../models/quick_take.dart';
import 'auth_repository.dart';
import 'blocks_repository.dart';

/// ------------------------------------------------------------------
/// Quick Takes provider — user reactions (separate from Creator Takes)
/// ------------------------------------------------------------------

/// Quick takes for a specific content, sorted by score (best first).
final quickTakesByContentProvider =
    FutureProvider.family<List<QuickTake>, String>((ref, contentId) async {
  if (!SupabaseConfig.isConfigured) return [];

  final sb = Supabase.instance.client;
  final cid = int.tryParse(contentId);
  if (cid == null) return [];

  final rows = await sb
      .from('quick_takes')
      // Build 16 — pull bilingual columns so _QuickTakeCard can call
      // `localizedBody(locale)` instead of showing the raw source text.
      .select(
        'id, user_id, content_id, body, body_en, body_es, '
        'original_language, thumbs_up, thumbs_down, created_at',
      )
      .eq('content_id', cid)
      .order('thumbs_up', ascending: false)
      .order('created_at', ascending: false);

  final user = ref.watch(currentUserProvider);

  // If logged in, also fetch this user's votes for these takes.
  Map<String, int> myVotes = {};
  if (user != null && rows.isNotEmpty) {
    final takeIds = rows.map((r) => r['id'] as String).toList();
    final voteRows = await sb
        .from('quick_take_votes')
        .select()
        .eq('user_id', user.id)
        .inFilter('quick_take_id', takeIds);
    for (final v in voteRows) {
      myVotes[v['quick_take_id'] as String] = v['vote'] as int;
    }
  }

  // Build 16 — hide quick takes authored by a user I've blocked. The
  // current user's own quick takes are shown regardless.
  final blocked = ref.watch(blocksProvider);

  return rows
      .where((r) {
        final authorId = r['user_id'] as String?;
        if (authorId == null) return true;
        return !blocked.contains(authorId);
      })
      .map((r) {
        final id = r['id'] as String;
        return QuickTake(
          id: id,
          userId: r['user_id'] as String,
          contentId: (r['content_id'] as int).toString(),
          body: r['body'] as String? ?? '',
          bodyEn: r['body_en'] as String?,
          bodyEs: r['body_es'] as String?,
          originalLanguage: r['original_language'] as String?,
          thumbsUp: r['thumbs_up'] as int? ?? 0,
          thumbsDown: r['thumbs_down'] as int? ?? 0,
          createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ??
              DateTime.now(),
          myVote: myVotes[id] ?? 0,
        );
      })
      .toList();
});

/// How many quick takes the current user has posted today.
final quickTakesTodayCountProvider = FutureProvider<int>((ref) async {
  if (!SupabaseConfig.isConfigured) return 0;

  final user = ref.watch(currentUserProvider);
  if (user == null) return 0;

  final sb = Supabase.instance.client;
  final today = DateTime.now().toUtc();
  final startOfDay =
      DateTime.utc(today.year, today.month, today.day).toIso8601String();

  final rows = await sb
      .from('quick_takes')
      .select('id')
      .eq('user_id', user.id)
      .gte('created_at', startOfDay);

  return rows.length;
});

/// Submit a quick take. Returns true on success.
///
/// Build 16 — [originalLanguage] ('en' | 'es') is taken from the app's
/// active UI locale at compose time. We write the body into both the
/// legacy `body` column (back-compat) AND the matching language column,
/// so readers in the original locale see the exact authored text even
/// before the translate-quick-take Edge Function lands the other side.
Future<bool> submitQuickTake({
  required String userId,
  required int contentId,
  required String body,
  required String originalLanguage, // 'en' | 'es'
}) async {
  try {
    final sb = Supabase.instance.client;
    // ignore: avoid_print
    print(
      '[submitQuickTake] user=$userId content=$contentId lang=$originalLanguage',
    );

    final payload = <String, dynamic>{
      'user_id': userId,
      'content_id': contentId,
      'body': body,
      'original_language': originalLanguage,
    };
    // Mirror body into the matching language column so the locale-aware
    // reader has something to show in the original locale immediately.
    payload[originalLanguage == 'es' ? 'body_es' : 'body_en'] = body;

    final inserted = await sb
        .from('quick_takes')
        .insert(payload)
        .select('id')
        .single();
    final newId = inserted['id'] as String?;
    // ignore: avoid_print
    print('[submitQuickTake] success id=$newId');
    if (newId != null) {
      // Fire-and-forget: don't block UX waiting on DeepL. If the call
      // fails, the take still renders in its original language; a
      // manual retry or subsequent edit will cover the translation.
      _invokeTranslateQuickTake(newId);
    }
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('[submitQuickTake] ERROR: $e');
    return false;
  }
}

/// Vote on a quick take. [vote] is 1 (thumbs up) or -1 (thumbs down).
/// If the user already voted the same way, removes the vote.
///
/// Counter updates (thumbs_up / thumbs_down on quick_takes) are handled
/// by a Supabase trigger on quick_take_votes — the Flutter code only
/// needs to manage the vote row itself.
Future<bool> voteQuickTake({
  required String quickTakeId,
  required String userId,
  required int vote,
  required int currentVote,
}) async {
  try {
    final sb = Supabase.instance.client;

    if (currentVote == vote) {
      // Un-vote: delete the vote row → trigger decrements counter.
      await sb
          .from('quick_take_votes')
          .delete()
          .eq('quick_take_id', quickTakeId)
          .eq('user_id', userId);
    } else if (currentVote != 0) {
      // Changing direction: update vote → trigger adjusts both counters.
      await sb
          .from('quick_take_votes')
          .update({'vote': vote})
          .eq('quick_take_id', quickTakeId)
          .eq('user_id', userId);
    } else {
      // Fresh vote: insert → trigger increments counter.
      await sb.from('quick_take_votes').insert({
        'quick_take_id': quickTakeId,
        'user_id': userId,
        'vote': vote,
      });
    }
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('[voteQuickTake] ERROR: $e');
    return false;
  }
}

/// Delete a quick take (own only). Returns true on success.
Future<bool> deleteQuickTake({required String quickTakeId}) async {
  try {
    final sb = Supabase.instance.client;
    await sb.from('quick_takes').delete().eq('id', quickTakeId);
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('[deleteQuickTake] ERROR: $e');
    return false;
  }
}

/// Fire-and-forget invocation of the translate-quick-take Edge Function.
///
/// Build 16 — runs in the background after a quick take insert. The
/// caller doesn't await this: the take is already persisted and shows
/// in its original language; the translation backfills the other side
/// a second or two later. Failures are logged and swallowed so a flaky
/// DeepL response never blocks the compose flow.
///
/// Auth context is taken from the active Supabase session — the Edge
/// Function checks that `quick_takes.user_id == auth.uid()` (403 else).
void _invokeTranslateQuickTake(String quickTakeId) {
  () async {
    try {
      final sb = Supabase.instance.client;
      // Auth: explicit Authorization header using the current user
      // session's access token. See the matching comment in
      // `creators_provider._invokeTranslateTake` for the full reason
      // — the SDK's implicit auth attachment is unreliable enough that
      // all of Build 16's translations silently 401'd in prod.
      final session = sb.auth.currentSession;
      if (session == null) {
        // ignore: avoid_print
        print('[translateQuickTake] id=$quickTakeId SKIP: no active session');
        return;
      }
      final res = await sb.functions.invoke(
        'translate-quick-take',
        body: {'quick_take_id': quickTakeId},
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      // ignore: avoid_print
      print(
        '[translateQuickTake] id=$quickTakeId status=${res.status} data=${res.data}',
      );
    } catch (e) {
      // ignore: avoid_print
      print('[translateQuickTake] id=$quickTakeId ERROR: $e');
    }
  }();
}
