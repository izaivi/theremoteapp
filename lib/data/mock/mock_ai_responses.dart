import 'dart:math';

import '../models/content.dart';
import 'mock_content.dart';

/// Stub "AI" response generator. Until we wire Claude/OpenAI, this produces
/// believable mock responses by keyword-matching the user query against the
/// catalog and picking 1-3 relevant titles.
///
/// Intentionally lightweight. Real intent parsing + grounding on the user's
/// profile happens server-side in V1 of the backend.
class MockAiResponder {
  static final _rng = Random();

  static ({String text, List<String> contentIds}) reply(String userMessage) {
    final q = userMessage.toLowerCase().trim();

    if (q.isEmpty) {
      return (
        text: 'Tell me what you\'re in the mood for and I\'ll find something.',
        contentIds: const [],
      );
    }

    // --- Mood / intent detection ---
    final isShort = _any(q, [
      'short',
      'corto',
      'quick',
      'rápido',
      'rapido',
      'tonight',
      'esta noche',
      '<90',
      'hora y media'
    ]);
    final isBinge = _any(q, [
      'binge',
      'series',
      'serie',
      'marathon',
      'maratón',
      'weekend',
      'fin de semana'
    ]);
    final isSad = _any(q, [
      'sad',
      'triste',
      'cry',
      'llorar',
      'emotional',
      'emocional',
      'heartbreak'
    ]);
    final isAction = _any(q, ['action', 'acción', 'accion', 'fight', 'crime']);
    final isSciFi = _any(q, ['sci-fi', 'scifi', 'ciencia', 'space', 'futuro']);
    final isClassic = _any(q, ['classic', 'clásico', 'clasico', 'old', 'viejo']);
    final isSkip = _any(q, [
      'avoid',
      'skip',
      'overrated',
      'evitar',
      'saltar',
      'sobrevalorada',
      'sobrevalorado'
    ]);

    // --- Pick candidates from catalog views ---
    List<Content> pool;
    String intro;

    if (isSkip) {
      pool = MockContent.dontWaste;
      intro = 'Honestly? These are getting hype but the numbers say skip:';
    } else if (isShort) {
      pool = MockContent.quickDecision;
      intro = 'Short, high-quality, ready for tonight:';
    } else if (isBinge) {
      pool = MockContent.catalog
          .where((c) => c.type == ContentType.series && c.watcherScore >= 85)
          .toList();
      intro = 'These are the series worth your weekend:';
    } else if (isSad) {
      pool = MockContent.catalog
          .where((c) =>
              c.tags.any((t) =>
                  t.contains('emotional') ||
                  t.contains('devastating') ||
                  t.contains('quiet')) &&
              c.watcherScore >= 85)
          .toList();
      intro = 'If you want something that\'ll hit you in the chest:';
    } else if (isSciFi) {
      pool = MockContent.catalog
          .where((c) => c.genres.any((g) => g.toLowerCase().contains('sci')))
          .toList();
      intro = 'Sci-fi picks that actually deliver:';
    } else if (isAction) {
      pool = MockContent.catalog
          .where((c) => c.genres.any((g) =>
              g.toLowerCase().contains('action') ||
              g.toLowerCase().contains('crime') ||
              g.toLowerCase().contains('thriller')))
          .where((c) => c.watcherScore >= 80)
          .toList();
      intro = 'Tight, high-craft action:';
    } else if (isClassic) {
      pool =
          MockContent.catalog.where((c) => c.id.startsWith('c-classic')).toList();
      intro = 'Classics worth revisiting (or discovering):';
    } else {
      // Generic fallback: top 3 by Watcher Score from catalog.
      pool = [...MockContent.catalog]
        ..sort((a, b) => b.watcherScore.compareTo(a.watcherScore));
      intro = 'Here\'s what the Watcher Score is loving right now:';
    }

    if (pool.isEmpty) {
      return (
        text:
            'Nothing in the catalog perfectly matches that — try asking for a mood, genre, or runtime.',
        contentIds: const [],
      );
    }

    pool.shuffle(_rng);
    final picks = pool.take(3).toList();
    final reasonsLine = picks
        .map((c) => '• **${c.title}** (${c.year}) — Watcher Score ${c.watcherScore}')
        .join('\n');

    return (
      text: '$intro\n\n$reasonsLine',
      contentIds: picks.map((c) => c.id).toList(),
    );
  }

  static bool _any(String text, List<String> keys) =>
      keys.any((k) => text.contains(k));
}
