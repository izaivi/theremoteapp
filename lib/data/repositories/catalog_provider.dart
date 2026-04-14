import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/prefs/language_prefs.dart';
import '../../core/supabase/supabase_client.dart';
import '../mock/mock_content.dart';
import '../models/content.dart';
import '../models/user_profile.dart';
import 'auth_repository.dart';
import 'user_profile_repository.dart';

/// ------------------------------------------------------------------
/// Catalog provider — reads from Supabase `content` + `content_availability`
/// when connected, falls back to mock data when running in local-only mode.
/// ------------------------------------------------------------------

/// Full catalog loaded once per session (or when country/auth-state changes).
/// Screens apply their own filters/sorts on top.
///
/// Watching `authStateChangesProvider` ensures we re-fetch after the user
/// signs in — fixes the "empty Home on first launch" bug where the provider
/// fires before the auth session is established.
final catalogProvider = FutureProvider<List<Content>>((ref) async {
  // Re-run whenever auth state changes (sign-in, sign-out, token refresh).
  ref.watch(authStateChangesProvider);

  if (!SupabaseConfig.isConfigured) return MockContent.catalog;

  final country = ref.watch(effectiveCountryProvider);
  final sb = Supabase.instance.client;

  // 1. Fetch all content rows (sorted by popularity).
  final contentRows = await sb
      .from('content')
      .select()
      .order('tmdb_popularity', ascending: false)
      .limit(600);

  // 2. Fetch availability for user's country.
  final availRows = await sb
      .from('content_availability')
      .select('content_id, platform_id, monetization_type')
      .eq('country_code', country);

  // 3. Fetch platforms for name lookup.
  final platformRows = await sb.from('platforms').select('id, name');
  final platformNames = <int, String>{
    for (final p in platformRows) (p['id'] as int): p['name'] as String,
  };

  // 4. Build availability index: tmdb_id → set of platform names.
  final availByContent = <int, Set<String>>{};
  for (final a in availRows) {
    final cid = a['content_id'] as int;
    final pid = a['platform_id'] as int;
    final name = platformNames[pid] ?? '?';
    availByContent.putIfAbsent(cid, () => {}).add(name);
  }

  // 5. Map DB rows to Content model.
  return contentRows
      .map((r) => _mapRowToContent(r, availByContent))
      .toList();
});

/// Single content by tmdb_id — used by content detail screen.
final contentByIdProvider =
    FutureProvider.family<Content?, String>((ref, id) async {
  if (!SupabaseConfig.isConfigured) return MockContent.byId(id);

  // `id` arrives as String from route params. Could be a tmdb_id (int) or
  // old mock id like "c-1".
  final tmdbId = int.tryParse(id);
  if (tmdbId == null) return MockContent.byId(id);

  final country = ref.watch(effectiveCountryProvider);
  final sb = Supabase.instance.client;

  final rows =
      await sb.from('content').select().eq('tmdb_id', tmdbId).limit(1);
  if (rows.isEmpty) return null;

  final availRows = await sb
      .from('content_availability')
      .select('content_id, platform_id, monetization_type')
      .eq('content_id', tmdbId)
      .eq('country_code', country);

  final platformRows = await sb.from('platforms').select('id, name');
  final platformNames = <int, String>{
    for (final p in platformRows) (p['id'] as int): p['name'] as String,
  };

  final availByContent = <int, Set<String>>{};
  for (final a in availRows) {
    final cid = a['content_id'] as int;
    final pid = a['platform_id'] as int;
    final name = platformNames[pid] ?? '?';
    availByContent.putIfAbsent(cid, () => {}).add(name);
  }

  return _mapRowToContent(rows.first, availByContent);
});

// ---------------------------------------------------------------------------
// Convenience "view" providers — same pattern as MockContent static getters
// but reading from the catalog provider.
// ---------------------------------------------------------------------------

/// Trending = top by TMDB popularity, filtered by user's active platforms.
final trendingProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  final profile = ref.watch(userProfileProvider);
  return catalog
      .where((c) => _matchesPlatforms(c, profile))
      .take(20)
      .toList();
});

/// Exploding = recent + high popularity spike (heuristic: release_year recent
/// + high popularity). Placeholder until we have real trend signals.
final explodingProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  final profile = ref.watch(userProfileProvider);
  final now = DateTime.now().year;
  return catalog
      .where((c) =>
          c.year >= now - 1 &&
          c.tmdbId != null &&
          _matchesPlatforms(c, profile))
      .take(15)
      .toList();
});

/// Quick decision = movies under 115 min, sorted by popularity.
final quickDecisionProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  final profile = ref.watch(userProfileProvider);
  return catalog
      .where((c) =>
          c.type == ContentType.movie &&
          c.durationMinutes <= 115 &&
          _matchesPlatforms(c, profile))
      .take(15)
      .toList();
});

/// Don't waste = lowest scored content with some popularity (anti-rec).
/// Placeholder: titles with low imdb scores but high popularity.
/// Platform-agnostic on purpose — the warning applies regardless of where it
/// streams.
final dontWasteProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  final withScores = catalog.where((c) => c.imdbScore != null && c.imdbScore! < 5.5).toList()
    ..sort((a, b) => (a.imdbScore ?? 0).compareTo(b.imdbScore ?? 0));
  return withScores.take(10).toList();
});

/// Daily gems = the 5 personalized picks for Home.
///
/// Composite score (IMDb, RT, Metacritic, TMDB/Watcher) with a ≥2-source
/// quality gate, a creator-take 1.5x boost, plus a profile bonus for genre
/// overlap, favoriteThemes matches (director/cast), and sessionLength fit.
///
/// The final 5 are picked with a deterministic daily shuffle over the top 30,
/// seeded by `hash(userId + date)` — same user sees the same 5 all day, new 5
/// tomorrow. Cascading fallback drops the quality gate, then the platform
/// filter, if the pool is too thin.
final dailyGemsProvider = FutureProvider<List<Gem>>((ref) async {
  if (!SupabaseConfig.isConfigured) return MockContent.dailyGems;

  final catalog = await ref.watch(catalogProvider.future);
  final profile = ref.watch(userProfileProvider);

  // Creator takes with is_curated=true → 1.5x boost on composite score.
  final Set<int> curatedTmdbIds = {};
  try {
    final sb = Supabase.instance.client;
    final takes = await sb
        .from('creator_takes')
        .select('content_id, creators!inner(is_curated)')
        .eq('creators.is_curated', true);
    for (final t in (takes as List)) {
      final cid = t['content_id'];
      if (cid is int) curatedTmdbIds.add(cid);
    }
  } catch (_) {
    // Boost, not a requirement — continue without it.
  }

  // Exclude already-watched (Long Quiz seed + runtime) and dismissed titles.
  final excluded = {...profile.watchedIds, ...profile.dismissedIds};

  bool baseFilter(Content c) =>
      !excluded.contains(c.id) && _matchesPlatforms(c, profile);

  // Pool 1: platform + quality gate.
  List<Content> candidates =
      catalog.where((c) => baseFilter(c) && _passesQualityGate(c)).toList();

  // Cascade 1: drop quality gate if pool is thin.
  if (candidates.length < 15) {
    candidates = catalog.where(baseFilter).toList();
  }
  // Cascade 2: drop platform filter if pool is still thin.
  if (candidates.length < 5) {
    candidates = catalog.where((c) => !excluded.contains(c.id)).toList();
  }
  // Last resort: unfiltered.
  if (candidates.isEmpty) {
    candidates = List<Content>.from(catalog);
  }

  double scoreOf(Content c) {
    double base = _compositeScore(c);
    if (curatedTmdbIds.contains(c.tmdbId)) base *= 1.5;
    return base + _profileBonus(c, profile);
  }

  candidates.sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
  final top = candidates.take(30).toList();

  // Daily rotation: deterministic shuffle seeded by user+date.
  final now = DateTime.now();
  final dateKey =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final seed = (profile.id ?? 'anon').hashCode ^ dateKey.hashCode;
  top.shuffle(math.Random(seed));
  final chosen = top.take(5).toList()
    ..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));

  return chosen.indexed.map((e) {
    final (i, c) = e;
    final hasCurated = curatedTmdbIds.contains(c.tmdbId);
    return Gem(
      content: c,
      gemRank: (5 - i).toDouble(),
      reason: _reasonFor(c, profile, hasCurated),
      // Free tier sees the 2 lowest-ranked gems as a tease; Pro sees all 5.
      tierVisibility: i >= 3 ? UserPlan.free : UserPlan.pro,
    );
  }).toList();
});

/// Popular in region (Discover idle section).
final popularInRegionProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  final profile = ref.watch(userProfileProvider);
  return catalog
      .where((c) =>
          c.availablePlatforms.isNotEmpty && _matchesPlatforms(c, profile))
      .take(20)
      .toList();
});

/// Bingeable series = series sorted by popularity, filtered by user platforms.
final bingeableProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  final profile = ref.watch(userProfileProvider);
  return catalog
      .where((c) =>
          c.type == ContentType.series && _matchesPlatforms(c, profile))
      .take(15)
      .toList();
});

// ---------------------------------------------------------------------------
// Row → Content mapper
// ---------------------------------------------------------------------------

Content _mapRowToContent(
  Map<String, dynamic> r,
  Map<int, Set<String>> availByContent,
) {
  final tmdbId = r['tmdb_id'] as int;
  final mediaType = r['media_type'] as String? ?? 'movie';

  // Pick synopsis: prefer user's language, fall back to EN.
  final synopsis =
      (r['synopsis_es'] as String?) ??
      (r['synopsis_en'] as String?) ??
      '';

  // Genre IDs from TMDB → human names (best effort).
  final genreIds = (r['genres'] as List<dynamic>?)?.cast<int>() ?? [];

  // Available platforms for this title.
  final platforms = availByContent[tmdbId]?.toList() ?? [];

  return Content(
    id: tmdbId.toString(),
    tmdbId: tmdbId,
    title: (r['title'] as String?) ?? 'Untitled',
    type: mediaType == 'tv' ? ContentType.series : ContentType.movie,
    year: (r['release_year'] as int?) ?? 0,
    genres: genreIds.map(_tmdbGenreName).toList(),
    posterUrl: r['poster_path'] != null
        ? 'https://image.tmdb.org/t/p/w500${r['poster_path']}'
        : '',
    backdropUrl: r['backdrop_path'] != null
        ? 'https://image.tmdb.org/t/p/w780${r['backdrop_path']}'
        : '',
    durationMinutes: (r['runtime_minutes'] as int?) ?? 0,
    classification: (r['classification'] as String?) ?? '',
    synopsis: synopsis,
    // Watcher Score is Fase 2 — placeholder with TMDB vote average scaled.
    watcherScore: _tmdbToWatcherScore(r['tmdb_vote_average']),
    trend: TrendDirection.stable,
    hypeLevel: _popularityToHype(r['tmdb_popularity']),
    dropOffRate: DropOffRate.low,
    trustScore: 70,
    variance: 10,
    imdbScore: (r['imdb_score'] as num?)?.toDouble(),
    rottenTomatoesCriticsScore: r['rt_score'] as int?,
    metacriticScore: r['metacritic_score'] as int?,
    socialMentions: ((r['tmdb_popularity'] as num?) ?? 0).toInt() * 100,
    tags: const [],
    director: r['director'] as String?,
    cast: (r['cast_list'] as List<dynamic>?)?.cast<String>() ?? [],
    availablePlatforms: platforms,
  );
}

/// Map TMDB vote_average (0-10) to Watcher Score (0-100). Temporary.
int _tmdbToWatcherScore(dynamic voteAvg) {
  if (voteAvg == null) return 50;
  final d = (voteAvg as num).toDouble();
  return (d * 10).round().clamp(0, 100);
}

HypeLevel _popularityToHype(dynamic pop) {
  if (pop == null) return HypeLevel.low;
  final d = (pop as num).toDouble();
  if (d > 200) return HypeLevel.extreme;
  if (d > 50) return HypeLevel.high;
  if (d > 15) return HypeLevel.medium;
  return HypeLevel.low;
}

/// TMDB genre_id → human-readable name.
String _tmdbGenreName(int id) {
  const map = {
    28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy',
    80: 'Crime', 99: 'Documentary', 18: 'Drama', 10751: 'Family',
    14: 'Fantasy', 36: 'History', 27: 'Horror', 10402: 'Music',
    9648: 'Mystery', 10749: 'Romance', 878: 'Sci-Fi', 10770: 'TV Movie',
    53: 'Thriller', 10752: 'War', 37: 'Western',
    // TV genres
    10759: 'Action', 10762: 'Kids', 10763: 'News', 10764: 'Reality',
    10765: 'Sci-Fi', 10766: 'Soap', 10767: 'Talk', 10768: 'Politics',
  };
  return map[id] ?? 'Other';
}

// ---------------------------------------------------------------------------
// Fase 2a-1 — scoring & personalization helpers
// ---------------------------------------------------------------------------
//
// Philosophy: we are NOT an IMDb/RT mirror. Quality requires a cross-source
// consensus (≥2 sources passing the gate) so bot-reviewed outliers don't
// dominate. Personalization (genres, themes, sessionLength) is additive bonus
// on top of the quality base — a great title always beats a mediocre one that
// happens to share a genre, but between two quality titles, the one that
// matches the user's taste wins.

/// Quality gate thresholds. Content needs to clear ≥2 of these to be
/// considered "quality" for Daily Gems.
const double _kImdbGate = 7.2;
const int _kRtGate = 75;
const int _kMetaGate = 65;
const int _kWatcherGate = 70; // 0-100 scale (tmdb vote_average 7.0 * 10)

/// Number of quality sources this content clears.
int _qualitySourceCount(Content c) {
  var n = 0;
  if (c.imdbScore != null && c.imdbScore! >= _kImdbGate) n++;
  if (c.rottenTomatoesCriticsScore != null &&
      c.rottenTomatoesCriticsScore! >= _kRtGate) n++;
  if (c.metacriticScore != null && c.metacriticScore! >= _kMetaGate) n++;
  if (c.watcherScore >= _kWatcherGate) n++;
  return n;
}

bool _passesQualityGate(Content c) => _qualitySourceCount(c) >= 2;

/// Composite quality score 0-100 — average of available sources normalized
/// to the same scale. TMDB-derived watcherScore is always present; IMDb/RT/
/// Metacritic are opportunistic.
double _compositeScore(Content c) {
  final parts = <double>[];
  if (c.imdbScore != null) parts.add(c.imdbScore! * 10); // 0-10 → 0-100
  if (c.rottenTomatoesCriticsScore != null) {
    parts.add(c.rottenTomatoesCriticsScore!.toDouble());
  }
  if (c.metacriticScore != null) parts.add(c.metacriticScore!.toDouble());
  parts.add(c.watcherScore.toDouble());
  return parts.reduce((a, b) => a + b) / parts.length;
}

/// Profile-match bonus. Additive on top of composite score.
///   +15 per genre overlap, capped at +45 (3 matches).
///   +10 per favoriteTheme match against director/cast, capped at +30.
///   +10 if duration matches user's sessionLength window.
double _profileBonus(Content c, UserProfile p) {
  double bonus = 0;

  // Genre overlap.
  final genreMatches =
      c.genres.toSet().intersection(p.favoriteGenres.toSet()).length;
  bonus += math.min(genreMatches, 3) * 15.0;

  // favoriteThemes → director + cast. Substring match (case-insensitive) so
  // "Keanu Reeves" matches "Keanu Reeves" in the cast list and "Villeneuve"
  // matches a director field.
  if (p.favoriteThemes.isNotEmpty) {
    final themesLower =
        p.favoriteThemes.map((t) => t.toLowerCase().trim()).toList();
    var themeHits = 0;
    final director = c.director?.toLowerCase() ?? '';
    final castLower = c.cast.map((n) => n.toLowerCase()).toList();
    for (final theme in themesLower) {
      if (theme.isEmpty) continue;
      if (director.contains(theme) ||
          castLower.any((name) => name.contains(theme))) {
        themeHits++;
        if (themeHits >= 3) break;
      }
    }
    bonus += themeHits * 10.0;
  }

  // SessionLength soft bonus.
  final mins = c.durationMinutes;
  if (mins > 0) {
    switch (p.sessionLength) {
      case SessionLength.short:
        if (mins <= 95) bonus += 10;
        break;
      case SessionLength.medium:
        if (mins >= 85 && mins <= 180) bonus += 10;
        break;
      case SessionLength.long:
        if (mins >= 120) bonus += 10;
        break;
    }
  }

  return bonus;
}

/// Platform filter: if the user selected platforms in the Fast Quiz, only
/// keep content available on at least one of them. If no availability data
/// is known for a title (empty list), we hide it — the user wants their
/// platforms, not an open question. If the user selected no platforms at
/// all (shouldn't happen post-quiz but defensively), we pass everything.
bool _matchesPlatforms(Content c, UserProfile p) {
  if (p.activePlatforms.isEmpty) return true;
  if (c.availablePlatforms.isEmpty) return false;
  final userSet = p.activePlatforms.toSet();
  return c.availablePlatforms.any(userSet.contains);
}

/// Short human reason string for why a Gem was chosen. Priority:
///   1. Curated creator take (highest-signal, most honest).
///   2. Genre match with the user's favorites.
///   3. Cross-source consensus (3+ sources).
///   4. Generic fallback.
String _reasonFor(Content c, UserProfile p, bool hasCuratedTake) {
  if (hasCuratedTake) {
    return 'Curated pick — our creators weigh in on this one.';
  }
  final genreMatches =
      c.genres.toSet().intersection(p.favoriteGenres.toSet());
  if (genreMatches.isNotEmpty) {
    return 'Matches your taste in ${genreMatches.first}.';
  }
  if (_qualitySourceCount(c) >= 3) {
    return 'Rare consensus — critics and audiences agree.';
  }
  return 'High ratings, low noise — worth discovering.';
}
