import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/reports_repository.dart';
import '../../l10n/app_localizations.dart';

/// Modal bottom sheet that captures a report on any reportable target.
///
/// Build 16 — Apple UGC compliance. Used from the ⋯ menu on quick takes,
/// creator takes, and creator profile headers.
///
/// Usage:
/// ```dart
/// await showReportSheet(
///   context,
///   targetType: ReportTargetType.creatorTake,
///   targetId: take.id,
/// );
/// ```
///
/// Returns `true` if the report landed successfully (including when the
/// user was told they already reported this target — from their POV, it's
/// "done"). Returns `false` on error so the caller can decide whether to
/// surface a retry affordance.
Future<bool> showReportSheet(
  BuildContext context, {
  required ReportTargetType targetType,
  required String targetId,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A1F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
    ),
  );
  return ok ?? false;
}

class _ReportSheet extends ConsumerStatefulWidget {
  final ReportTargetType targetType;
  final String targetId;

  const _ReportSheet({
    required this.targetType,
    required this.targetId,
  });

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  ReportReason? _reason;
  final _noteCtrl = TextEditingController();
  bool _submitting = false;
  String? _noteError;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (_reason == null) return;

    // When reason=other, note is required. Apple reviewers appreciate the
    // signal that "Other" reports have context rather than being a noisy
    // catch-all bucket.
    final note = _noteCtrl.text.trim();
    if (_reason == ReportReason.other && note.isEmpty) {
      setState(() => _noteError = l10n.reportNoteRequiredError);
      return;
    }

    setState(() {
      _submitting = true;
      _noteError = null;
    });

    final result = await ref.read(reportsRepositoryProvider).submit(
          targetType: widget.targetType,
          targetId: widget.targetId,
          reason: _reason!,
          note: note.isEmpty ? null : note,
        );

    if (!mounted) return;

    switch (result) {
      case SubmitReportResult.ok:
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.reportSuccess)),
        );
        return;
      case SubmitReportResult.duplicate:
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.reportDuplicate)),
        );
        return;
      case SubmitReportResult.error:
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.reportError)),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final noteRequired = _reason == ReportReason.other;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                l10n.reportSheetTitle,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.reportSheetSubtitle,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              _reasonTile(ReportReason.spam, l10n.reportReasonSpam),
              _reasonTile(
                  ReportReason.harassment, l10n.reportReasonHarassment),
              _reasonTile(ReportReason.hate, l10n.reportReasonHate),
              _reasonTile(ReportReason.other, l10n.reportReasonOther),
              const SizedBox(height: 14),
              TextField(
                controller: _noteCtrl,
                maxLines: 3,
                maxLength: 300,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: noteRequired
                      ? l10n.reportNoteRequiredLabel
                      : l10n.reportNoteLabel,
                  errorText: _noteError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_noteError != null) setState(() => _noteError = null);
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed:
                      (_reason == null || _submitting) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          l10n.reportSubmit,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reasonTile(ReportReason reason, String label) {
    final selected = _reason == reason;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _submitting ? null : () => setState(() => _reason = reason),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withOpacity(0.12)
                : Colors.white.withOpacity(0.03),
            border: Border.all(
              color: selected
                  ? AppColors.accent
                  : Colors.white.withOpacity(0.1),
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? AppColors.accent : Colors.white54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? Colors.white : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
