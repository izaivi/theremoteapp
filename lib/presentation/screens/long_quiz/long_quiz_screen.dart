import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/mock/mock_content.dart';
import '../../../data/models/content.dart';
import '../../../data/repositories/catalog_provider.dart';
import '../../../data/repositories/ratings_repository.dart';
import '../../../data/repositories/vault_repository.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../l10n/app_localizations.dart';

/// Long Quiz — second, optional onboarding phase.
///
/// Unlocks `classicDiscoveryBoost` + real awareness scoring in the engine.
/// Two steps in v1:
///   1. **Tri-state grid**: every catalog tile cycles not-seen → seen → loved.
///      "seen" IDs bootstrap `awarenessScore`, "loved" IDs also feed
///      `lovedRecentIds` as strong taste signal.
///   2. **Themes**: free-text field (comma-separated tags). Directors,
///      moods, keywords. Empty is allowed.
///
/// Accessible from Profile, Discover banner, and eventually an auto-prompt.
class LongQuizScreen extends ConsumerStatefulWidget {
  const LongQuizScreen({super.key});

  @override
  ConsumerState<LongQuizScreen> createState() => _LongQuizScreenState();
}

enum _TileState { none, seen, loved }

class _LongQuizScreenState extends ConsumerState<LongQuizScreen> {
  int _step = 0;
  final Map<String, _TileState> _tiles = {};
  final TextEditingController _themes = TextEditingController();

  /// Retake mode: entered from Settings → "Change my preferences"
  /// (URL has `?retake=1`). When true, pre-fill tiles + themes from
  /// the current profile / vault, and on finish return to /settings
  /// with a SnackBar instead of the celebratory home redirect.
  bool _retake = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final retake =
          GoRouterState.of(context).uri.queryParameters['retake'] == '1';
      if (!retake) return;

      final profile = ref.read(userProfileProvider);
      final vault = ref.read(vaultProvider);

      setState(() {
        _retake = true;
        // Pre-fill themes from the stored favoriteThemes.
        _themes.text = profile.favoriteThemes.join(', ');
        // Pre-fill tri-state grid: tiles in watchedIds start as `seen`,
        // and those currently marked loved in the vault upgrade to `loved`.
        // Catalog tiles that aren't in watchedIds stay `none`.
        for (final id in profile.watchedIds) {
          _tiles[id] = vault.isLoved(id) ? _TileState.loved : _TileState.seen;
        }
      });
    });
  }

  @override
  void dispose() {
    _themes.dispose();
    super.dispose();
  }

  void _cycle(String id) {
    setState(() {
      final cur = _tiles[id] ?? _TileState.none;
      _tiles[id] = switch (cur) {
        _TileState.none => _TileState.seen,
        _TileState.seen => _TileState.loved,
        _TileState.loved => _TileState.none,
      };
    });
  }

  Future<void> _finish() async {
    final seenIds = _tiles.entries
        .where((e) => e.value != _TileState.none)
        .map((e) => e.key)
        .toList();
    final lovedIds = _tiles.entries
        .where((e) => e.value == _TileState.loved)
        .map((e) => e.key)
        .toList();
    final themes = _themes.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    await ref.read(userProfileProvider.notifier).completeLongQuiz(
          QuizAnswers(
            favoriteGenres: ref.read(userProfileProvider).favoriteGenres,
            seenCanonIds: seenIds,
            lovedRecentIds: lovedIds,
            favoriteThemes: themes,
          ),
        );

    // The ❤️ taps in the grid are a strong taste signal — mirror them into
    // the Vault (as "loved") and into Ratings (as 5★) so the user sees
    // their picks reflected in their library right away. Without this, the
    // long quiz feels disconnected from the rest of the app: Home still
    // shows the same 5 Gems the user just told us they don't care about.
    final vault = ref.read(vaultProvider.notifier);
    final ratings = ref.read(ratingsProvider.notifier);
    for (final id in lovedIds) {
      // toggleLoved only adds if not already loved — idempotent.
      if (!ref.read(vaultProvider).isLoved(id)) {
        await vault.toggleLoved(id);
      }
      await ratings.setRating(id, 5);
    }

    if (!mounted) return;

    if (_retake) {
      // Refresh Home taste rows immediately; skip the celebratory dialog
      // (the user came from Settings with intent, not first-time wow).
      invalidateTasteRows(ref);
      final messenger = ScaffoldMessenger.of(context);
      context.go('/settings');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Preferences updated'),
            duration: Duration(seconds: 2),
          ),
        );
      });
      return;
    }

    _showDoneAndPop();
  }

  void _showDoneAndPop() {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/mascots/mascot_celebrate.png',
              width: 120,
              height: 120,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.auto_awesome,
                      color: AppColors.accent, size: 48),
            ),
            const SizedBox(height: 8),
            Text(l10n.longQuizDoneTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(l10n.longQuizDoneBody, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/home');
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final catalogAsync = ref.watch(catalogProvider);
    final catalog = catalogAsync.valueOrNull ?? MockContent.catalog;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.longQuizTitle),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              l10n.longQuizSkip,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // --- Step indicator ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  for (var i = 0; i < 2; i++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= _step
                              ? AppColors.accent
                              : Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // --- Body per step ---
            Expanded(
              child: _step == 0
                  ? _buildGridStep(catalog, l10n)
                  : _buildThemesStep(l10n),
            ),

            // --- Footer nav ---
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: () => setState(() => _step -= 1),
                      child: Text(l10n.longQuizBack),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _step == 0
                        ? () => setState(() => _step = 1)
                        : _finish,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    child: Text(
                        _step == 0 ? l10n.longQuizNext : l10n.longQuizFinish),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Step 1: grid ----------------

  Widget _buildGridStep(List<Content> catalog, AppLocalizations l10n) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.longQuizStepGrid,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.longQuizStepGridSub,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                // Legend
                Row(
                  children: [
                    _LegendDot(
                      icon: Icons.check,
                      color: const Color(0xFF4F8CFF),
                      label: l10n.longQuizLegendSeen,
                    ),
                    const SizedBox(width: 14),
                    _LegendDot(
                      icon: Icons.favorite,
                      color: const Color(0xFFE5484D),
                      label: l10n.longQuizLegendLoved,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.58,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final c = catalog[i];
                final state = _tiles[c.id] ?? _TileState.none;
                return _CanonTile(
                  content: c,
                  state: state,
                  onTap: () => _cycle(c.id),
                );
              },
              childCount: catalog.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }

  // ---------------- Step 2: themes ----------------

  Widget _buildThemesStep(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.longQuizStepThemes,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.longQuizStepThemesSub,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).textTheme.bodySmall?.color,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _themes,
            maxLines: 5,
            minLines: 3,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: l10n.longQuizThemesHint,
              hintStyle: TextStyle(
                fontSize: 13,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              contentPadding: const EdgeInsets.all(14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Canon tile (poster + tri-state overlay)
// ---------------------------------------------------------------------------

class _CanonTile extends StatelessWidget {
  final Content content;
  final _TileState state;
  final VoidCallback onTap;
  const _CanonTile({
    required this.content,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const seenColor = Color(0xFF4F8CFF);
    const lovedColor = Color(0xFFE5484D);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: switch (state) {
              _TileState.none => Colors.white.withOpacity(0.08),
              _TileState.seen => seenColor,
              _TileState.loved => lovedColor,
            },
            width: state == _TileState.none ? 1 : 2,
          ),
          boxShadow: state == _TileState.none
              ? null
              : [
                  BoxShadow(
                    color: (state == _TileState.loved ? lovedColor : seenColor)
                        .withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Poster
              content.posterUrl.isEmpty
                  ? Container(color: Colors.white12)
                  : Image.network(
                      content.posterUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: Colors.white12),
                    ),
              // Dim when not selected to make selected tiles pop
              if (state == _TileState.none)
                Container(color: Colors.black.withOpacity(0.35)),

              // Title footer
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.8),
                      ],
                    ),
                  ),
                  child: Text(
                    content.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              // State badge
              if (state != _TileState.none)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: state == _TileState.loved
                          ? lovedColor
                          : seenColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      state == _TileState.loved
                          ? Icons.favorite
                          : Icons.check,
                      size: 13,
                      color: Colors.white,
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

class _LegendDot extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _LegendDot({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, size: 11, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }
}
