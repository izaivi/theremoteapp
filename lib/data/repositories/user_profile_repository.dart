import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

/// Persists [UserProfile] locally via SharedPreferences as a JSON blob.
///
/// In Fase 1 del backend this will sync to Supabase `profiles`. Until then,
/// everything stays local. Kept as plain JSON (no freezed codegen) to match
/// the rest of `data/models/` bootstrap approach.
class UserProfileRepository {
  static const _key = 'user.profile.v1';

  Future<UserProfile> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return UserProfile.anonymous;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _fromJson(json);
    } catch (_) {
      // Corrupted blob — reset rather than crash.
      return UserProfile.anonymous;
    }
  }

  Future<void> save(UserProfile profile) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(_toJson(profile)));
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }

  // ---- JSON codec -----------------------------------------------------------

  Map<String, dynamic> _toJson(UserProfile p) => {
        'id': p.id,
        'alias': p.alias,
        'country': p.country,
        'activePlatforms': p.activePlatforms,
        'favoriteGenres': p.favoriteGenres,
        'sessionLength': p.sessionLength.name,
        'favoriteThemes': p.favoriteThemes,
        'watchedIds': p.watchedIds.toList(),
        'dismissedIds': p.dismissedIds.toList(),
        'quizCompletion': p.quizCompletion.name,
        'tier': p.tier,
      };

  UserProfile _fromJson(Map<String, dynamic> j) {
    return UserProfile(
      id: j['id'] as String?,
      alias: j['alias'] as String?,
      country: j['country'] as String?,
      activePlatforms: (j['activePlatforms'] as List?)?.cast<String>() ?? const [],
      favoriteGenres: (j['favoriteGenres'] as List?)?.cast<String>() ?? const [],
      sessionLength: SessionLength.values.firstWhere(
        (e) => e.name == j['sessionLength'],
        orElse: () => SessionLength.medium,
      ),
      favoriteThemes: (j['favoriteThemes'] as List?)?.cast<String>() ?? const [],
      watchedIds: ((j['watchedIds'] as List?)?.cast<String>() ?? const []).toSet(),
      dismissedIds:
          ((j['dismissedIds'] as List?)?.cast<String>() ?? const []).toSet(),
      quizCompletion: QuizCompletion.values.firstWhere(
        (e) => e.name == j['quizCompletion'],
        orElse: () => QuizCompletion.none,
      ),
      tier: j['tier'] as String? ?? 'free',
    );
  }
}

final userProfileRepositoryProvider =
    Provider<UserProfileRepository>((ref) => UserProfileRepository());

/// Global source of truth for the current user's profile.
///
/// Loads from disk on first read. Every mutation persists immediately so
/// there's no "save" button anywhere — the UI is always a reflection of
/// the stored state. Router redirects watch this to gate Home behind
/// onboarding completion.
class UserProfileController extends StateNotifier<UserProfile> {
  UserProfileController(this._repo) : super(UserProfile.anonymous) {
    _load();
  }

  final UserProfileRepository _repo;

  Future<void> _load() async {
    state = await _repo.load();
  }

  Future<void> completeFastQuiz({
    required String country,
    required List<String> activePlatforms,
    required List<String> favoriteGenres,
  }) async {
    final next = UserProfile.fromFastQuiz(
      country: country,
      activePlatforms: activePlatforms,
      favoriteGenres: favoriteGenres,
    );
    state = next;
    await _repo.save(next);
  }

  Future<void> completeLongQuiz(QuizAnswers answers) async {
    final next = state.withLongQuiz(answers);
    state = next;
    await _repo.save(next);
  }

  Future<void> markWatched(String contentId) async {
    final next = state.copyWith(watchedIds: {...state.watchedIds, contentId});
    state = next;
    await _repo.save(next);
  }

  Future<void> dismiss(String contentId) async {
    final next =
        state.copyWith(dismissedIds: {...state.dismissedIds, contentId});
    state = next;
    await _repo.save(next);
  }

  /// Hard reset — used from dev / debug / settings "sign out".
  Future<void> reset() async {
    state = UserProfile.anonymous;
    await _repo.clear();
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileController, UserProfile>(
  (ref) => UserProfileController(ref.watch(userProfileRepositoryProvider)),
);
