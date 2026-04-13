import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/prefs/language_prefs.dart';
import '../../core/supabase/supabase_client.dart';
import '../mock/mock_content.dart';
import '../models/content.dart';
import 'auth_repository.dart';

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

/// Trending = top by TMDB popularity (stand-in until Watcher Score Fase 2).
final trendingProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  return catalog.take(20).toList(); // already sorted by tmdb_popularity desc
});

/// Exploding = recent + high popularity spike (heuristic: release_year recent
/// + high popularity). Placeholder until we have real trend signals.
final explodingProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  final now = DateTime.now().year;
  return catalog
      .where((c) => c.year >= now - 1 && c.tmdbId != null)
      .take(15)
      .toList();
});

/// Quick decision = movies under 115 min, sorted by popularity.
final quickDecisionProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  return catalog
      .where((c) =>
          c.type == ContentType.movie && c.durationMinutes <= 115)
      .take(15)
      .toList();
});

/// Don't waste = lowest scored content with some popularity (anti-rec).
/// Placeholder: titles with low imdb scores but high popularity.
final dontWasteProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  final withScores = catalog.where((c) => c.imdbScore != null && c.imdbScore! < 5.5).toList()
    ..sort((a, b) => (a.imdbScore ?? 0).compareTo(b.imdbScore ?? 0));
  return withScores.take(10).toList();
});

/// Daily gems = high-quality hidden gems (high score + lower popularity).
/// Placeholder until Watcher Score Fase 2.
final dailyGemsProvider = FutureProvider<List<Gem>>((ref) async {
  if (!SupabaseConfig.isConfigured) return MockContent.dailyGems;
  final catalog = await ref.watch(catalogProvider.future);
  // Pick titles with good IMDb score but NOT in the top-20 popularity.
  final pool = catalog
      .where((c) => c.imdbScore != null && c.imdbScore! >= 7.5)
      .skip(20) // skip the trending ones
      .take(20)
      .toList()
    ..sort((a, b) => (b.imdbScore ?? 0).compareTo(a.imdbScore ?? 0));

  return pool.take(5).indexed.map((e) {
    final (i, c) = e;
    return Gem(
      content: c,
      gemRank: (5 - i).toDouble(),
      reason: 'High ratings, low noise — worth discovering.',
      tierVisibility: i < 3 ? UserPlan.free : UserPlan.pro,
    );
  }).toList();
});

/// Popular in region (Discover idle section).
final popularInRegionProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  return catalog
      .where((c) => c.availablePlatforms.isNotEmpty)
      .take(20)
      .toList();
});

/// Bingeable series = series sorted by popularity.
final bingeableProvider = FutureProvider<List<Content>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  return catalog
      .where((c) => c.type == ContentType.series)
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
