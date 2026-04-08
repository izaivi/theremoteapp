/// Señales sociales internas del producto — "The Remote Fans Say".
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

/// A short user opinion, ≤230 chars. Anchored to a single Content.
/// Shown in the Content detail as a list, never as a social feed.
class QuickTake {
  final String id;
  final String contentId;

  /// Public alias (separate from the user's real identity / email).
  final String alias;

  /// The take body. Must be ≤230 chars.
  final String body;

  /// Rating the user gave at the time of writing (nullable — can write
  /// a take without rating).
  final int? rating;

  /// Whether the user said it was worth their time.
  final bool? worthMyTime;

  final DateTime createdAt;

  const QuickTake({
    required this.id,
    required this.contentId,
    required this.alias,
    required this.body,
    this.rating,
    this.worthMyTime,
    required this.createdAt,
  });
}
