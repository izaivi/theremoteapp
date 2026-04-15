import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Target kinds that can be reported. Kept in sync with the CHECK constraint
/// on `public.content_reports.target_type` (Migration 2026-04-15).
enum ReportTargetType {
  quickTake,
  creatorTake,
  creatorProfile;

  /// DB-side string value (matches CHECK constraint).
  String get db => switch (this) {
        ReportTargetType.quickTake => 'quick_take',
        ReportTargetType.creatorTake => 'creator_take',
        ReportTargetType.creatorProfile => 'creator_profile',
      };
}

/// Report reasons offered to the user. Limited to 4 per Vivi's decision
/// (Build 16) — Spam, Harassment, Hate, Other. Keep this list aligned with
/// the CHECK constraint on `public.content_reports.reason`.
enum ReportReason {
  spam,
  harassment,
  hate,
  other;

  String get db => switch (this) {
        ReportReason.spam => 'spam',
        ReportReason.harassment => 'harassment',
        ReportReason.hate => 'hate',
        ReportReason.other => 'other',
      };
}

/// Result of `submitReport`. The UI uses this to show the right toast —
/// success, "already reported" (duplicate), or generic error.
enum SubmitReportResult { ok, duplicate, error }

/// Thin wrapper around the `content_reports` insert.
///
/// Build 16 — Apple UGC compliance. One report per user per target is
/// enforced by the unique index `uniq_report_per_user_target`. When a
/// duplicate is attempted Supabase returns a 23505 PostgreSQL error;
/// we map that to [SubmitReportResult.duplicate] so the UI can show
/// "you already reported this" instead of a scary generic error.
///
/// Email notification to hello@punkytigerlabs.com is deferred to Build 17
/// — for now Vivi reviews the `content_reports` table directly.
class ReportsRepository {
  Future<SubmitReportResult> submit({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String? note,
  }) async {
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) {
        // Unauthenticated users shouldn't reach the report UI — but guard
        // anyway to avoid a confusing RLS violation.
        return SubmitReportResult.error;
      }
      await sb.from('content_reports').insert({
        'reporter_id': uid,
        'target_type': targetType.db,
        'target_id': targetId,
        'reason': reason.db,
        'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
      });
      return SubmitReportResult.ok;
    } on PostgrestException catch (e) {
      // 23505 = unique_violation on (reporter_id, target_type, target_id).
      if (e.code == '23505') return SubmitReportResult.duplicate;
      if (kDebugMode) debugPrint('[reports] submit error: $e');
      return SubmitReportResult.error;
    } catch (e) {
      if (kDebugMode) debugPrint('[reports] submit unexpected: $e');
      return SubmitReportResult.error;
    }
  }
}

final reportsRepositoryProvider =
    Provider<ReportsRepository>((ref) => ReportsRepository());
