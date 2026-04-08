import '../models/content.dart';
import '../mock/mock_content.dart';

/// Interfaz pensada para que SupabaseContentRepository la implemente
/// en Fase 1 del backend. Por ahora solo el mock.
abstract class ContentRepository {
  Future<List<Content>> getTrending({required String countryCode});
  Future<List<Content>> getExploding({required String countryCode});
  Future<List<Gem>> getDailyGems({
    required String countryCode,
    required UserPlan tier,
  });
}

class MockContentRepository implements ContentRepository {
  @override
  Future<List<Content>> getTrending({required String countryCode}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return MockContent.trending;
  }

  @override
  Future<List<Content>> getExploding({required String countryCode}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return MockContent.trending
        .where((c) => c.hypeLevel == HypeLevel.extreme)
        .toList();
  }

  @override
  Future<List<Gem>> getDailyGems({
    required String countryCode,
    required UserPlan tier,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final all = MockContent.dailyGems;
    if (tier == UserPlan.pro) return all.take(5).toList();
    return all.take(3).toList(); // Free tier ve 3 de 5
  }
}
