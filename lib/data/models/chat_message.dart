/// Chat message model for the AI Chat screen.
///
/// Pre-backend this lives only in memory — messages don't persist across
/// app restarts. When Supabase + real AI land, we'll move to a `chat_messages`
/// table keyed by user_id with a rolling retention policy.

enum ChatSender { user, ai }

class ChatMessage {
  final String id;
  final ChatSender sender;
  final String text;
  final DateTime createdAt;

  /// Optional content IDs the AI is recommending. Rendered as poster chips
  /// under the message bubble so the user can tap through to Content Detail.
  final List<String> recommendedContentIds;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.createdAt,
    this.recommendedContentIds = const [],
  });
}
