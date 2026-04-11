/// Señales sociales internas del producto — "Flixscope Fans Say".
///
/// Estos modelos representan lo que el backend devolverá por cada Content:
/// (a) estadística agregada (stats) y (b) una lista de quick takes recientes.
///
/// El agregado alimenta el 10% "Señales internas" del Watcher Score. Los
/// quick takes son visibles pero no son "reviews largas" — máximo 230 chars.

/// Aggregate internal signal for a piece of content, derived from verified
/// user interactions. Mirrors what `content.internal_signals` will expose in
/// Supabase once the backend lands.
class FansSayStats {
  /// Percentage of verified watchers who finished the content (0-100).
  final int completionRate;

  /// Percentage of verified watchers who answered "worth my time = yes".
  final int worthMyTimePct;

  /// Average star rating from verified watchers (1.0-5.0).
  final double avgRating;

  /// Total number of verified watchers that contributed any signal.
  /// Displayed as transparency metric — "n=1,248 verified watchers".
  final int sampleSize;

  const FansSayStats({
    required this.completionRate,
    required this.worthMyTimePct,
    required this.avgRating,
    required this.sampleSize,
  });

  /// Whether this content has enough signal to show the "Fans Say" block.
  /// Below this threshold, stats are too noisy to surface.
  bool get hasEnoughSignal => sampleSize >= 50;
}

/// Legacy mock quick take — replaced by `quick_take.dart` model.
/// Kept only for mock data compatibility during migration.
class MockQuickTake {
  final String id;
  final String contentId;
  final String alias;
  final String body;
  final int? rating;
  final bool? worthMyTime;
  final DateTime createdAt;

  const MockQuickTake({
    required this.id,
    required this.contentId,
    required this.alias,
    required this.body,
    this.rating,
    this.worthMyTime,
    required this.createdAt,
  });
}
