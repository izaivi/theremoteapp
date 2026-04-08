/// Modelos base — portados desde ProductDoc v1.1 sec. 12 + types.ts (AI Studio).
/// V1 sin freezed para que el bootstrap compile sin generar código.
/// En F-3 los migraremos a freezed + json_serializable.

enum ContentType { movie, series }

enum TrendDirection { up, down, stable, exploding }

enum HypeLevel { low, medium, high, extreme }

enum DropOffRate { veryLow, low, medium, high }

enum UserPlan { free, pro }

class WatcherScoreBreakdown {
  final int externalRatings;     // 25%
  final int socialEngagement;    // 20%
  final int growthVelocity;      // 15%
  final int retentionEstimate;   // 15%
  final int creatorOpinion;      // 15%
  final int internalSignals;     // 10% — futuro "Remote Fans Say"

  const WatcherScoreBreakdown({
    required this.externalRatings,
    required this.socialEngagement,
    required this.growthVelocity,
    required this.retentionEstimate,
    required this.creatorOpinion,
    required this.internalSignals,
  });
}

class Content {
  final String id;
  final int? tmdbId;
  final int? watchmodeId;
  final String title;
  final ContentType type;
  final int year;
  final List<String> genres;
  final String posterUrl;
  final String backdropUrl;
  final int durationMinutes;
  final String classification;
  final String synopsis;

  // Watcher Score & related
  final int watcherScore;            // 0-100
  final TrendDirection trend;
  final HypeLevel hypeLevel;
  final DropOffRate dropOffRate;
  final int trustScore;              // 0-100
  final int variance;                // spread entre fuentes (anti-manipulación)

  // External scores (kept for transparency, down-weighted in calc)
  final double? imdbScore;
  final int? rottenTomatoesCriticsScore;
  final int? metacriticScore;
  final double? traktScore;

  // Social
  final int socialMentions;

  // Tags AI-generated
  final List<String> tags;

  // Available platforms in user's region (denormalized for UI speed)
  final List<String> availablePlatforms;

  const Content({
    required this.id,
    this.tmdbId,
    this.watchmodeId,
    required this.title,
    required this.type,
    required this.year,
    required this.genres,
    required this.posterUrl,
    required this.backdropUrl,
    required this.durationMinutes,
    required this.classification,
    required this.synopsis,
    required this.watcherScore,
    required this.trend,
    required this.hypeLevel,
    required this.dropOffRate,
    required this.trustScore,
    required this.variance,
    this.imdbScore,
    this.rottenTomatoesCriticsScore,
    this.metacriticScore,
    this.traktScore,
    required this.socialMentions,
    required this.tags,
    required this.availablePlatforms,
  });
}

class Gem {
  final Content content;
  final double gemRank;
  final String reason;
  final UserPlan tierVisibility;

  const Gem({
    required this.content,
    required this.gemRank,
    required this.reason,
    required this.tierVisibility,
  });
}
