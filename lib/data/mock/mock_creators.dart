import '../models/creator.dart';

/// Seed creators — replaced by Supabase repository in a later fase.
///
/// @izaivi is the founding creator (Vivi / Punky Tiger Labs).
/// Other placeholders will be replaced as real users join the beta.
class MockCreators {
  static final List<Creator> creators = [
    // --- Founding creator ---
    const Creator(
      id: 'cr-1',
      alias: '@izaivi',
      bio:
          'Founder of Flixscope. I watch everything so you don\'t have to. '
          'Anime, K-drama, prestige TV, true crime, and comfort rewatches.',
      specialty: 'Everything',
      isCurated: true,
      followersCount: 0,
    ),
  ];

  /// Seed takes — kept minimal until real takes are submitted via the app.
  /// These will eventually come from Supabase `creator_takes` table.
  static final List<CreatorTake> takes = [
    // @izaivi's takes — set the tone for the beta.
    CreatorTake(
      id: 'ct-1',
      creatorId: 'cr-1',
      contentId: 'ct-placeholder-1',
      verdict: CreatorVerdict.worthIt,
      body:
          'Welcome to Flixscope! This is where you\'ll find honest takes from real watchers. '
          'No sponsored content, no algorithms hiding the good stuff.',
      createdAt: DateTime(2026, 4, 10),
    ),
  ];

  // -------- helpers --------

  static Creator? byId(String id) {
    for (final c in creators) {
      if (c.id == id) return c;
    }
    return null;
  }

  static List<CreatorTake> takesBy(String creatorId) =>
      takes.where((t) => t.creatorId == creatorId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Latest takes feed, newest first.
  static List<CreatorTake> get latestTakes =>
      [...takes]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Featured skip — newest `skipIt` take. Drives the "Not worth your time"
  /// hero card at the top of the Creators screen.
  static CreatorTake? get featuredSkip {
    final skips = takes.where((t) => t.verdict == CreatorVerdict.skipIt).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return skips.isEmpty ? null : skips.first;
  }
}
