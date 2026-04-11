import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
import '../models/quick_take.dart';
import 'auth_repository.dart';

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
      .select()
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

  return rows.map((r) {
    final id = r['id'] as String;
    return QuickTake(
      id: id,
      userId: r['user_id'] as String,
      contentId: (r['content_id'] as int).toString(),
      body: r['body'] as String? ?? '',
      thumbsUp: r['thumbs_up'] as int? ?? 0,
      thumbsDown: r['thumbs_down'] as int? ?? 0,
      createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ??
          DateTime.now(),
      myVote: myVotes[id] ?? 0,
    );
  }).toList();
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
Future<bool> submitQuickTake({
  required String userId,
  required int contentId,
  required String body,
}) async {
  try {
    final sb = Supabase.instance.client;
    // ignore: avoid_print
    print('[submitQuickTake] user=$userId content=$contentId');
    await sb.from('quick_takes').insert({
      'user_id': userId,
      'content_id': contentId,
      'body': body,
    });
    // ignore: avoid_print
    print('[submitQuickTake] success');
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('[submitQuickTake] ERROR: $e');
    return false;
  }
}

/// Vote on a quick take. [vote] is 1 (thumbs up) or -1 (thumbs down).
/// If the user already voted the same way, removes the vote.
Future<bool> voteQuickTake({
  required String quickTakeId,
  required String userId,
  required int vote,
  required int currentVote,
}) async {
  try {
    final sb = Supabase.instance.client;

    if (currentVote == vote) {
      // Un-vote: remove existing vote and decrement counter.
      await sb
          .from('quick_take_votes')
          .delete()
          .eq('quick_take_id', quickTakeId)
          .eq('user_id', userId);
      final field = vote == 1 ? 'thumbs_up' : 'thumbs_down';
      await sb.rpc('decrement_field', params: {
        'table_name': 'quick_takes',
        'row_id': quickTakeId,
        'field_name': field,
      });
      // Simpler: just update with raw SQL-style
      // Actually, let's use a direct update approach
      return true;
    } else {
      // New vote or change direction.
      if (currentVote != 0) {
        // Changing direction: remove old vote counter, add new.
        final oldField = currentVote == 1 ? 'thumbs_up' : 'thumbs_down';
        final newField = vote == 1 ? 'thumbs_up' : 'thumbs_down';
        // Update vote record
        await sb
            .from('quick_take_votes')
            .update({'vote': vote})
            .eq('quick_take_id', quickTakeId)
            .eq('user_id', userId);
        // Update counters (increment new, decrement old)
        final take = await sb
            .from('quick_takes')
            .select('thumbs_up, thumbs_down')
            .eq('id', quickTakeId)
            .single();
        await sb.from('quick_takes').update({
          oldField: (take[oldField] as int) - 1,
          newField: (take[newField] as int) + 1,
        }).eq('id', quickTakeId);
      } else {
        // Fresh vote.
        await sb.from('quick_take_votes').insert({
          'quick_take_id': quickTakeId,
          'user_id': userId,
          'vote': vote,
        });
        final field = vote == 1 ? 'thumbs_up' : 'thumbs_down';
        final take = await sb
            .from('quick_takes')
            .select('thumbs_up, thumbs_down')
            .eq('id', quickTakeId)
            .single();
        await sb.from('quick_takes').update({
          field: (take[field] as int) + 1,
        }).eq('id', quickTakeId);
      }
      return true;
    }
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
