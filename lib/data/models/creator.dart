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

  const Creator({
    required this.id,
    required this.alias,
    required this.bio,
    required this.specialty,
    this.avatarUrl,
    this.isCurated = false,
    this.followersCount = 0,
  });
}

class CreatorTake {
  final String id;
  final String creatorId;
  final String contentId;
  final CreatorVerdict verdict;
  final String body;
  final int editCount;
  final DateTime createdAt;

  const CreatorTake({
    required this.id,
    required this.creatorId,
    required this.contentId,
    required this.verdict,
    required this.body,
    this.editCount = 0,
    required this.createdAt,
  });

  /// Whether this take can still be edited (max 2 edits).
  bool get canEdit => editCount < 2;

  /// Remaining edits.
  int get editsRemaining => 2 - editCount;
}
