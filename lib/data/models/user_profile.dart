/// User profile & onboarding quiz models.
///
/// V1 uses plain Dart classes (no freezed yet) to match the rest of
/// `data/models/` until F-3 migrates everything.
///
/// These models bootstrap the per-user `awarenessScore` needed by the
/// 5 Gems engine V3 (see `5_gems_engine.txt` V2→V3 changelog): without any
/// history, the app has no way to know which titles are "already on the
/// user's radar". The onboarding quiz solves this by asking the user to
/// mark a curated grid of canonical titles they've already seen.

/// Progress through the onboarding quiz.
///
/// The quiz is split in two tiers (decided 2026-04-07):
///
///   - [fast]: country + platforms (min 1) + genres. ~60 seconds, mandatory.
///     Enough to render Home with basic 5 Gems. `awarenessScore` defaults
///     to 0.5 (neutral) for all titles and `classicDiscoveryBoost` is
///     disabled — a Fast-only user will not see classics in their daily
///     5 Gems. This is the honest incentive to complete the Long Quiz.
///
///   - [long]: fast fields + loved-recent titles + seen-canon grid
///     (universal, ~20-30 titles) + session length + favorite themes.
///     3-5 minutes, optional. Unlocks real `awarenessScore` computation
///     and the classic-discovery path in 5 Gems.
enum QuizCompletion { none, fast, long }

enum SessionLength {
  /// Short sessions. Feeds the "Quick Decision" Home section.
  short, // < 90 min

  /// Default bucket — 1 to 3h, movies or a couple of episodes.
  medium,

  /// Full binge: long movies or multi-episode sessions.
  long,
}

/// Answers captured during the onboarding quiz (Fast + optional Long).
///
/// Fast Quiz (mandatory, ≤60s):
///   1. Country (auto-detect, confirmable)
///   2. Active platforms (min 1 — without platforms a gem is useless)
///   3. Favorite genres (3-5 chips)
///
/// Long Quiz (optional, promptable later):
///   4. Loved recent titles → lovedRecentIds
///   5. Seen-canon grid (universal, ~20-30 canonical titles) → seenCanonIds
///   6. Session length → sessionLength
///   7. Favorite themes / directors / actors (free text) → favoriteThemes
class QuizAnswers {
  // --- Fast Quiz fields (always present after onboarding) ---

  /// Favorite genres selected in the Fast Quiz.
  final List<String> favoriteGenres;

  // --- Long Quiz fields (empty until the user completes Long) ---

  /// Titles the user marked as "seen recently and loved".
  /// Strong signal of current taste profile.
  final List<String> lovedRecentIds;

  /// Titles from the onboarding canon grid the user has already seen.
  /// Used to bootstrap `awarenessScore` + `watchedIds` from minute zero.
  final List<String> seenCanonIds;

  /// Preferred session length bucket.
  final SessionLength sessionLength;

  /// Free-text themes, directors, actors, tags the user cares about.
  /// Feeds thematic affinity beyond genre matching.
  final List<String> favoriteThemes;

  const QuizAnswers({
    this.favoriteGenres = const [],
    this.lovedRecentIds = const [],
    this.seenCanonIds = const [],
    this.sessionLength = SessionLength.medium,
    this.favoriteThemes = const [],
  });

  static const empty = QuizAnswers();

  QuizAnswers copyWith({
    List<String>? favoriteGenres,
    List<String>? lovedRecentIds,
    List<String>? seenCanonIds,
    SessionLength? sessionLength,
    List<String>? favoriteThemes,
  }) {
    return QuizAnswers(
      favoriteGenres: favoriteGenres ?? this.favoriteGenres,
      lovedRecentIds: lovedRecentIds ?? this.lovedRecentIds,
      seenCanonIds: seenCanonIds ?? this.seenCanonIds,
      sessionLength: sessionLength ?? this.sessionLength,
      favoriteThemes: favoriteThemes ?? this.favoriteThemes,
    );
  }
}

/// The user's running profile. Built from the quiz at onboarding and
/// updated continuously from in-app behavior.
///
/// Will eventually live in Supabase `profiles` (see BITACORA schema draft).
/// Until then, persisted locally via SharedPreferences + JSON.
class UserProfile {
  /// Supabase auth id. Null while the user is in anonymous / device-only mode.
  final String? id;

  /// Public alias (only set after first write attempt — see auth decisions).
  final String? alias;

  /// ISO-3166 alpha-2 country code. Drives availability queries.
  final String? country;

  /// Active streaming platforms the user actually pays for.
  final List<String> activePlatforms;

  /// Favorite genres — seeded from quiz, refined by behavior.
  final List<String> favoriteGenres;

  /// Session length preference — only meaningful after Long Quiz.
  final SessionLength sessionLength;

  /// Free-text themes / directors / actors. Empty until Long Quiz.
  final List<String> favoriteThemes;

  /// Every title the user has explicitly marked as "seen".
  /// This is the authoritative set for `awarenessScore` computation.
  /// Empty for Fast-only users (awarenessScore defaults to 0.5 neutral).
  final Set<String> watchedIds;

  /// Titles the user explicitly dismissed ("not interested").
  /// Excluded from gem candidates.
  final Set<String> dismissedIds;

  /// How far the user has progressed through onboarding.
  /// Gates whether classics can appear in their 5 Gems (long required).
  final QuizCompletion quizCompletion;

  /// Tier — 'free' | 'pro'.
  final String tier;

  const UserProfile({
    this.id,
    this.alias,
    this.country,
    this.activePlatforms = const [],
    this.favoriteGenres = const [],
    this.sessionLength = SessionLength.medium,
    this.favoriteThemes = const [],
    this.watchedIds = const {},
    this.dismissedIds = const {},
    this.quizCompletion = QuizCompletion.none,
    this.tier = 'free',
  });

  static const anonymous = UserProfile();

  /// Build a profile from the Fast Quiz (mandatory onboarding).
  ///
  /// Country and at least one platform are required. Without a platform
  /// the best gem in the world is useless — the user couldn't watch it.
  factory UserProfile.fromFastQuiz({
    required String country,
    required List<String> activePlatforms,
    required List<String> favoriteGenres,
  }) {
    assert(activePlatforms.isNotEmpty,
        'Fast Quiz requires at least one active platform.');
    return UserProfile(
      country: country,
      activePlatforms: activePlatforms,
      favoriteGenres: favoriteGenres,
      quizCompletion: QuizCompletion.fast,
    );
  }

  /// Upgrade an existing Fast profile with Long Quiz answers.
  ///
  /// Merges `seenCanonIds` and `lovedRecentIds` into `watchedIds` to
  /// bootstrap `awarenessScore` from minute zero. This is the moment
  /// the engine unlocks `classicDiscoveryBoost` for this user.
  UserProfile withLongQuiz(QuizAnswers answers) {
    return copyWith(
      favoriteGenres: answers.favoriteGenres.isEmpty
          ? favoriteGenres
          : answers.favoriteGenres,
      sessionLength: answers.sessionLength,
      favoriteThemes: answers.favoriteThemes,
      watchedIds: {
        ...watchedIds,
        ...answers.seenCanonIds,
        ...answers.lovedRecentIds,
      },
      quizCompletion: QuizCompletion.long,
    );
  }

  /// Convenience: whether the engine should enable classic discovery for
  /// this user. Mirrors the `classicDiscoveryBoost` gate in engine V3.1.
  bool get canReceiveClassics => quizCompletion == QuizCompletion.long;

  UserProfile copyWith({
    String? id,
    String? alias,
    String? country,
    List<String>? activePlatforms,
    List<String>? favoriteGenres,
    SessionLength? sessionLength,
    List<String>? favoriteThemes,
    Set<String>? watchedIds,
    Set<String>? dismissedIds,
    QuizCompletion? quizCompletion,
    String? tier,
  }) {
    return UserProfile(
      id: id ?? this.id,
      alias: alias ?? this.alias,
      country: country ?? this.country,
      activePlatforms: activePlatforms ?? this.activePlatforms,
      favoriteGenres: favoriteGenres ?? this.favoriteGenres,
      sessionLength: sessionLength ?? this.sessionLength,
      favoriteThemes: favoriteThemes ?? this.favoriteThemes,
      watchedIds: watchedIds ?? this.watchedIds,
      dismissedIds: dismissedIds ?? this.dismissedIds,
      quizCompletion: quizCompletion ?? this.quizCompletion,
      tier: tier ?? this.tier,
    );
  }
}
