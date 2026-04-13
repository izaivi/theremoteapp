import 'dart:math';

import '../models/content.dart';
import '../models/creator.dart';

/// Remoty Engine — rule-based streaming companion.
///
/// Detects user intent from keywords (mood, genre, platform, vault, creators)
/// and responds with matching content. Bilingual EN/ES.
///
/// No AI API needed — all logic is local keyword matching + catalog lookup.
/// Data is passed in from the caller (Supabase providers), so the engine
/// itself stays pure and testable.
class RemotypEngine {
  static final _rng = Random();

  /// Context data for Remoty to reason about.
  final List<Content> catalog;
  final Set<String> lovedIds;
  final Set<String> watchlistIds;
  final Set<String> notForMeIds;
  final List<CreatorTake> creatorTakes;
  final Map<String, int> ratings; // contentId → 1-5 stars

  /// Previous query context — allows Remoty to refine results.
  /// Caller passes the last user message so Remoty can combine intents.
  final String? previousQuery;
  final List<String>? previousResultIds;

  const RemotypEngine({
    required this.catalog,
    this.lovedIds = const {},
    this.watchlistIds = const {},
    this.notForMeIds = const {},
    this.creatorTakes = const [],
    this.ratings = const {},
    this.previousQuery,
    this.previousResultIds,
  });

  // ── Random fallback messages (witty, no-judgment Remoty vibe) ──

  static const _fallbacksEn = [
    "Hmm, I don't have that one in my catalog yet — but honestly, my catalog "
        "is still growing. Try asking me by mood or genre!",
    "I looked everywhere (okay, I looked in my database) and came up empty. "
        "Want to try a genre instead? I'm great at moods.",
    "No luck on that one. But hey, I'm the friend who won't judge you for "
        "watching The Smurfs at 2 AM — try me with a vibe.",
    "That one's off my radar for now. But ask me for something fun, scary, "
        "or cry-worthy and I'll deliver.",
  ];

  static const _fallbacksEs = [
    "Hmm, eso no lo tengo en mi catálogo todavía — pero sigo creciendo. "
        "¿Pruebas con un mood o género?",
    "Busqué por todos lados (bueno, en mi base de datos) y nada. "
        "¿Quieres probar con un género? Soy bueno con los moods.",
    "No encontré eso. Pero hey, soy el amigo que no te juzga si quieres ver "
        "Los Pitufos a las 2 AM — dime un vibe.",
    "Eso está fuera de mi radar por ahora. Pero pídeme algo divertido, "
        "de miedo, o para llorar y te cumplo.",
  ];

  static const _greetingsEn = [
    "Hey! I'm Remoty, your streaming buddy. Tell me a mood, a genre, "
        "or just what you feel like watching — I got you.",
    "What's up! Remoty here. I know your catalog inside out. "
        "Hit me with a vibe — action? comedy? crying on the couch?",
    "Hey there! I'm Remoty — think of me as that friend who always "
        "has the perfect recommendation. What are you in the mood for?",
    "Yo! Remoty at your service. No judgment, all picks. "
        "What do you wanna watch?",
  ];

  static const _greetingsEs = [
    "¡Hola! Soy Remoty, tu compa de streaming. Dime un mood, un género, "
        "o lo que se te antoje ver — yo te busco.",
    "¡Qué onda! Aquí Remoty. Me sé tu catálogo de memoria. "
        "Aviéntame un vibe — ¿acción? ¿comedia? ¿llorar en el sillón?",
    "¡Hey! Soy Remoty — piensa en mí como ese amigo que siempre "
        "tiene la recomendación perfecta. ¿Qué se te antoja?",
    "¡Yo! Remoty a tus órdenes. Cero juicio, puros picks. "
        "¿Qué quieres ver?",
  ];

  static String _randomFrom(List<String> list) => list[_rng.nextInt(list.length)];

  /// Entry point. Returns response text + optional content IDs for cards.
  ({String text, List<String> contentIds}) reply(
    String userMessage, {
    bool spanish = false,
  }) {
    final q = userMessage.toLowerCase().trim();

    if (q.isEmpty) {
      return (
        text: spanish
            ? 'Dime qué quieres ver y te busco algo.'
            : 'Tell me what you\'re in the mood for and I\'ll find something.',
        contentIds: const [],
      );
    }

    final intent = _detectIntent(q);

    switch (intent) {
      case _Intent.greeting:
        return (
          text: spanish ? _randomFrom(_greetingsEs) : _randomFrom(_greetingsEn),
          contentIds: const [],
        );

      case _Intent.thanks:
        return (
          text: spanish
              ? '¡De nada! Si necesitas más picks, aquí estoy.'
              : 'You\'re welcome! If you need more picks, I\'m right here.',
          contentIds: const [],
        );

      case _Intent.skip:
        final pool = catalog.where((c) => c.watcherScore < 65).toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Estos tienen scores bajos — probablemente puedes saltarlos:'
              : 'These have low scores — you can probably skip them:',
          spanish: spanish,
        );

      case _Intent.short:
        final pool = catalog
            .where((c) =>
                c.type == ContentType.movie &&
                c.durationMinutes > 0 &&
                c.durationMinutes <= 100 &&
                c.watcherScore >= 80)
            .toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Corto, de calidad, listo para esta noche:'
              : 'Short, high-quality, ready for tonight:',
          spanish: spanish,
        );

      case _Intent.binge:
        final pool = catalog
            .where(
                (c) => c.type == ContentType.series && c.watcherScore >= 80)
            .toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Estas son las series que valen tu fin de semana:'
              : 'These are the series worth your weekend:',
          spanish: spanish,
        );

      case _Intent.sad:
        final pool = catalog
            .where((c) =>
                c.genres.any((g) {
                  final gl = g.toLowerCase();
                  return gl.contains('drama') || gl.contains('romance');
                }) &&
                c.watcherScore >= 80)
            .toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Si quieres algo que te pegue en el pecho:'
              : 'If you want something that\'ll hit you in the chest:',
          spanish: spanish,
        );

      case _Intent.sciFi:
        final pool = catalog
            .where((c) => c.genres.any((g) {
                  final gl = g.toLowerCase();
                  return gl.contains('sci') || gl.contains('ciencia');
                }))
            .toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Picks de sci-fi que realmente entregan:'
              : 'Sci-fi picks that actually deliver:',
          spanish: spanish,
        );

      case _Intent.action:
        final pool = catalog
            .where((c) => c.genres.any((g) {
                  final gl = g.toLowerCase();
                  return gl.contains('action') ||
                      gl.contains('crime') ||
                      gl.contains('thriller');
                }))
            .where((c) => c.watcherScore >= 75)
            .toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Acción apretada, de alto nivel:'
              : 'Tight, high-craft action:',
          spanish: spanish,
        );

      case _Intent.classic:
        final pool = catalog
            .where((c) => c.year < 2000 && c.watcherScore >= 80)
            .toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Clásicos que vale la pena (re)descubrir:'
              : 'Classics worth revisiting (or discovering):',
          spanish: spanish,
        );

      case _Intent.comedy:
        final pool = catalog
            .where((c) => c.genres
                .any((g) => g.toLowerCase().contains('comedy')))
            .where((c) => c.watcherScore >= 75)
            .toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Para reírte un rato:'
              : 'For a good laugh:',
          spanish: spanish,
        );

      case _Intent.drama:
        final pool = catalog
            .where((c) => c.genres
                .any((g) => g.toLowerCase().contains('drama')))
            .where((c) => c.watcherScore >= 75)
            .toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Drama de peso, de los que te dejan pensando:'
              : 'Heavy-hitting drama that stays with you:',
          spanish: spanish,
        );

      case _Intent.romance:
        final pool = catalog
            .where((c) => c.genres.any((g) {
                  final gl = g.toLowerCase();
                  return gl.contains('romance') || gl.contains('love');
                }))
            .where((c) => c.watcherScore >= 70)
            .toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Para una noche romántica:'
              : 'For a romantic night in:',
          spanish: spanish,
        );

      case _Intent.refine:
        return _handleRefine(q, spanish: spanish);

      case _Intent.horror:
        final pool = catalog
            .where((c) => c.genres
                .any((g) => g.toLowerCase().contains('horror')))
            .toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Si quieres pasar miedo:'
              : 'If you want a scare:',
          spanish: spanish,
        );

      case _Intent.animation:
        final pool = catalog
            .where((c) => c.genres
                .any((g) => g.toLowerCase().contains('animat')))
            .toList();
        return _respond(
          pool: pool,
          intro: spanish
              ? 'Animación que vale la pena:'
              : 'Animation worth watching:',
          spanish: spanish,
        );

      case _Intent.vault:
        return _handleVault(q, spanish: spanish);

      case _Intent.ranking:
        return _handleRanking(q, spanish: spanish);

      case _Intent.creators:
        return _handleCreators(spanish: spanish);

      case _Intent.platform:
        return _handlePlatform(q, spanish: spanish);

      case _Intent.generic:
        return _handleSearch(q, spanish: spanish);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // VAULT HANDLER — uses real vault data
  // ══════════════════════════════════════════════════════════════

  ({String text, List<String> contentIds}) _handleVault(
    String q, {
    required bool spanish,
  }) {
    // Determine which bucket user is asking about
    final isWatchlist = _any(q, ['watchlist', 'para ver', 'saved', 'guardad']);
    final isLoved = _any(q, ['loved', 'favorit', 'heart', 'corazón']);
    final isNotForMe = _any(q, ['not for me', 'no para mí', 'dismiss', 'descartad']);

    if (isWatchlist) {
      if (watchlistIds.isEmpty) {
        return (
          text: spanish
              ? 'Tu watchlist está vacía. Guarda títulos con 🔖 para verlos después.'
              : 'Your watchlist is empty. Save titles with 🔖 to watch later.',
          contentIds: const [],
        );
      }
      final titles = catalog
          .where((c) => watchlistIds.contains(c.id))
          .toList();
      return _respond(
        pool: titles,
        intro: spanish
            ? 'En tu watchlist tienes ${watchlistIds.length} título(s). Aquí van algunos:'
            : 'You have ${watchlistIds.length} title(s) in your watchlist. Here are some:',
        spanish: spanish,
      );
    }

    if (isLoved) {
      if (lovedIds.isEmpty) {
        return (
          text: spanish
              ? 'No tienes favoritas aún. Marca con ❤️ los títulos que ames.'
              : 'No loved titles yet. Heart the titles you love.',
          contentIds: const [],
        );
      }
      final titles = catalog
          .where((c) => lovedIds.contains(c.id))
          .toList();
      return _respond(
        pool: titles,
        intro: spanish
            ? 'Tus favoritas (${lovedIds.length} título(s)):'
            : 'Your loved titles (${lovedIds.length}):',
        spanish: spanish,
      );
    }

    if (isNotForMe) {
      return (
        text: spanish
            ? 'Tienes ${notForMeIds.length} título(s) descartados. '
                'No te los recomendaremos de nuevo.'
            : 'You have ${notForMeIds.length} dismissed title(s). '
                'We won\'t recommend them again.',
        contentIds: const [],
      );
    }

    // General vault summary
    final total = lovedIds.length + watchlistIds.length + notForMeIds.length;
    if (total == 0) {
      return (
        text: spanish
            ? 'Tu bóveda está vacía. Empieza explorando y guardando títulos '
                'desde Home o Discover. Marca ❤️ los que ames y 🔖 los que quieras ver.'
            : 'Your vault is empty. Start exploring and saving titles from '
                'Home or Discover. Heart what you love and bookmark what to watch.',
        contentIds: const [],
      );
    }

    // Build detailed summary with actual title names
    final buf = StringBuffer();
    buf.writeln(spanish
        ? 'Tu bóveda tiene **$total título(s)**:'
        : 'Your vault has **$total title(s)**:');

    if (lovedIds.isNotEmpty) {
      final lovedTitles = catalog
          .where((c) => lovedIds.contains(c.id))
          .map((c) => c.title)
          .toList();
      buf.writeln('');
      buf.writeln(spanish ? '❤️ **Favoritas** (${lovedTitles.length}):' : '❤️ **Loved** (${lovedTitles.length}):');
      for (final t in lovedTitles.take(5)) {
        buf.writeln('• $t');
      }
      if (lovedTitles.length > 5) {
        buf.writeln(spanish ? '  ...y ${lovedTitles.length - 5} más' : '  ...and ${lovedTitles.length - 5} more');
      }
    }

    if (watchlistIds.isNotEmpty) {
      final wlTitles = catalog
          .where((c) => watchlistIds.contains(c.id))
          .map((c) => c.title)
          .toList();
      buf.writeln('');
      buf.writeln(spanish ? '🔖 **Para ver** (${wlTitles.length}):' : '🔖 **Watchlist** (${wlTitles.length}):');
      for (final t in wlTitles.take(5)) {
        buf.writeln('• $t');
      }
      if (wlTitles.length > 5) {
        buf.writeln(spanish ? '  ...y ${wlTitles.length - 5} más' : '  ...and ${wlTitles.length - 5} more');
      }
    }

    if (notForMeIds.isNotEmpty) {
      buf.writeln('');
      buf.writeln(spanish
          ? '👎 **Descartadas:** ${notForMeIds.length}'
          : '👎 **Dismissed:** ${notForMeIds.length}');
    }

    // Show content cards for loved or watchlisted (randomized)
    final showIds = lovedIds.isNotEmpty ? lovedIds : watchlistIds;
    final showTitles = catalog
        .where((c) => showIds.contains(c.id))
        .toList()
      ..shuffle(_rng);
    final showPicks = showTitles.take(3).toList();

    return (
      text: buf.toString().trimRight(),
      contentIds: showPicks.map((c) => c.id).toList(),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // RANKING HANDLER — uses user star ratings
  // ══════════════════════════════════════════════════════════════

  ({String text, List<String> contentIds}) _handleRanking(
    String q, {
    required bool spanish,
  }) {
    if (ratings.isEmpty) {
      return (
        text: spanish
            ? 'Aún no has calificado nada con estrellas. '
                'Abre cualquier título y dale tu rating de 1 a 5 estrellas.'
            : 'You haven\'t rated anything yet. '
                'Open any title and give it your 1-5 star rating.',
        contentIds: const [],
      );
    }

    final isWorst = _any(q, [
      'worst', 'peor', '1 star', 'one star', 'low',
      'peores', 'baj',
    ]);

    if (isWorst) {
      // Show lowest rated (1-2 stars)
      final lowIds = ratings.entries
          .where((e) => e.value <= 2)
          .map((e) => e.key)
          .toList();
      if (lowIds.isEmpty) {
        return (
          text: spanish
              ? 'No tienes ningún título con 1 o 2 estrellas. ¡Todo bien valorado!'
              : 'You don\'t have any 1-2 star titles. Everything\'s rated well!',
          contentIds: const [],
        );
      }
      final titles = catalog
          .where((c) => lowIds.contains(c.id))
          .toList();
      return _respond(
        pool: titles,
        intro: spanish
            ? 'Tus títulos con peor rating (${lowIds.length}):'
            : 'Your lowest rated titles (${lowIds.length}):',
        spanish: spanish,
      );
    }

    // Default: show best rated (5 stars, or top rated)
    final fiveStarIds = ratings.entries
        .where((e) => e.value == 5)
        .map((e) => e.key)
        .toList();

    if (fiveStarIds.isNotEmpty) {
      final titles = catalog
          .where((c) => fiveStarIds.contains(c.id))
          .toList()
        ..shuffle(_rng);
      final buf = StringBuffer();
      buf.writeln(spanish
          ? '⭐ Tus **${fiveStarIds.length} título(s) con 5 estrellas**:'
          : '⭐ Your **${fiveStarIds.length} five-star title(s)**:');
      buf.writeln('');
      for (final t in titles.take(5)) {
        buf.writeln('• **${t.title}** (${t.year})');
      }
      if (titles.length > 5) {
        buf.writeln(spanish
            ? '  ...y ${titles.length - 5} más'
            : '  ...and ${titles.length - 5} more');
      }
      return (
        text: buf.toString().trimRight(),
        contentIds: titles.take(3).map((c) => c.id).toList(),
      );
    }

    // No 5-star, show general summary
    final grouped = <int, int>{};
    for (final e in ratings.entries) {
      grouped[e.value] = (grouped[e.value] ?? 0) + 1;
    }
    final buf = StringBuffer();
    buf.writeln(spanish
        ? 'Has calificado **${ratings.length} título(s)**:'
        : 'You\'ve rated **${ratings.length} title(s)**:');
    for (final stars in [5, 4, 3, 2, 1]) {
      final count = grouped[stars];
      if (count != null) {
        buf.writeln('${'⭐' * stars} — $count');
      }
    }
    // Show cards for top rated
    final topIds = ratings.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final showTitles = catalog
        .where((c) => topIds.take(3).any((e) => e.key == c.id))
        .take(3)
        .toList();
    return (
      text: buf.toString().trimRight(),
      contentIds: showTitles.map((c) => c.id).toList(),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // CREATORS HANDLER — uses real takes data
  // ══════════════════════════════════════════════════════════════

  ({String text, List<String> contentIds}) _handleCreators({
    required bool spanish,
  }) {
    if (creatorTakes.isEmpty) {
      return (
        text: spanish
            ? 'Aún no hay takes de creators en el catálogo. '
                'Sé el primero en publicar un take desde la ficha de cualquier título.'
            : 'No creator takes yet. Be the first to publish a take from any title card.',
        contentIds: const [],
      );
    }

    // Top worth-it takes by popularity
    final worthIt = creatorTakes
        .where((t) => t.verdict == CreatorVerdict.worthIt)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final skipIt = creatorTakes
        .where((t) => t.verdict == CreatorVerdict.skipIt)
        .toList();

    final topPicks = worthIt.take(3).toList();
    final lines = topPicks
        .map((t) {
          final preview = t.body.length > 60
              ? '${t.body.substring(0, 60)}...'
              : t.body;
          return '• "${preview}"';
        })
        .join('\n');

    return (
      text: spanish
          ? 'Hay ${creatorTakes.length} takes publicados '
              '(${worthIt.length} Worth It, ${skipIt.length} Skip It).\n\n'
              'Los más recientes:\n$lines'
          : 'There are ${creatorTakes.length} published takes '
              '(${worthIt.length} Worth It, ${skipIt.length} Skip It).\n\n'
              'Most recent:\n$lines',
      contentIds: topPicks.map((t) => t.contentId).toSet().toList(),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PLATFORM HANDLER — searches real catalog availablePlatforms
  // ══════════════════════════════════════════════════════════════

  ({String text, List<String> contentIds}) _handlePlatform(
    String q, {
    required bool spanish,
  }) {
    final platform = _extractPlatform(q);
    final pool = catalog
        .where((c) => c.availablePlatforms
            .any((p) => p.toLowerCase().contains(platform.toLowerCase())))
        .where((c) => c.watcherScore >= 70)
        .toList()
      ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));

    return _respond(
      pool: pool,
      intro: spanish
          ? 'Lo mejor disponible en **$platform**:'
          : 'Best available on **$platform**:',
      spanish: spanish,
      emptyMsg: spanish
          ? 'No encontré contenido de **$platform** en el catálogo actual. '
              'Puede que las licencias varíen por región.'
          : 'No **$platform** content found in the current catalog. '
              'Licensing may vary by region.',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SEARCH HANDLER — title, director, cast fuzzy match
  // ══════════════════════════════════════════════════════════════

  ({String text, List<String> contentIds}) _handleSearch(
    String q, {
    required bool spanish,
  }) {
    // Normalize query: lowercase, remove common filler words
    final query = q
        .replaceAll(RegExp(r'\b(busca|buscar|find|search|show|dame|quiero ver|want to watch|recommend|recomienda)\b'), '')
        .trim();

    if (query.isEmpty) {
      final pool = [...catalog]
        ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));
      return _respond(
        pool: pool,
        intro: spanish
            ? 'Esto es lo que el Watcher Score ama ahora:'
            : 'Here\'s what the Watcher Score is loving right now:',
        spanish: spanish,
      );
    }

    final ql = query.toLowerCase();

    // 1. Exact/substring title match (highest priority)
    final titleMatches = catalog
        .where((c) => c.title.toLowerCase().contains(ql))
        .toList()
      ..sort((a, b) {
        // Prefer exact matches, then shorter titles (more specific)
        final aExact = a.title.toLowerCase() == ql ? 0 : 1;
        final bExact = b.title.toLowerCase() == ql ? 0 : 1;
        if (aExact != bExact) return aExact.compareTo(bExact);
        return a.title.length.compareTo(b.title.length);
      });

    if (titleMatches.isNotEmpty) {
      return _respond(
        pool: titleMatches,
        intro: spanish
            ? 'Encontré esto en el catálogo:'
            : 'Found this in the catalog:',
        spanish: spanish,
        shuffle: false,
      );
    }

    // 2. Director match
    final directorMatches = catalog
        .where((c) => c.director?.toLowerCase().contains(ql) ?? false)
        .toList()
      ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));

    if (directorMatches.isNotEmpty) {
      final dirName = directorMatches.first.director ?? query;
      return _respond(
        pool: directorMatches,
        intro: spanish
            ? 'Películas de **$dirName** en el catálogo:'
            : 'Films by **$dirName** in the catalog:',
        spanish: spanish,
        shuffle: false,
      );
    }

    // 3. Cast match
    final castMatches = catalog
        .where((c) => c.cast.any((a) => a.toLowerCase().contains(ql)))
        .toList()
      ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));

    if (castMatches.isNotEmpty) {
      // Find the actual actor name for display
      final actorName = castMatches.first.cast
          .firstWhere((a) => a.toLowerCase().contains(ql), orElse: () => query);
      return _respond(
        pool: castMatches,
        intro: spanish
            ? 'Títulos con **$actorName**:'
            : 'Titles with **$actorName**:',
        spanish: spanish,
        shuffle: false,
      );
    }

    // 4. Word-level fuzzy: match if ANY significant word (3+ chars) in the
    //    query appears in the title. Catches partial title searches.
    final words = ql.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
    if (words.isNotEmpty) {
      final fuzzyMatches = catalog.where((c) {
        final tl = c.title.toLowerCase();
        return words.any((w) => tl.contains(w));
      }).toList()
        ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));

      if (fuzzyMatches.isNotEmpty) {
        return _respond(
          pool: fuzzyMatches,
          intro: spanish
              ? 'No encontré una coincidencia exacta, pero esto podría interesarte:'
              : 'No exact match, but this might interest you:',
          spanish: spanish,
        );
      }
    }

    // 5. Nothing found — witty random fallback + trending picks
    final pool = [...catalog]
      ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));
    final fallback = spanish ? _randomFrom(_fallbacksEs) : _randomFrom(_fallbacksEn);
    return _respond(
      pool: pool,
      intro: fallback,
      spanish: spanish,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // REFINE HANDLER — narrows previous results based on new criteria
  // ══════════════════════════════════════════════════════════════

  ({String text, List<String> contentIds}) _handleRefine(
    String q, {
    required bool spanish,
  }) {
    // Get previous results to narrow down
    final prevPool = previousResultIds != null && previousResultIds!.isNotEmpty
        ? catalog.where((c) => previousResultIds!.contains(c.id)).toList()
        : <Content>[];

    // If we have no previous results, search the whole catalog
    final searchPool = prevPool.isNotEmpty ? prevPool : catalog;

    // Detect what they want to refine BY
    List<Content> refined;

    if (_any(q, ['fight', 'pelea', 'violent', 'violenc', 'martial', 'combat'])) {
      refined = searchPool
          .where((c) => c.genres.any((g) {
                final gl = g.toLowerCase();
                return gl.contains('action') || gl.contains('crime') || gl.contains('thriller');
              }))
          .toList();
    } else if (_any(q, ['funny', 'fun', 'comedy', 'comedia', 'divertid'])) {
      refined = searchPool
          .where((c) => c.genres.any((g) => g.toLowerCase().contains('comedy')))
          .toList();
    } else if (_any(q, ['drama', 'serious', 'heavy', 'intense'])) {
      refined = searchPool
          .where((c) => c.genres.any((g) => g.toLowerCase().contains('drama')))
          .toList();
    } else if (_any(q, ['romance', 'romántic', 'love', 'amor'])) {
      refined = searchPool
          .where((c) => c.genres.any((g) {
                final gl = g.toLowerCase();
                return gl.contains('romance') || gl.contains('love');
              }))
          .toList();
    } else {
      // Generic word match within previous results
      final words = q.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
      refined = searchPool.where((c) {
        final tl = '${c.title} ${c.genres.join(' ')} ${c.director ?? ''}'.toLowerCase();
        return words.any((w) => tl.contains(w));
      }).toList();
    }

    if (refined.isEmpty) {
      return (
        text: spanish
            ? 'No encontré nada con ese filtro dentro de lo anterior. '
                '¿Quieres que busque en todo el catálogo?'
            : 'Nothing matched that filter in your previous results. '
                'Want me to search the full catalog?',
        contentIds: const [],
      );
    }

    return _respond(
      pool: refined,
      intro: spanish
          ? 'Refinando tu búsqueda:'
          : 'Narrowing it down:',
      spanish: spanish,
    );
  }

  // ── Intent classification ──

  _Intent _detectIntent(String q) {
    // Check for refinement of previous query first —
    // short messages like "but with fights" or "pero de peleas" refine.
    if (previousQuery != null &&
        previousResultIds != null &&
        previousResultIds!.isNotEmpty &&
        _any(q, [
          'but', 'pero', 'more', 'más', 'mas', 'less', 'menos',
          'only', 'solo', 'sólo', 'instead', 'better', 'mejor',
          'with', 'con', 'without', 'sin', 'que sean', 'that are',
          'de esas', 'of those', 'like that', 'así', 'asi',
        ])) {
      return _Intent.refine;
    }

    if (_any(q, ['hi', 'hello', 'hola', 'hey', 'sup', 'qué onda', 'que onda'])) {
      return _Intent.greeting;
    }
    if (_any(q, ['thank', 'gracias', 'thanks', 'thx'])) {
      return _Intent.thanks;
    }
    if (_any(q, [
      'avoid', 'skip', 'overrated', 'evitar', 'saltar',
      'sobrevalorada', 'sobrevalorado', 'me salto',
    ])) return _Intent.skip;

    if (_any(q, [
      'short', 'corto', 'quick', 'rápido', 'rapido',
      'tonight', 'esta noche', '<90', 'hora y media',
    ])) return _Intent.short;

    if (_any(q, [
      'binge', 'marathon', 'maratón', 'weekend', 'fin de semana',
    ])) return _Intent.binge;

    // Check 'series'/'serie' separately to avoid false positives
    if (_any(q, ['serie']) && !_any(q, ['series de', 'serie de'])) {
      return _Intent.binge;
    }

    if (_any(q, [
      'sad', 'triste', 'cry', 'llorar', 'emotional',
      'emocional', 'heartbreak',
    ])) return _Intent.sad;

    if (_any(q, [
      'comedy', 'comedia', 'funny', 'fun', 'chistos', 'gracios',
      'reír', 'reir', 'laugh', 'divertid', 'hilarious', 'humor',
    ])) {
      return _Intent.comedy;
    }

    if (_any(q, [
      'drama', 'dramát', 'dramat', 'serious', 'intense', 'intens',
      'deep', 'profund', 'heavy',
    ])) {
      return _Intent.drama;
    }

    if (_any(q, [
      'romance', 'romantic', 'romántic', 'romanc', 'love story',
      'amor', 'date night', 'couple', 'pareja',
    ])) {
      return _Intent.romance;
    }

    if (_any(q, ['horror', 'terror', 'scary', 'miedo', 'susto'])) {
      return _Intent.horror;
    }

    if (_any(q, ['animat', 'anime', 'cartoon', 'animación', 'animacion', 'pixar', 'ghibli'])) {
      return _Intent.animation;
    }

    if (_any(q, [
      'action', 'acción', 'accion', 'fight', 'pelea', 'crime',
      'thriller', 'shoot', 'war', 'guerra', 'violent', 'violenc',
      'martial', 'combat', 'explosio',
    ])) {
      return _Intent.action;
    }

    if (_any(q, ['sci-fi', 'scifi', 'ciencia ficción', 'space', 'futuro'])) {
      return _Intent.sciFi;
    }

    if (_any(q, ['classic', 'clásico', 'clasico', 'old', 'viejo'])) {
      return _Intent.classic;
    }

    if (_any(q, [
      'ranking', 'ranked', 'rated', 'stars', 'estrellas',
      'best rated', 'worst rated', 'mis ratings', 'my ratings',
      'top rated', 'mejor calificad', 'peor calificad',
      '5 stars', '1 star', 'five star', 'one star',
      'mis mejores', 'mis peores',
    ])) return _Intent.ranking;

    if (_any(q, [
      'vault', 'bóveda', 'boveda', 'watchlist', 'para ver',
      'my vault', 'mi bóveda', 'saved', 'favorit', 'loved',
      'not for me', 'no para mí', 'descartad',
    ])) return _Intent.vault;

    if (_any(q, [
      'creator', 'creators', 'take', 'takes', 'creador',
      'creadores', 'picks de creator',
    ])) return _Intent.creators;

    if (_any(q, [
      'netflix', 'max', 'hbo', 'disney', 'prime', 'amazon',
      'apple tv', 'hulu', 'paramount', 'crunchyroll', 'peacock',
      'mubi', 'tubi', 'vix', 'platform', 'plataforma',
    ])) return _Intent.platform;

    return _Intent.generic;
  }

  static String _extractPlatform(String q) {
    final platforms = {
      'netflix': 'Netflix',
      'max': 'Max',
      'hbo': 'Max',
      'disney': 'Disney Plus',
      'prime': 'Prime Video',
      'amazon': 'Prime Video',
      'apple tv': 'Apple TV Plus',
      'hulu': 'Hulu',
      'paramount': 'Paramount Plus',
      'crunchyroll': 'Crunchyroll',
      'peacock': 'Peacock',
      'mubi': 'MUBI',
      'tubi': 'Tubi',
      'vix': 'ViX',
    };
    for (final entry in platforms.entries) {
      if (q.contains(entry.key)) return entry.value;
    }
    return 'streaming';
  }

  // ── Response builder ──

  static ({String text, List<String> contentIds}) _respond({
    required List<Content> pool,
    required String intro,
    required bool spanish,
    String? emptyMsg,
    bool shuffle = true,
  }) {
    if (pool.isEmpty) {
      return (
        text: emptyMsg ??
            (spanish ? _randomFrom(_fallbacksEs) : _randomFrom(_fallbacksEn)),
        contentIds: const [],
      );
    }

    final working = [...pool];
    if (shuffle) working.shuffle(_rng);
    final picks = working.take(3).toList();
    final reasonsLine = picks
        .map((c) =>
            '• **${c.title}** (${c.year}) — Watcher Score ${c.watcherScore}')
        .join('\n');

    return (
      text: '$intro\n\n$reasonsLine',
      contentIds: picks.map((c) => c.id).toList(),
    );
  }

  static bool _any(String text, List<String> keys) =>
      keys.any((k) => text.contains(k));
}

/// Legacy alias — kept so nothing breaks if old code references it.
@Deprecated('Use RemotypEngine instead')
typedef MockAiResponder = RemotypEngine;

enum _Intent {
  greeting,
  thanks,
  skip,
  short,
  binge,
  sad,
  action,
  sciFi,
  classic,
  comedy,
  drama,
  romance,
  horror,
  animation,
  vault,
  ranking,
  creators,
  platform,
  refine,
  generic,
}
