/// Creator & CreatorTake models.
///
/// A Creator is a trusted voice in Flixscope. V1 supports a mix of:
///   - **Curated critics**: manually whitelisted by the team (Letterboxd-
///     inspired). Carry an `isCurated = true` badge.
///   - **Power users**: organic app users promoted by the system once
///     they hit quality thresholds (not implemented yet — `isCurated = false`
///     for now acts as a placeholder).
///
/// A CreatorTake is an editorial review by a creator about specific content.
/// Only two verdicts — creators commit to a clear position:
///   - [CreatorVerdict.worthIt]: positive, "watch it".
///   - [CreatorVerdict.skipIt]: negative, "NOT worth your time".
///
/// Quick takes (casual user reactions) are a SEPARATE system — see
/// `quick_take.dart`.

enum CreatorVerdict { worthIt, skipIt }

class Creator {
  final String id;
  final String alias;
  final String bio;

  /// Optional CDN URL. Null → render initials avatar.
  final String? avatarUrl;

  /// Short specialty label: "Horror", "Sci-Fi", "Indie", etc.
  final String specialty;

  /// True if this creator was whitelisted by the team.
  final bool isCurated;

  /// Mock follower count (will come from backend later).
  final int followersCount;

  /// Build 16 — the `auth.users.id` that owns this creator profile.
  /// Nullable because curated-critic stubs that don't map to a real user
  /// exist (we control that row manually for system creators). Populated
  /// from `creators.user_id` when present. Needed for UGC moderation:
  /// reports and blocks live at the auth-user level, not at creator level,
  /// so we resolve creator → user_id when the user taps Block on a profile.
  final String? userId;

  const Creator({
    required this.id,
    required this.alias,
    required this.bio,
    required this.specialty,
    this.avatarUrl,
    this.isCurated = false,
    this.followersCount = 0,
    this.userId,
  });
}

class CreatorTake {
  final String id;
  final String creatorId;
  final String contentId;
  final CreatorVerdict verdict;

  /// Legacy single-language body. Pre-Build 16 column. Still populated by
  /// the trigger / older clients and used as the ultimate fallback when
  /// neither `bodyEn` nor `bodyEs` carries the active locale.
  final String body;

  /// English version of the take (Build 16+). Either authored directly by
  /// the creator (when `originalLanguage == 'en'`) or filled in by the
  /// `translate-take` Edge Function. Null until the function lands or the
  /// creator writes the EN side manually.
  final String? bodyEn;

  /// Spanish version of the take (Build 16+). Mirror of `bodyEn`.
  final String? bodyEs;

  /// Which language the creator actually wrote. The Edge Function preserves
  /// this side and translates the other. `null` for legacy takes that
  /// predate Build 16 (those rows were backfilled from the `body` column,
  /// which Vivi's founder takes happened to be in English).
  final String? originalLanguage;

  final int editCount;
  final DateTime createdAt;

  const CreatorTake({
    required this.id,
    required this.creatorId,
    required this.contentId,
    required this.verdict,
    required this.body,
    this.bodyEn,
    this.bodyEs,
    this.originalLanguage,
    this.editCount = 0,
    required this.createdAt,
  });

  /// Whether this take can still be edited (max 2 edits).
  bool get canEdit => editCount < 2;

  /// Remaining edits.
  int get editsRemaining => 2 - editCount;

  /// Returns the take body in the requested language, with fallbacks.
  ///
  /// Resolution order for `languageCode == 'es'`:
  ///   1. `bodyEs` if present and non-empty
  ///   2. `bodyEn` if present and non-empty (better to show *something*
  ///      readable than a blank — happens briefly between insert and the
  ///      Edge Function landing the translation, or if DeepL was down)
  ///   3. legacy `body`
  ///
  /// Mirror order for `languageCode == 'en'`. Any other code falls back
  /// to the original-language column when available, otherwise `body`.
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
      // Unknown locale — prefer original-language column, then either side.
      if (originalLanguage == 'es') {
        primary = bodyEs; secondary = bodyEn;
      } else {
        primary = bodyEn; secondary = bodyEs;
      }
    }
    if (primary != null && primary.trim().isNotEmpty) return primary;
    if (secondary != null && secondary.trim().isNotEmpty) return secondary;
    return body;
  }

  /// True iff a translation is available in the requested locale (i.e. the
  /// reader does NOT need to fall back to the original-language column).
  /// Useful for showing a small "translated by AI / shown in original
  /// language" indicator in the future.
  bool hasTranslationFor(String? languageCode) {
    final code = (languageCode ?? '').toLowerCase();
    if (code == 'es') return bodyEs != null && bodyEs!.trim().isNotEmpty;
    if (code == 'en') return bodyEn != null && bodyEn!.trim().isNotEmpty;
    return false;
  }
}
