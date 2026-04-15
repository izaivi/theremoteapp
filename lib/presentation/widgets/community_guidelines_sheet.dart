import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/community_guidelines_repository.dart';
import '../../l10n/app_localizations.dart';

/// Build 16 — Apple App Store Guideline 1.2 (UGC) compliance.
///
/// One-time Community Guidelines acceptance shown the first time the
/// user tries to publish ANY take (quick or creator). Short summary of
/// prohibited conduct + a single Accept CTA. On accept we stamp
/// `profiles.community_guidelines_accepted_at` and this sheet is never
/// shown again for that account.
///
/// Call [ensureCommunityGuidelinesAccepted] from publishing entry points.
/// Returns `true` when the user can proceed (already accepted, or just
/// tapped Accept in the sheet), `false` if they dismissed it.
Future<bool> ensureCommunityGuidelinesAccepted(
  BuildContext context,
  WidgetRef ref,
) async {
  // Already accepted — skip the sheet entirely.
  if (ref.read(communityGuidelinesAcceptedProvider)) return true;

  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true, // allow tap-outside; Cancel still exits via false
    backgroundColor: const Color(0xFF1A1A1F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _CommunityGuidelinesSheet(),
  );
  return accepted ?? false;
}

class _CommunityGuidelinesSheet extends ConsumerStatefulWidget {
  const _CommunityGuidelinesSheet();

  @override
  ConsumerState<_CommunityGuidelinesSheet> createState() =>
      _CommunityGuidelinesSheetState();
}

class _CommunityGuidelinesSheetState
    extends ConsumerState<_CommunityGuidelinesSheet> {
  bool _working = false;

  Future<void> _accept() async {
    setState(() => _working = true);
    await ref.read(communityGuidelinesAcceptedProvider.notifier).accept();
    if (!mounted) return;
    // Always pop true — even if the server write failed the local state
    // is flipped, and the compose flow can continue without re-prompting.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              l10n.guidelinesSheetTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.guidelinesSheetSubtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            // Five short rules — the classic UGC set Apple looks for.
            _Rule(
              icon: Icons.block,
              text: l10n.guidelinesRuleHarassment,
            ),
            _Rule(
              icon: Icons.warning_amber_rounded,
              text: l10n.guidelinesRuleObjectionable,
            ),
            _Rule(
              icon: Icons.campaign_outlined,
              text: l10n.guidelinesRuleSpam,
            ),
            _Rule(
              icon: Icons.person_outline,
              text: l10n.guidelinesRuleImpersonation,
            ),
            _Rule(
              icon: Icons.copyright,
              text: l10n.guidelinesRuleIp,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => context.push('/legal/guidelines'),
              child: Text(
                l10n.guidelinesReadFull,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.accent.withOpacity(0.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _working
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(l10n.guidelinesCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _working ? null : _accept,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _working
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            l10n.guidelinesAccept,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Rule({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
