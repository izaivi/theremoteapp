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

class QuickTake {
  final String id;
  final String userId;
  final String contentId;
  final String body;
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
    this.thumbsUp = 0,
    this.thumbsDown = 0,
    required this.createdAt,
    this.myVote = 0,
  });

  /// Net score (thumbs up minus thumbs down).
  int get score => thumbsUp - thumbsDown;
}
