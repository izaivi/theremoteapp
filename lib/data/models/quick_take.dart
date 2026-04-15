/// Quick Take — casual user reactions to content.
///
/// Separate from Creator Takes (editorial reviews with verdict).
/// Quick takes are short (250 chars), have no verdict, and support
/// thumbs up / thumbs down voting.
///
/// Access rules:
///   - Free users: 3 quick takes per day.
///   - Premium users: unlimited.
///   - All authenticated users can vote (thumbs up/down).
///
/// Build 16 — bilingual rendering:
///   `body_en` / `body_es` / `original_language` mirror the pattern
///   already used by `CreatorTake`. The author writes in their UI
///   locale, the `translate-quick-take` Edge Function backfills the
///   opposite column via DeepL, and `localizedBody(locale)` resolves
///   the best text to show with a fallback chain.

class QuickTake {
  final String id;
  final String userId;
  final String contentId;

  /// Legacy column — kept as the final fallback. New takes still write
  /// this for back-compat with any consumer that hasn't been updated.
  final String body;

  /// Translated / authored English rendering. Null until the Edge
  /// Function fills it in (happens a second or two after insert).
  final String? bodyEn;

  /// Translated / authored Spanish rendering. Null until filled in.
  final String? bodyEs;

  /// Source language chosen at compose time. 'en' | 'es'. Authoritative
  /// input for the translate-quick-take Edge Function.
  final String? originalLanguage;

  final int thumbsUp;
  final int thumbsDown;
  final DateTime createdAt;

  /// The current user's vote on this take: 1, -1, or 0 (no vote).
  final int myVote;

  const QuickTake({
    required this.id,
    required this.userId,
    required this.contentId,
    required this.body,
    this.bodyEn,
    this.bodyEs,
    this.originalLanguage,
    this.thumbsUp = 0,
    this.thumbsDown = 0,
    required this.createdAt,
    this.myVote = 0,
  });

  /// Net score (thumbs up minus thumbs down).
  int get score => thumbsUp - thumbsDown;

  /// Returns the take body in the requested language with fallbacks.
  ///
  /// Mirrors `CreatorTake.localizedBody`:
  ///   1. Requested-language column if populated.
  ///   2. Other-language column (better to show *something* readable
  ///      than a blank — happens briefly between insert and the Edge
  ///      Function landing the translation, or if DeepL was down).
  ///   3. Legacy `body`.
  String localizedBody(String? languageCode) {
    final code = (languageCode ?? '').toLowerCase();
    String? primary;
    String? secondary;
    if (code == 'es') {
      primary = bodyEs;
      secondary = bodyEn;
    } else if (code == 'en') {
      primary = bodyEn;
      secondary = bodyEs;
    } else {
      if (originalLanguage == 'es') {
        primary = bodyEs;
        secondary = bodyEn;
      } else {
        primary = bodyEn;
        secondary = bodyEs;
      }
    }
    if (primary != null && primary.trim().isNotEmpty) return primary;
    if (secondary != null && secondary.trim().isNotEmpty) return secondary;
    return body;
  }

  /// True iff the take has a translation in the requested locale (so
  /// the reader is not falling back to the original-language column).
  bool hasTranslationFor(String? languageCode) {
    final code = (languageCode ?? '').toLowerCase();
    if (code == 'es') return bodyEs != null && bodyEs!.trim().isNotEmpty;
    if (code == 'en') return bodyEn != null && bodyEn!.trim().isNotEmpty;
    return false;
  }
}
