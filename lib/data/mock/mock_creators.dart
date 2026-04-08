import '../models/creator.dart';

/// Mock creators + takes. Replaced by Supabase repository later.
///
/// Mix: curated critics (isCurated = true) + power users (isCurated = false).
/// Content IDs must exist in `MockContent.catalog`.
class MockCreators {
  static final List<Creator> creators = [
    // --- Curated critics ---
    const Creator(
      id: 'cr-1',
      alias: '@lumen_22',
      bio: 'Slow cinema, neo-noir, and anything shot on film. Patient watcher.',
      specialty: 'Neo-Noir',
      isCurated: true,
      followersCount: 12400,
    ),
    const Creator(
      id: 'cr-2',
      alias: '@midnight_oil',
      bio: 'Prestige TV obsessive. I will die on the Severance hill.',
      specialty: 'Prestige TV',
      isCurated: true,
      followersCount: 9800,
    ),
    const Creator(
      id: 'cr-3',
      alias: '@noirhead',
      bio: 'Crime, thrillers, and the occasional heist. Heat is a religion.',
      specialty: 'Crime',
      isCurated: true,
      followersCount: 7200,
    ),
    const Creator(
      id: 'cr-4',
      alias: '@quiet_frames',
      bio: 'Indie dramas, intimate stories, devastating endings. Aftersun changed me.',
      specialty: 'Indie Drama',
      isCurated: true,
      followersCount: 5100,
    ),

    // --- Power users ---
    const Creator(
      id: 'cr-5',
      alias: '@one_more_film',
      bio: 'Four movies a week minimum. Low patience for marketing hype.',
      specialty: 'Everything',
      isCurated: false,
      followersCount: 2300,
    ),
    const Creator(
      id: 'cr-6',
      alias: '@popcorn_judge',
      bio: 'Unfiltered takes on blockbusters. If it insults my intelligence, you\'ll know.',
      specialty: 'Blockbusters',
      isCurated: false,
      followersCount: 1800,
    ),
  ];

  static final List<CreatorTake> takes = [
    // --- SKIP IT (featured "Not worth your time") ---
    CreatorTake(
      id: 'ct-1',
      creatorId: 'cr-6',
      contentId: 'c-9', // Madame Web
      verdict: CreatorVerdict.skipIt,
      body:
          'Marketing had me curious. Five minutes in I wanted my time back. Incoherent script, wasted cast. Skip it — genuinely.',
      createdAt: DateTime(2026, 4, 6),
    ),
    CreatorTake(
      id: 'ct-2',
      creatorId: 'cr-5',
      contentId: 'c-8', // Argylle
      verdict: CreatorVerdict.skipIt,
      body:
          'Bloated, tonally confused, and 30 minutes too long. The trailer is the best version of this movie.',
      createdAt: DateTime(2026, 4, 3),
    ),

    // --- WORTH IT ---
    CreatorTake(
      id: 'ct-3',
      creatorId: 'cr-2',
      contentId: 'c-2', // Severance
      verdict: CreatorVerdict.worthIt,
      body:
          'The show I trust people with. If episode 1 clicks for you, the rest will wreck you in the best way.',
      createdAt: DateTime(2026, 4, 7),
    ),
    CreatorTake(
      id: 'ct-4',
      creatorId: 'cr-1',
      contentId: 'c-classic-1', // Blade Runner
      verdict: CreatorVerdict.worthIt,
      body:
          'I put this off for years thinking I knew what it was. I did not. The vibe alone justifies the runtime.',
      createdAt: DateTime(2026, 4, 5),
    ),
    CreatorTake(
      id: 'ct-5',
      creatorId: 'cr-4',
      contentId: 'c-7', // Aftersun
      verdict: CreatorVerdict.worthIt,
      body:
          'Quiet, patient, devastating. You\'ll be thinking about the last ten minutes for weeks.',
      createdAt: DateTime(2026, 4, 4),
    ),
    CreatorTake(
      id: 'ct-6',
      creatorId: 'cr-3',
      contentId: 'c-classic-2', // Heat
      verdict: CreatorVerdict.worthIt,
      body:
          'Every frame is a masterclass in how to build tension. Pacino and De Niro in that diner is still the ceiling.',
      createdAt: DateTime(2026, 4, 2),
    ),

    // --- QUICK TAKE (neutral) ---
    CreatorTake(
      id: 'ct-7',
      creatorId: 'cr-2',
      contentId: 'c-3', // Shogun
      verdict: CreatorVerdict.quickTake,
      body:
          'Gorgeous and patient. If you bounced off prestige slow burns before, this might not convert you — but it deserves the try.',
      createdAt: DateTime(2026, 4, 1),
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
