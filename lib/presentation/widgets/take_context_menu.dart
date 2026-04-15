import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/reports_repository.dart';
import '../../l10n/app_localizations.dart';
import 'report_sheet.dart';

/// Small ⋯ menu button used on every piece of user-generated content
/// (quick takes, creator takes, creator profile headers).
///
/// Build 16 — Apple UGC compliance. Always offers **Report**; optionally
/// offers **Block** when the caller provides [onBlock]. The caller is
/// responsible for wiring Block to the blocks repository + confirm dialog
/// because block target resolution differs per surface (e.g. blocking a
/// quick take author vs. a creator needs different user_id lookups).
///
/// This widget is intentionally tiny — no state beyond the sheet itself.
class TakeContextMenuButton extends StatelessWidget {
  /// Which kind of target this menu acts on — routes into content_reports.
  final ReportTargetType targetType;

  /// DB id of the target (uuid as string for takes; creator.id for profile).
  final String targetId;

  /// Optional block handler. When null the Block row is not shown — useful
  /// for surfaces where blocking doesn't apply (e.g., own content, or the
  /// user isn't signed in).
  final VoidCallback? onBlock;

  /// Optional colour for the ⋯ glyph. Defaults to muted white.
  final Color? iconColor;

  const TakeContextMenuButton({
    super.key,
    required this.targetType,
    required this.targetId,
    this.onBlock,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.more_horiz, size: 20, color: iconColor ?? Colors.white54),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: 'More',
      onPressed: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showModalBottomSheet<_MenuAction>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.white70),
                title: Text(l10n.reportAction,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.of(sheetCtx).pop(_MenuAction.report),
              ),
              if (onBlock != null)
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.redAccent),
                  title: Text(l10n.blockAction,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.redAccent)),
                  onTap: () => Navigator.of(sheetCtx).pop(_MenuAction.block),
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case _MenuAction.report:
        await showReportSheet(
          context,
          targetType: targetType,
          targetId: targetId,
        );
        return;
      case _MenuAction.block:
        onBlock?.call();
        return;
    }
  }
}

enum _MenuAction { report, block }
