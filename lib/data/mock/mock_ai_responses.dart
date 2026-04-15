import 'dart:math';

import '../models/content.dart';
import '../models/creator.dart';
import '../models/user_profile.dart';

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

  /// Last text Remoty itself produced. Used so a follow-up "ok / dale / yes"
  /// can be interpreted as "act on what you just offered" — currently used
  /// to extract a `**theme**` mentioned in a personalized greeting.
  final String? previousReplyText;

  /// User taste profile — drives greeting personalization, platform
  /// pre-filtering, sessionLength caps, and genre tiebreaker weighting.
  /// Null while anonymous / pre-onboarding (engine falls back to neutral).
  final UserProfile? userProfile;

  /// Engaged content IDs (watchedIds ∪ dismissedIds ∪ ratings.keys).
  /// Same contract as Home rows + Discover idle (Fase 3.1).
  /// Only applied to *recommendation* intents — explicit title/director/cast
  /// searches bypass it so the user can always look something up by name.
  final Set<String> excluded;

  const RemotypEngine({
    required this.catalog,
    this.lovedIds = const {},
    this.watchlistIds = const {},
    this.notForMeIds = const {},
    this.creatorTakes = const [],
    this.ratings = const {},
    this.previousQuery,
    this.previousResultIds,
    this.previousReplyText,
    this.userProfile,
    this.excluded = const {},
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

  /// Personalized greeting (Fase 4 — "cálido pero discreto").
  ///
  /// Picks a base greeting from the bilingual pool, then optionally:
  ///   - prefixes the user's [alias] when present (~70% of the time)
  ///   - tags on a one-liner referencing a [favoriteThemes] entry (~50%)
  ///
  /// Falls back to the plain pool when [userProfile] is null/anonymous so
  /// brand-new users still see the canonical Remoty intro.
  String _personalizedGreeting(bool spanish) {
    final base = spanish ? _randomFrom(_greetingsEs) : _randomFrom(_greetingsEn);
    final p = userProfile;
    if (p == null) return base;

    final alias = p.alias?.trim();
    final hasAlias = alias != null && alias.isNotEmpty;

    // Alias prefix ~70% of the time (when we have one).
    // We don't try to splice the alias inside the canned phrase — too fragile
    // across languages. Instead we prepend a short personalized opener and
    // keep the original greeting on the next line.
    String greeting = base;
    if (hasAlias && _rng.nextInt(10) < 7) {
      final opener = spanish ? '¡Hey, $alias!' : 'Hey, $alias!';
      greeting = '$opener $base';
    }

    // Theme/director/actor mention ~50% of the time.
    final themes = p.favoriteThemes;
    if (themes.isNotEmpty && _rng.nextBool()) {
      final theme = themes[_rng.nextInt(themes.length)];
      greeting += spanish
          ? '\n\nVi en tu perfil que te late **$theme** — si quieres, jalo por ahí.'
          : '\n\nNoticed **$theme** on your profile — happy to lean that way if you want.';
    }

    return greeting;
  }

  /// Single-token affirmations that mean "yes, do that" in the context of
  /// the previous Remoty reply. Kept narrow on purpose — anything ambiguous
  /// (like "sure" alone, which can be sarcasm) we leave to generic search.
  static final RegExp _affirmationRe = RegExp(
    r'^(ok|okay|okey|sí|si|yes|yep|yeah|dale|vale|porfa|porfi|please|pls|claro|listo|go|adelante)[!.\s]*$',
    caseSensitive: false,
  );

  static bool _isAffirmation(String q) => _affirmationRe.hasMatch(q.trim());

  /// Handle a contextual "ok / dale / yes" — the user is accepting whatever
  /// Remoty offered in the previous reply.
  ///
  /// Strategy:
  ///   1. Look for a `**bolded**` token in the previous reply (themes are
  ///      always rendered bold by `_personalizedGreeting`). If found, search
  ///      the catalog for that token across title/director/cast/genre.
  ///   2. Fall back to the personalized top pool so the user always gets
  ///      *something* actionable.
  ({String text, List<String> contentIds}) _handleAffirmation({
    required bool spanish,
  }) {
    final prev = previousReplyText ?? '';
    final boldMatch = RegExp(r'\*\*([^*]+)\*\*').firstMatch(prev);
    final cue = boldMatch?.group(1)?.trim();

    if (cue != null && cue.isNotEmpty) {
      final cl = cue.toLowerCase();
      final hits = catalog.where((c) {
        final t = c.title.toLowerCase();
        final d = c.director?.toLowerCase() ?? '';
        final castHit = c.cast.any((a) => a.toLowerCase().contains(cl));
        final genreHit = c.genres.any((g) => g.toLowerCase().contains(cl));
        return t.contains(cl) || d.contains(cl) || castHit || genreHit;
      }).toList()
        ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));

      if (hits.isNotEmpty) {
        return _respond(
          pool: hits,
          intro: spanish
              ? 'Perfecto, jalando por **$cue**:'
              : 'Got it, leaning into **$cue**:',
          spanish: spanish,
          shuffle: false,
          // Don't hide engaged titles — the user explicitly asked for this thread.
          respectExclusion: false,
        );
      }
    }

    // Nothing to lean into → personalized top picks.
    return _respond(
      pool: _personalizedTopPool(),
      intro: spanish
          ? 'Va. Esto es lo que más vale la pena ahora:'
          : 'Cool. Here\'s what\'s most worth your time right now:',
      spanish: spanish,
    );
  }

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
          text: _personalizedGreeting(spanish),
          contentIds: const [],
        );

      case _Intent.thanks:
        return (
          text: spanish
              ? '¡De nada! Si necesitas más picks, aquí estoy.'
              : 'You\'re welcome! If you need more picks, I\'m right here.',
          contentIds: const [],
        );

      case _Intent.affirmation:
        return _handleAffirmation(spanish: spanish);

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
        // Cap depends on the user's preferred sessionLength bucket so a
        // "long-binge" person doesn't get force-fed 90-minute fillers when
        // they ask for "something tonight".
        final cap = switch (userProfile?.sessionLength ?? SessionLength.medium) {
          SessionLength.short => 95,
          SessionLength.medium => 120,
          SessionLength.long => 150,
        };
        final pool = catalog
            .where((c) =>
                c.type == ContentType.movie &&
                c.durationMinutes > 0 &&
                c.durationMinutes <= cap &&
                c.watcherScore >= 80)
            .toList();
        return _respond(
          pool: _weightByFavoriteGenres(pool),
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
          pool: _weightByFavoriteGenres(pool),
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
        // Si el usuario dijo "anime" / "ghibli" / "manga" / "shonen",
        // aplicamos filtro estricto: Animation + original_language = 'ja'.
        // Esto evita servir Pixar/DreamWorks cuando piden específicamente anime.
        // Si la cosecha queda vacía (catalog sin anime ingestado), caemos al
        // filtro amplio para no devolver "nada" al usuario.
        final isAnimeAsk = _any(
          q,
          ['anime', 'ghibli', 'manga', 'shonen', 'shounen', 'otaku'],
        );
        final broadPool = catalog
            .where((c) => c.genres
                .any((g) => g.toLowerCase().contains('animat')))
            .toList();
        final strictPool = isAnimeAsk
            ? broadPool
                .where((c) => c.originalLanguage == 'ja')
                .toList()
            : const <Content>[];
        final pool = (isAnimeAsk && strictPool.isNotEmpty)
            ? strictPool
            : broadPool;
        return _respond(
          pool: pool,
          intro: isAnimeAsk
              ? (spanish ? 'Anime para maratonear:' : 'Anime worth bingeing:')
              : (spanish
                  ? 'Animación que vale la pena:'
                  : 'Animation worth watching:'),
          spanish: spanish,
        );

      case _Intent.vault:
        return _handleVault(q, spanish: spanish);

      case _Intent.ranking:
        return _handleRanking(q, spanish: spanish);

      case _Intent.byScore:
        return _handleByScore(q, spanish: spanish);

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
    final activePlatforms = userProfile?.activePlatforms ?? const <String>[];

    // Generic "what's on streaming?" with no named platform → prefer the
    // user's active subscriptions so we don't surface stuff they can't watch.
    if (platform == 'streaming' && activePlatforms.isNotEmpty) {
      final pool = catalog
          .where((c) => c.availablePlatforms.any((p) {
                final pl = p.toLowerCase();
                return activePlatforms
                    .any((ap) => pl.contains(ap.toLowerCase()));
              }))
          .where((c) => c.watcherScore >= 75)
          .toList()
        ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));
      return _respond(
        pool: _weightByFavoriteGenres(pool),
        intro: spanish
            ? 'Lo mejor en tus plataformas (${activePlatforms.join(', ')}):'
            : 'Best on your platforms (${activePlatforms.join(', ')}):',
        spanish: spanish,
      );
    }

    final pool = catalog
        .where((c) => c.availablePlatforms
            .any((p) => p.toLowerCase().contains(platform.toLowerCase())))
        .where((c) => c.watcherScore >= 70)
        .toList()
      ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));

    // Heads-up if the named platform isn't one the user actually pays for.
    final userHasIt = activePlatforms
        .any((ap) => ap.toLowerCase() == platform.toLowerCase());
    final heads = (activePlatforms.isNotEmpty && !userHasIt)
        ? (spanish
            ? '_Heads-up: no veo **$platform** en tu lista de plataformas activas — quizá necesites suscribirte._\n\n'
            : '_Heads-up: I don\'t see **$platform** on your active platforms — you may need a subscription._\n\n')
        : '';

    return _respond(
      pool: _weightByFavoriteGenres(pool),
      intro: '$heads${spanish ? 'Lo mejor disponible en **$platform**:' : 'Best available on **$platform**:'}',
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
    // Normalize query: lowercase, remove common filler words / phrases.
    // Order matters: strip multi-word phrases BEFORE single tokens so we
    // don't leave orphan stop-words behind ("what" without "about", etc).
    final query = q
        .replaceAll(
            RegExp(
                r'\b(que hay de|qu[eé] hay de|que tienes de|qu[eé] tienes de|what about|what is|what\u0027s|whats|who is|who\u0027s|tell me about|h[aá]blame de|conoces a|sabes de)\b'),
            '')
        .replaceAll(
            RegExp(
                r'\b(busca|buscar|find|search|show|dame|quiero ver|want to watch|recommend|recomienda)\b'),
            '')
        .trim();

    if (query.isEmpty) {
      final pool = _personalizedTopPool();
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
      // Explicit name lookup → never hide engaged titles. If Vivi rated FROM
      // 5★ and then asks "FROM" by name, she still wants FROM in the answer.
      return _respond(
        pool: titleMatches,
        intro: spanish
            ? 'Encontré esto en el catálogo:'
            : 'Found this in the catalog:',
        spanish: spanish,
        shuffle: false,
        respectExclusion: false,
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
        respectExclusion: false,
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
        respectExclusion: false,
      );
    }

    // 4. Word-level fuzzy: match if ANY significant word (3+ chars) in the
    //    query appears in title, director, or cast. Catches partial searches
    //    like "Que hay de Nolan" → Nolan is a director surname, not a title.
    final words = ql.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
    if (words.isNotEmpty) {
      final fuzzyMatches = catalog.where((c) {
        final tl = c.title.toLowerCase();
        final dl = c.director?.toLowerCase() ?? '';
        return words.any((w) {
          if (tl.contains(w) || dl.contains(w)) return true;
          return c.cast.any((a) => a.toLowerCase().contains(w));
        });
      }).toList()
        ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));

      if (fuzzyMatches.isNotEmpty) {
        // Title-only matches keep the "this might interest you" intro;
        // anything else (director/cast) is a stronger signal — say so.
        final isPersonHit = fuzzyMatches.any((c) => words.any((w) {
              final tl = c.title.toLowerCase();
              if (tl.contains(w)) return false;
              final dl = c.director?.toLowerCase() ?? '';
              return dl.contains(w) ||
                  c.cast.any((a) => a.toLowerCase().contains(w));
            }));
        return _respond(
          pool: fuzzyMatches,
          intro: isPersonHit
              ? (spanish
                  ? 'Encontré títulos relacionados a ${words.last}:'
                  : 'Found titles related to ${words.last}:')
              : (spanish
                  ? 'No encontré una coincidencia exacta, pero esto podría interesarte:'
                  : 'No exact match, but this might interest you:'),
          spanish: spanish,
          shuffle: false,
          // Person/director/cast lookups are explicit — don't hide engaged.
          respectExclusion: !isPersonHit,
        );
      }
    }

    // 5. Nothing found — witty random fallback + personalized trending picks
    final pool = _personalizedTopPool();
    final fallback = spanish ? _randomFrom(_fallbacksEs) : _randomFrom(_fallbacksEn);
    return _respond(
      pool: pool,
      intro: fallback,
      spanish: spanish,
    );
  }

  /// "Top of catalog" tilted toward the user's favoriteGenres and
  /// activePlatforms. Used when the user asks something open-ended (or when
  /// search misses) so we don't dump the same generic top-N every time.
  ///
  /// Anonymous users get the plain watcherScore-sorted catalog.
  List<Content> _personalizedTopPool() {
    final p = userProfile;
    final base = [...catalog]
      ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));
    if (p == null) return base;

    final favsLower = p.favoriteGenres.map((g) => g.toLowerCase()).toSet();
    final platsLower =
        p.activePlatforms.map((plat) => plat.toLowerCase()).toSet();

    if (favsLower.isEmpty && platsLower.isEmpty) return base;

    bool platformOk(Content c) {
      if (platsLower.isEmpty) return true;
      return c.availablePlatforms.any((ap) {
        final apl = ap.toLowerCase();
        return platsLower.any((up) => apl.contains(up));
      });
    }

    bool genreOk(Content c) {
      if (favsLower.isEmpty) return true;
      return c.genres.any((g) {
        final gl = g.toLowerCase();
        return favsLower.any((f) => gl.contains(f) || f.contains(gl));
      });
    }

    final hits = base.where((c) => platformOk(c) && genreOk(c)).toList();
    // Backfill with the rest of the catalog so we always have ≥ 3 candidates.
    final remainder = base.where((c) => !hits.contains(c)).toList();
    return [...hits, ...remainder];
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

  // ── Watcher Score detection ──
  //
  // Fires when the user references the Watcher Score visible in every result
  // card. Catches three shapes:
  //   1. Explicit name: "watcher score", "puntaje", "puntuación"
  //   2. "score" word (en/es): "score alto", "score 80", "score superior"
  //   3. Numeric thresholds with comparators: "más de 80", "above 75", etc.
  //      (kept narrow to 2-digit numbers so "5 stars" doesn't false-positive)
  static final RegExp _byScoreRe = RegExp(
    r'(watcher score|puntaje|puntuaci[oó]n|\bscore\b|'
    r'(?:m[aá]s de|arriba de|encima de|superior a|mayor (?:a|que)|'
    r'above|over|higher than|greater than)\s*\d{2,3})',
    caseSensitive: false,
  );

  static bool _isByScoreQuery(String q) => _byScoreRe.hasMatch(q);

  /// Parse a threshold from the query.
  ///
  /// Heuristics:
  ///   - Numeric token in 50-99 → use as-is (Watcher Score is /100)
  ///   - Numeric token in 1-10 (with comma/dot decimals) → IMDb-style /10,
  ///     multiply ×10 (so "score arriba de 8" → 80)
  ///   - "alto" / "high" / "highest" / "top" → 80 (or 85 for "muy alto")
  ///   - Nothing parseable → 80 (default for "watcher score" alone)
  ///
  /// Returns null only when the user explicitly wants "low" titles, so the
  /// caller can route to a different copy.
  int? _parseScoreThreshold(String q) {
    // Low-score signal — mirrors the `skip` intent territory; we still answer
    // here because the user explicitly asked about score.
    if (_any(q, ['bajo', 'low', 'malo', 'peor', 'worst'])) return -1;

    // Number + optional decimal.
    final numMatch = RegExp(r'\b(\d{1,3})(?:[.,](\d+))?\b').firstMatch(q);
    if (numMatch != null) {
      final whole = int.tryParse(numMatch.group(1)!) ?? 80;
      if (whole >= 50 && whole <= 100) return whole.clamp(50, 100);
      if (whole >= 1 && whole <= 10) {
        // Treat 8.5 → 85, 9 → 90, 7 → 70, etc.
        final dec = numMatch.group(2);
        if (dec != null && dec.isNotEmpty) {
          final asDouble = double.tryParse('$whole.$dec') ?? whole.toDouble();
          return (asDouble * 10).round().clamp(50, 100);
        }
        return (whole * 10).clamp(50, 100);
      }
    }

    if (_any(q, ['muy alto', 'altísimo', 'altisimo', 'highest', 'top tier'])) {
      return 85;
    }
    return 80;
  }

  ({String text, List<String> contentIds}) _handleByScore(
    String q, {
    required bool spanish,
  }) {
    final threshold = _parseScoreThreshold(q);

    // Low-score path — mirrors `_Intent.skip` but acknowledges the framing.
    if (threshold == -1) {
      final pool = catalog.where((c) => c.watcherScore < 65).toList()
        ..sort((a, b) => a.watcherScore.compareTo(b.watcherScore));
      return _respond(
        pool: pool,
        intro: spanish
            ? 'Estos tienen Watcher Score bajo — probablemente puedes saltarlos:'
            : 'These have a low Watcher Score — you can probably skip them:',
        spanish: spanish,
        shuffle: false,
      );
    }

    final cutoff = threshold ?? 80;
    final pool = catalog.where((c) => c.watcherScore >= cutoff).toList()
      ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));

    if (pool.isEmpty) {
      return (
        text: spanish
            ? 'No tengo títulos con Watcher Score $cutoff o mayor en tu catálogo. Prueba bajando un poco el umbral.'
            : 'I don\'t have any titles with a Watcher Score of $cutoff or higher in your catalog. Try lowering the bar a bit.',
        contentIds: const [],
      );
    }

    return _respond(
      pool: pool,
      intro: spanish
          ? 'Top picks por Watcher Score (≥$cutoff):'
          : 'Top picks by Watcher Score (≥$cutoff):',
      spanish: spanish,
      shuffle: false, // already sorted desc by score
    );
  }

  _Intent _detectIntent(String q) {
    // Watcher Score queries — score is visible in every result card so users
    // naturally ask "score arriba de 80" or "watcher score alto". Catch this
    // BEFORE refine so "con score 80" doesn't get treated as a refinement of
    // the previous reply (the word "con" would otherwise hijack it).
    if (_isByScoreQuery(q)) {
      return _Intent.byScore;
    }

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

    // Affirmation — only meaningful when Remoty just offered something.
    // We require a previousReplyText so a stray "ok" out of context still
    // routes to the generic search instead of confusing the user.
    if (previousReplyText != null && _isAffirmation(q)) {
      return _Intent.affirmation;
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

  ({String text, List<String> contentIds}) _respond({
    required List<Content> pool,
    required String intro,
    required bool spanish,
    String? emptyMsg,
    bool shuffle = true,
    bool respectExclusion = true,
  }) {
    // Fase 4: hide titles the user already engaged with (watched, dismissed,
    // rated). Same contract as Home rows + Discover idle. Skipped for
    // explicit lookups (title/director/cast) so the user can still find
    // something they've already rated when they search by name.
    var working = [...pool];
    if (respectExclusion && excluded.isNotEmpty) {
      final filtered = working.where((c) => !excluded.contains(c.id)).toList();
      // Don't filter to oblivion — if exclusion empties the pool, fall back
      // to the unfiltered list so the user gets *something*.
      if (filtered.isNotEmpty) working = filtered;
    }

    if (working.isEmpty) {
      return (
        text: emptyMsg ??
            (spanish ? _randomFrom(_fallbacksEs) : _randomFrom(_fallbacksEn)),
        contentIds: const [],
      );
    }

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

  /// Reorder a candidate list so titles whose genres overlap the user's
  /// `favoriteGenres` come first. Stable for ties: original watcherScore-driven
  /// ordering (or shuffle) inside each tier is preserved.
  ///
  /// No-op when there is no profile or no favorite genres — keeps anonymous
  /// users on the canonical curation.
  List<Content> _weightByFavoriteGenres(List<Content> pool) {
    final favs = userProfile?.favoriteGenres ?? const <String>[];
    if (favs.isEmpty || pool.isEmpty) return pool;
    final favsLower = favs.map((g) => g.toLowerCase()).toSet();
    final boosted = <Content>[];
    final rest = <Content>[];
    for (final c in pool) {
      final hit = c.genres.any((g) {
        final gl = g.toLowerCase();
        return favsLower.any((f) => gl.contains(f) || f.contains(gl));
      });
      (hit ? boosted : rest).add(c);
    }
    return [...boosted, ...rest];
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
  affirmation,
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
  byScore,
  creators,
  platform,
  refine,
  generic,
}
