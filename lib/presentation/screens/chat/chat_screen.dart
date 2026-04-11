import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/mock/mock_ai_responses.dart';
import '../../../data/mock/mock_content.dart';
import '../../../data/models/chat_message.dart';
import '../../../data/models/content.dart';
import '../../../data/repositories/catalog_provider.dart';
import '../../../data/repositories/chat_quota_repository.dart';
import '../../../data/repositories/creators_provider.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../data/repositories/ratings_repository.dart';
import '../../../data/repositories/vault_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/paywall_sheet.dart';

/// Ask Remoty — streaming companion powered by the catalog, vault,
/// and creator takes. Rule-based intent detection, no AI API needed.
///
/// Free users: 5 questions/day (quota tracked in `ChatQuotaRepository`,
/// resets at local midnight). On exhaustion the input locks and a paywall
/// banner appears — tap → `showPaywall`.
///
/// Pro users: unlimited (quota display reads "Unlimited").
///
/// Bilingual EN/ES — Remoty detects user locale and responds accordingly.

/// Persists chat messages across tab switches via Riverpod.
final _chatMessagesProvider =
    StateProvider<List<ChatMessage>>((ref) => []);
final _chatThinkingProvider = StateProvider<bool>((ref) => false);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || ref.read(_chatThinkingProvider)) return;

    final isPro = ref.read(isProProvider);

    // Pro (paid or creator) bypasses the quota entirely.
    if (!isPro) {
      final allowed = await ref.read(chatQuotaProvider.notifier).consume();
      if (!allowed) {
        if (mounted) showPaywall(context);
        return;
      }
    }

    ref.read(_chatMessagesProvider.notifier).update((msgs) => [
          ...msgs,
          ChatMessage(
            id: 'u-${DateTime.now().microsecondsSinceEpoch}',
            sender: ChatSender.user,
            text: text,
            createdAt: DateTime.now(),
          ),
        ]);
    _controller.clear();
    ref.read(_chatThinkingProvider.notifier).state = true;
    _scrollToBottom();

    // Simulate latency — Remoty "thinks" for a moment.
    await Future<void>.delayed(const Duration(milliseconds: 650));

    // Detect locale for bilingual responses.
    final isSpanish = mounted &&
        (Localizations.localeOf(context).languageCode == 'es');

    // Build engine with real data from Supabase providers.
    final catalog =
        ref.read(catalogProvider).valueOrNull ?? MockContent.catalog;
    final vault = ref.read(vaultProvider);
    final takes = ref.read(latestTakesProvider).valueOrNull ?? [];

    final userRatings = ref.read(ratingsProvider);

    final engine = RemotypEngine(
      catalog: catalog,
      lovedIds: vault.loved,
      watchlistIds: vault.watchlist,
      notForMeIds: vault.notForMe,
      creatorTakes: takes,
      ratings: userRatings,
    );
    final reply = engine.reply(text, spanish: isSpanish);

    if (!mounted) return;
    ref.read(_chatMessagesProvider.notifier).update((msgs) => [
          ...msgs,
          ChatMessage(
            id: 'a-${DateTime.now().microsecondsSinceEpoch}',
            sender: ChatSender.ai,
            text: reply.text,
            createdAt: DateTime.now(),
            recommendedContentIds: reply.contentIds,
          ),
        ]);
    ref.read(_chatThinkingProvider.notifier).state = false;
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _clearConversation() async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          l10n.chatClearTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          l10n.chatClearBody,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.chatClearCancel,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.chatClearConfirm,
              style: const TextStyle(
                color: Color(0xFFE5484D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      ref.read(_chatMessagesProvider.notifier).state = [];
    }
  }

  void _showGuideSheet() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/mascots/mascot_ask.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surfaceElevated,
                          ),
                          child: const Icon(Icons.smart_toy,
                              size: 18, color: Color(0xFF4F8CFF)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.chatGuideTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [
                    _guideCategory(
                      icon: Icons.mood_outlined,
                      title: l10n.chatGuideCategory1Title,
                      description: l10n.chatGuideCategory1Desc,
                      examples: [
                        l10n.chatQuickShort,
                        l10n.chatQuickBinge,
                        l10n.chatQuickSad,
                      ],
                    ),
                    _guideCategory(
                      icon: Icons.bookmark_outline,
                      title: l10n.chatGuideCategory2Title,
                      description: l10n.chatGuideCategory2Desc,
                      examples: [l10n.chatQuickVault],
                    ),
                    _guideCategory(
                      icon: Icons.star_outline,
                      title: l10n.chatGuideCategory5Title,
                      description: l10n.chatGuideCategory5Desc,
                      examples: [l10n.chatQuickRanking],
                    ),
                    _guideCategory(
                      icon: Icons.movie_filter_outlined,
                      title: l10n.chatGuideCategory3Title,
                      description: l10n.chatGuideCategory3Desc,
                      examples: [l10n.chatQuickCreators],
                    ),
                    _guideCategory(
                      icon: Icons.devices_outlined,
                      title: l10n.chatGuideCategory4Title,
                      description: l10n.chatGuideCategory4Desc,
                      examples: const [
                        'Netflix picks',
                        'What\'s on Max?',
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guideCategory({
    required IconData icon,
    required String title,
    required String description,
    required List<String> examples,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF4F8CFF)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4F8CFF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.6),
              height: 1.4,
            ),
          ),
          if (examples.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: examples.map((e) => GestureDetector(
                onTap: () {
                  Navigator.of(context).pop(); // close sheet
                  _send(e);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F8CFF).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF4F8CFF).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    e,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF4F8CFF),
                    ),
                  ),
                ),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Trigger creator check — sets isCreatorOverride → isProProvider.
    ref.watch(currentCreatorProvider);
    final isPro = ref.watch(isProProvider);
    final quota = ref.watch(chatQuotaProvider);
    final exhausted = !isPro && quota.exhausted;
    final messages = ref.watch(_chatMessagesProvider);
    final thinking = ref.watch(_chatThinkingProvider);

    return SafeArea(
      child: Column(
        children: [
          // ---- Header ----
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.chatTitle,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.chatTagline,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                // Remoty avatar
                ClipOval(
                  child: Image.asset(
                    'assets/mascots/mascot_ask.png',
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 36),
                  ),
                ),
                const SizedBox(width: 8),
                // Guide button
                _HeaderIconButton(
                  icon: Icons.help_outline_rounded,
                  tooltip: l10n.chatGuideTitle,
                  onTap: _showGuideSheet,
                ),
                const SizedBox(width: 6),
                // Clear conversation button (only shown when there are messages)
                if (messages.isNotEmpty)
                  _HeaderIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: l10n.chatClearTitle,
                    onTap: _clearConversation,
                  )
                else
                  _QuotaBadge(
                    label: isPro
                        ? l10n.chatQuotaPro
                        : l10n.chatQuotaRemaining(quota.remaining),
                    isPro: isPro,
                    exhausted: exhausted,
                  ),
              ],
            ),
          ),

          // ---- Messages area ----
          Expanded(
            child: messages.isEmpty
                ? _EmptyState(onQuickTap: _send)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: messages.length + (thinking ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (thinking && i == messages.length) {
                        return const _ThinkingBubble();
                      }
                      return _MessageBubble(message: messages[i]);
                    },
                  ),
          ),

          // ---- Exhausted banner ----
          if (exhausted) _ExhaustedBanner(),

          // ---- Input ----
          _ChatInput(
            controller: _controller,
            enabled: !exhausted && !thinking,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header icon button (guide / clear)
// ---------------------------------------------------------------------------

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withOpacity(0.06),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 18, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quota badge
// ---------------------------------------------------------------------------

class _QuotaBadge extends StatelessWidget {
  final String label;
  final bool isPro;
  final bool exhausted;
  const _QuotaBadge({
    required this.label,
    required this.isPro,
    required this.exhausted,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPro
        ? AppColors.accent
        : exhausted
            ? const Color(0xFFE5484D)
            : const Color(0xFF4F8CFF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPro ? Icons.workspace_premium : Icons.bolt,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — Remoty mascot + quick-prompt chips
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final void Function(String) onQuickTap;
  const _EmptyState({required this.onQuickTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final quicks = <(IconData, String)>[
      (Icons.timer_outlined, l10n.chatQuickShort),
      (Icons.weekend_outlined, l10n.chatQuickBinge),
      (Icons.favorite_border, l10n.chatQuickSad),
      (Icons.block, l10n.chatQuickSkip),
      (Icons.bookmark_outline, l10n.chatQuickVault),
      (Icons.star_outline, l10n.chatQuickRanking),
      (Icons.movie_filter_outlined, l10n.chatQuickCreators),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Center(
          child: Image.asset(
            'assets/mascots/mascot_ask.png',
            width: 140,
            height: 140,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withOpacity(0.35),
                    const Color(0xFF4F8CFF).withOpacity(0.2),
                  ],
                ),
                border: Border.all(
                  color: AppColors.accent.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.smart_toy,
                  color: Colors.white, size: 38),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          l10n.chatEmptyTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.chatEmptyBody,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (final q in quicks)
              _QuickChip(
                icon: q.$1,
                label: q.$2,
                onTap: () => onQuickTap(q.$2),
              ),
          ],
        ),
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: const Color(0xFF4F8CFF)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class _MessageBubble extends ConsumerWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.sender == ChatSender.user;
    const blue = Color(0xFF4F8CFF);
    final catalog =
        ref.watch(catalogProvider).valueOrNull ?? MockContent.catalog;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Remoty avatar for bot messages
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/mascots/mascot_ask.png',
                      width: 22,
                      height: 22,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceElevated,
                        ),
                        child: const Icon(Icons.smart_toy,
                            size: 12, color: blue),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Remoty',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: blue,
                    ),
                  ),
                ],
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                gradient: isUser
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [blue, blue.withOpacity(0.8)],
                      )
                    : null,
                color: isUser
                    ? null
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft:
                      isUser ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight:
                      isUser ? const Radius.circular(4) : const Radius.circular(16),
                ),
                border: isUser
                    ? null
                    : Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: _FormattedText(text: message.text, isUser: isUser),
            ),
          ),
          if (message.recommendedContentIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: message.recommendedContentIds.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final id = message.recommendedContentIds[i];
                  final content = catalog.cast<Content?>().firstWhere(
                      (c) => c?.id == id,
                      orElse: () => MockContent.byId(id));
                  if (content == null) return const SizedBox.shrink();
                  return _RecommendationCard(
                    id: id,
                    title: content.title,
                    year: content.year,
                    score: content.watcherScore,
                    posterUrl: content.posterUrl,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Minimal bold parser: splits on `**…**` and bolds those segments.
class _FormattedText extends StatelessWidget {
  final String text;
  final bool isUser;
  const _FormattedText({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 14,
      height: 1.4,
      color: isUser ? Colors.white : Colors.white.withOpacity(0.92),
    );
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*');
    int cursor = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final String id;
  final String title;
  final int year;
  final int score;
  final String posterUrl;
  const _RecommendationCard({
    required this.id,
    required this.title,
    required this.year,
    required this.score,
    required this.posterUrl,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/content/$id'),
      child: SizedBox(
        width: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    posterUrl.isEmpty
                        ? Container(color: Colors.white12)
                        : Image.network(
                            posterUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: Colors.white12),
                          ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$score',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4F8CFF),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            Text(
              '$year',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thinking bubble (animated dots)
// ---------------------------------------------------------------------------

class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble();
  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Remoty label above thinking bubble
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/mascots/mascot_search.png',
                      width: 22,
                      height: 22,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceElevated,
                        ),
                        child: const Icon(Icons.smart_toy,
                            size: 12, color: Color(0xFF4F8CFF)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Remoty',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4F8CFF),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (i) {
                      final phase = (_ctrl.value + i * 0.18) % 1.0;
                      final scale = 0.6 + 0.6 * (1 - (phase - 0.5).abs() * 2);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4F8CFF),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Exhausted banner
// ---------------------------------------------------------------------------

class _ExhaustedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withOpacity(0.22),
            Theme.of(context).colorScheme.surface,
          ],
        ),
        border: Border.all(color: AppColors.accent.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.smart_toy, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.chatQuotaExhaustedTitle,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.chatQuotaExhaustedBody,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => showPaywall(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------

class _ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final void Function(String) onSend;
  const _ChatInput({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: enabled ? onSend : null,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: l10n.chatInputHint,
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: Color(0xFF4F8CFF)),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: enabled ? const Color(0xFF4F8CFF) : Colors.white10,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? () => onSend(controller.text) : null,
              child: const Padding(
                padding: EdgeInsets.all(13),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
