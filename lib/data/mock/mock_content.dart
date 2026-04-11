import '../models/content.dart';
import '../models/signals.dart';

/// Mock data para desarrollo de UI sin backend.
/// Reemplazado por SupabaseRepository en Fase 1 del backend.
class MockContent {
  // ---------------------------------------------------------------------------
  // Catálogo base (fuente única para todas las secciones de Home).
  // Cada ítem simula lo que vendrá del Watcher Score real: score, trend, hype,
  // variance, etc. Las secciones de Home son VISTAS (filtros) sobre este pool,
  // mismo patrón que 5 Gems es una vista sobre el catálogo real.
  // ---------------------------------------------------------------------------

  static final List<Content> catalog = [
    // --- Trending / high quality ---
    Content(
      id: 'c-1',
      title: 'The Bear',
      type: ContentType.series,
      year: 2024,
      genres: const ['Drama', 'Comedy'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/8aH9MZDITygx4qPC322xBJuAYns.jpg',
      backdropUrl: '',
      durationMinutes: 30,
      classification: 'TV-MA',
      synopsis:
          'A young chef returns to Chicago to run his family sandwich shop.',
      watcherScore: 91,
      trend: TrendDirection.up,
      hypeLevel: HypeLevel.high,
      dropOffRate: DropOffRate.veryLow,
      trustScore: 94,
      variance: 4,
      imdbScore: 8.6,
      rottenTomatoesCriticsScore: 99,
      metacriticScore: 87,
      traktScore: 8.4,
      socialMentions: 124000,
      tags: const ['intense', 'character-driven', 'binge-worthy'],
      availablePlatforms: const ['Disney+', 'HBO/Max'],
    ),
    Content(
      id: 'c-2',
      title: 'Severance',
      type: ContentType.series,
      year: 2025,
      genres: const ['Sci-Fi', 'Thriller'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg',
      backdropUrl: '',
      durationMinutes: 55,
      classification: 'TV-MA',
      synopsis:
          'Mark leads a team whose memories are surgically divided between work and personal life.',
      watcherScore: 94,
      trend: TrendDirection.exploding,
      hypeLevel: HypeLevel.extreme,
      dropOffRate: DropOffRate.veryLow,
      trustScore: 96,
      variance: 3,
      imdbScore: 8.7,
      rottenTomatoesCriticsScore: 97,
      metacriticScore: 89,
      traktScore: 8.6,
      socialMentions: 287000,
      tags: const ['mind-bending', 'slow burn', 'visually stunning'],
      availablePlatforms: const ['Apple TV+'],
    ),

    // --- Exploding growth ---
    Content(
      id: 'c-3',
      title: 'Shogun',
      type: ContentType.series,
      year: 2024,
      genres: const ['Drama', 'History'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/7O4iVfOMQmdCSxhOg1WnzG1AgYT.jpg',
      backdropUrl: '',
      durationMinutes: 60,
      classification: 'TV-MA',
      synopsis: 'An English navigator becomes a samurai in feudal Japan.',
      watcherScore: 93,
      trend: TrendDirection.exploding,
      hypeLevel: HypeLevel.high,
      dropOffRate: DropOffRate.veryLow,
      trustScore: 95,
      variance: 4,
      imdbScore: 8.7,
      rottenTomatoesCriticsScore: 99,
      metacriticScore: 89,
      traktScore: 8.5,
      socialMentions: 198000,
      tags: const ['epic', 'prestige', 'slow burn'],
      availablePlatforms: const ['Disney+'],
    ),
    Content(
      id: 'c-4',
      title: 'Ripley',
      type: ContentType.series,
      year: 2024,
      genres: const ['Thriller', 'Drama'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/rpSo8z9alultGVTqQ3dkLEyU8xx.jpg',
      backdropUrl: '',
      durationMinutes: 55,
      classification: 'TV-MA',
      synopsis: 'A grifter is hired to travel to Italy to bring a man home.',
      watcherScore: 86,
      trend: TrendDirection.exploding,
      hypeLevel: HypeLevel.medium,
      dropOffRate: DropOffRate.low,
      trustScore: 89,
      variance: 7,
      imdbScore: 7.9,
      rottenTomatoesCriticsScore: 93,
      metacriticScore: 81,
      traktScore: 7.8,
      socialMentions: 42000,
      tags: const ['black and white', 'stylish', 'patient'],
      availablePlatforms: const ['Netflix'],
    ),

    // --- Quick decision (pelis cortas, buenas, listas para hoy) ---
    Content(
      id: 'c-5',
      title: 'The Holdovers',
      type: ContentType.movie,
      year: 2023,
      genres: const ['Drama', 'Comedy'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/VHSzNBTwxV8vh7wylo7O9CLdac.jpg',
      backdropUrl: '',
      durationMinutes: 133,
      classification: 'R',
      synopsis:
          'A curmudgeonly teacher is forced to remain on campus over Christmas break.',
      watcherScore: 87,
      trend: TrendDirection.stable,
      hypeLevel: HypeLevel.medium,
      dropOffRate: DropOffRate.low,
      trustScore: 91,
      variance: 6,
      imdbScore: 7.9,
      rottenTomatoesCriticsScore: 97,
      metacriticScore: 82,
      traktScore: 7.8,
      socialMentions: 29000,
      tags: const ['warm', 'character-driven'],
      availablePlatforms: const ['Peacock'],
    ),
    Content(
      id: 'c-6',
      title: 'Past Lives',
      type: ContentType.movie,
      year: 2023,
      genres: const ['Drama', 'Romance'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/k3waqVXSnvCZWfJYNtdamTgTtTA.jpg',
      backdropUrl: '',
      durationMinutes: 105,
      classification: 'PG-13',
      synopsis: 'Two childhood friends reconnect decades later in New York.',
      watcherScore: 89,
      trend: TrendDirection.stable,
      hypeLevel: HypeLevel.low,
      dropOffRate: DropOffRate.veryLow,
      trustScore: 93,
      variance: 4,
      imdbScore: 7.8,
      rottenTomatoesCriticsScore: 96,
      metacriticScore: 94,
      traktScore: 7.9,
      socialMentions: 21000,
      tags: const ['quiet', 'devastating', 'romantic'],
      availablePlatforms: const ['Paramount+'],
    ),
    Content(
      id: 'c-7',
      title: 'Aftersun',
      type: ContentType.movie,
      year: 2022,
      genres: const ['Drama'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/evKz85EKouVbIr51zy5fOtpNRPg.jpg',
      backdropUrl: '',
      durationMinutes: 102,
      classification: 'R',
      synopsis: 'A father and daughter on holiday in Turkey.',
      watcherScore: 88,
      trend: TrendDirection.stable,
      hypeLevel: HypeLevel.low,
      dropOffRate: DropOffRate.low,
      trustScore: 92,
      variance: 5,
      imdbScore: 7.7,
      rottenTomatoesCriticsScore: 96,
      metacriticScore: 95,
      traktScore: 7.9,
      socialMentions: 18000,
      tags: const ['slow burn', 'emotional', 'visually stunning'],
      availablePlatforms: const ['MUBI'],
    ),

    // --- Clásicos (engine V3: elegibles si awarenessScore < 0.4) ---
    Content(
      id: 'c-classic-1',
      title: 'Blade Runner',
      type: ContentType.movie,
      year: 1982,
      genres: const ['Sci-Fi', 'Neo-Noir', 'Thriller'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/63N9uy8nd9j7Eog2axPQ8lbr3Wj.jpg',
      backdropUrl: '',
      durationMinutes: 117,
      classification: 'R',
      synopsis:
          'A blade runner must pursue and terminate four replicants who stole a ship in space.',
      watcherScore: 92,
      trend: TrendDirection.stable,
      hypeLevel: HypeLevel.low,
      dropOffRate: DropOffRate.low,
      trustScore: 96,
      variance: 3,
      imdbScore: 8.1,
      rottenTomatoesCriticsScore: 89,
      metacriticScore: 84,
      traktScore: 8.0,
      socialMentions: 12000,
      tags: const ['neo-noir', 'atmospheric', 'slow burn', 'blind-spot'],
      availablePlatforms: const ['HBO/Max'],
    ),
    Content(
      id: 'c-classic-2',
      title: 'Heat',
      type: ContentType.movie,
      year: 1995,
      genres: const ['Crime', 'Thriller', 'Drama'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/umSVjVdbVwtx5ryCA2QXL44Durm.jpg',
      backdropUrl: '',
      durationMinutes: 170,
      classification: 'R',
      synopsis:
          'A group of high-end professional thieves start to feel the heat from police when they unknowingly leave a clue.',
      watcherScore: 90,
      trend: TrendDirection.stable,
      hypeLevel: HypeLevel.low,
      dropOffRate: DropOffRate.veryLow,
      trustScore: 94,
      variance: 4,
      imdbScore: 8.3,
      rottenTomatoesCriticsScore: 88,
      metacriticScore: 76,
      traktScore: 8.1,
      socialMentions: 9000,
      tags: const ['slow burn', 'character study', 'tension', 'blind-spot'],
      availablePlatforms: const ['Netflix'],
    ),
    Content(
      id: 'c-classic-3',
      title: 'Eternal Sunshine of the Spotless Mind',
      type: ContentType.movie,
      year: 2004,
      genres: const ['Sci-Fi', 'Romance', 'Drama'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/5MwkWH9tYHv3mV9OdYTMR5qreIz.jpg',
      backdropUrl: '',
      durationMinutes: 108,
      classification: 'R',
      synopsis:
          'When their relationship turns sour, a couple undergoes a procedure to erase each other from their memories.',
      watcherScore: 93,
      trend: TrendDirection.stable,
      hypeLevel: HypeLevel.low,
      dropOffRate: DropOffRate.veryLow,
      trustScore: 95,
      variance: 3,
      imdbScore: 8.3,
      rottenTomatoesCriticsScore: 92,
      metacriticScore: 89,
      traktScore: 8.2,
      socialMentions: 11000,
      tags: const ['emotional', 'mind-bending', 'romantic', 'blind-spot'],
      availablePlatforms: const ['Paramount+'],
    ),

    // --- Don't waste your time (hype alto, score bajo, anti-rec) ---
    Content(
      id: 'c-8',
      title: 'Argylle',
      type: ContentType.movie,
      year: 2024,
      genres: const ['Action', 'Comedy'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/siduVKgOnABO4WH4lOwPQwaGwJp.jpg',
      backdropUrl: '',
      durationMinutes: 139,
      classification: 'PG-13',
      synopsis: 'A reclusive author gets pulled into real-world espionage.',
      watcherScore: 42,
      trend: TrendDirection.down,
      hypeLevel: HypeLevel.extreme,
      dropOffRate: DropOffRate.high,
      trustScore: 58,
      variance: 22,
      imdbScore: 5.7,
      rottenTomatoesCriticsScore: 33,
      metacriticScore: 39,
      traktScore: 5.4,
      socialMentions: 96000,
      tags: const ['bloated', 'tonal mess'],
      availablePlatforms: const ['Apple TV+'],
    ),
    Content(
      id: 'c-9',
      title: 'Madame Web',
      type: ContentType.movie,
      year: 2024,
      genres: const ['Action', 'Superhero'],
      posterUrl: 'https://image.tmdb.org/t/p/w500/rULWuutDcN5NvtiZi4FRPzRYWSh.jpg',
      backdropUrl: '',
      durationMinutes: 116,
      classification: 'PG-13',
      synopsis: 'A paramedic in Manhattan develops clairvoyant abilities.',
      watcherScore: 28,
      trend: TrendDirection.down,
      hypeLevel: HypeLevel.high,
      dropOffRate: DropOffRate.high,
      trustScore: 51,
      variance: 18,
      imdbScore: 3.8,
      rottenTomatoesCriticsScore: 12,
      metacriticScore: 25,
      traktScore: 4.2,
      socialMentions: 78000,
      tags: const ['incoherent', 'troubled production'],
      availablePlatforms: const ['Netflix'],
    ),
  ];

  // ---------------------------------------------------------------------------
  // Vistas / secciones (mismo patrón que usará el backend real).
  // ---------------------------------------------------------------------------

  /// Trending = alto score + hype alto (lo que todo mundo está viendo que además
  /// SÍ vale la pena — diferente de mainstream basura).
  static List<Content> get trending => catalog
      .where((c) =>
          c.watcherScore >= 85 &&
          (c.hypeLevel == HypeLevel.high || c.hypeLevel == HypeLevel.extreme))
      .toList();

  /// Exploding = crecimiento acelerado sostenido.
  static List<Content> get exploding =>
      catalog.where((c) => c.trend == TrendDirection.exploding).toList();

  /// Quick Decision = pelis cortas (<=115 min) con buen score. Para cuando el
  /// usuario quiere decidir rápido y sentarse ya.
  static List<Content> get quickDecision => catalog
      .where((c) =>
          c.type == ContentType.movie &&
          c.durationMinutes <= 115 &&
          c.watcherScore >= 80)
      .toList();

  /// Don't Waste Your Time = hype alto pero watcher score bajo. Anti-rec que
  /// te ahorra la noche. Clave del posicionamiento del producto.
  static List<Content> get dontWaste => catalog
      .where((c) =>
          c.watcherScore < 55 &&
          (c.hypeLevel == HypeLevel.high || c.hypeLevel == HypeLevel.extreme))
      .toList();

  // ---------------------------------------------------------------------------
  // 5 Gems del día (mock) — ya filtrado por el engine en el backend real.
  // ---------------------------------------------------------------------------

  // 5 Gems del día (mock). Mezcla target por engine V3:
  // max 2 clásicos (>5 años) + 3 modernos. Solo incluir clásicos si pasan
  // el bar de awarenessScore < 0.3 para el usuario. En mock asumimos que sí.
  static final List<Gem> dailyGems = [
    Gem(
      content: catalog.firstWhere((c) => c.id == 'c-7'), // Aftersun 2022
      gemRank: 87.4,
      reason:
          'High consensus across Metacritic and Trakt, low hype, completion rate 82%',
      tierVisibility: UserPlan.free,
    ),
    Gem(
      content: catalog.firstWhere((c) => c.id == 'c-6'), // Past Lives 2023
      gemRank: 85.1,
      reason:
          'Critical consensus from independent sources, quiet release, 89% completion',
      tierVisibility: UserPlan.free,
    ),
    Gem(
      content: catalog.firstWhere((c) => c.id == 'c-classic-1'), // Blade Runner 1982
      gemRank: 89.2,
      reason:
          'A 1982 neo-noir classic outside your radar. 94% completion among viewers who discovered it later — matches your slow-burn preference.',
      tierVisibility: UserPlan.pro,
    ),
    Gem(
      content: catalog.firstWhere((c) => c.id == 'c-classic-3'), // Eternal Sunshine 2004
      gemRank: 86.8,
      reason:
          'Blind-spot pick. Quiet 2004 release that metacritic critics and Trakt completion (91%) both validate — matches your emotional drama taste.',
      tierVisibility: UserPlan.pro,
    ),
    Gem(
      content: catalog.firstWhere((c) => c.id == 'c-4'), // Ripley 2024
      gemRank: 84.3,
      reason:
          'Quiet 2024 release. Stylish and patient. 88% completion among those who finished episode 1.',
      tierVisibility: UserPlan.pro,
    ),
  ];

  // ---------------------------------------------------------------------------
  // Señales agregadas por Content ("Remote Fans Say") — mock para Content detail.
  // ---------------------------------------------------------------------------

  static const Map<String, FansSayStats> fansSayByContentId = {
    'c-1': FansSayStats(
        completionRate: 87, worthMyTimePct: 91, avgRating: 4.5, sampleSize: 2140),
    'c-2': FansSayStats(
        completionRate: 92, worthMyTimePct: 94, avgRating: 4.7, sampleSize: 3012),
    'c-3': FansSayStats(
        completionRate: 84, worthMyTimePct: 89, avgRating: 4.4, sampleSize: 1580),
    'c-4': FansSayStats(
        completionRate: 78, worthMyTimePct: 82, avgRating: 4.1, sampleSize: 612),
    'c-5': FansSayStats(
        completionRate: 81, worthMyTimePct: 86, avgRating: 4.2, sampleSize: 430),
    'c-6': FansSayStats(
        completionRate: 89, worthMyTimePct: 93, avgRating: 4.6, sampleSize: 512),
    'c-7': FansSayStats(
        completionRate: 82, worthMyTimePct: 88, avgRating: 4.4, sampleSize: 298),
    'c-8': FansSayStats(
        completionRate: 41, worthMyTimePct: 23, avgRating: 2.3, sampleSize: 1820),
    'c-9': FansSayStats(
        completionRate: 34, worthMyTimePct: 11, avgRating: 1.6, sampleSize: 2401),
    'c-classic-1': FansSayStats(
        completionRate: 94, worthMyTimePct: 96, avgRating: 4.7, sampleSize: 892),
    'c-classic-2': FansSayStats(
        completionRate: 88, worthMyTimePct: 93, avgRating: 4.5, sampleSize: 704),
    'c-classic-3': FansSayStats(
        completionRate: 91, worthMyTimePct: 95, avgRating: 4.6, sampleSize: 1120),
  };

  static FansSayStats? fansSayFor(String contentId) =>
      fansSayByContentId[contentId];

  // ---------------------------------------------------------------------------
  // Quick takes por Content — 2 por título para el layout del detail.
  // En producción estos vienen de `quick_takes` en Supabase paginados.
  // ---------------------------------------------------------------------------

  static final Map<String, List<MockQuickTake>> quickTakesByContentId = {
    'c-classic-1': [
      MockQuickTake(
        id: 'qt-1',
        contentId: 'c-classic-1',
        alias: '@lumen_22',
        body:
            'I put this off for years thinking I knew what it was. I did not know what it was. The vibe alone justifies the runtime.',
        rating: 5,
        worthMyTime: true,
        createdAt: DateTime(2026, 3, 19),
      ),
      MockQuickTake(
        id: 'qt-2',
        contentId: 'c-classic-1',
        alias: '@noirhead',
        body: 'Slower than I expected. Stick with it past minute 40.',
        rating: 4,
        worthMyTime: true,
        createdAt: DateTime(2026, 3, 11),
      ),
    ],
    'c-2': [
      MockQuickTake(
        id: 'qt-3',
        contentId: 'c-2',
        alias: '@midnight_oil',
        body:
            'The show I trust people with. If episode 1 clicks for you, the rest will wreck you.',
        rating: 5,
        worthMyTime: true,
        createdAt: DateTime(2026, 4, 2),
      ),
    ],
    'c-8': [
      MockQuickTake(
        id: 'qt-4',
        contentId: 'c-8',
        alias: '@one_more_film',
        body:
            'Marketing was 9/10, movie was 3/10. Cast is doing their best with a script that does not know what it wants.',
        rating: 2,
        worthMyTime: false,
        createdAt: DateTime(2026, 3, 28),
      ),
    ],
  };

  static List<MockQuickTake> quickTakesFor(String contentId) =>
      quickTakesByContentId[contentId] ?? const [];

  // ---------------------------------------------------------------------------
  // Lookup helper used by Content detail route.
  // ---------------------------------------------------------------------------

  static Content? byId(String id) {
    for (final c in catalog) {
      if (c.id == id) return c;
    }
    return null;
  }
}
