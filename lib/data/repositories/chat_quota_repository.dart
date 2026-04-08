import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Daily AI chat quota for free users.
///
/// Free = 5 questions/day. Pro = unlimited (handled at call site).
/// Resets at local midnight — we compare the stored reset date to today's
/// date and wipe the counter on the first access of a new day.
class ChatQuotaState {
  final int used;
  final int limit;
  final DateTime resetDate; // date-only (midnight)

  const ChatQuotaState({
    required this.used,
    required this.limit,
    required this.resetDate,
  });

  int get remaining => (limit - used).clamp(0, limit);
  bool get exhausted => used >= limit;

  ChatQuotaState copyWith({int? used, int? limit, DateTime? resetDate}) =>
      ChatQuotaState(
        used: used ?? this.used,
        limit: limit ?? this.limit,
        resetDate: resetDate ?? this.resetDate,
      );
}

class ChatQuotaRepository {
  static const _keyUsed = 'chat.quota.used.v1';
  static const _keyDate = 'chat.quota.date.v1';

  static const int freeDailyLimit = 5;

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<ChatQuotaState> load() async {
    final p = await SharedPreferences.getInstance();
    final storedDateStr = p.getString(_keyDate);
    final today = _today();

    // First run or new day → reset.
    if (storedDateStr == null || DateTime.tryParse(storedDateStr) != today) {
      await p.setString(_keyDate, today.toIso8601String());
      await p.setInt(_keyUsed, 0);
      return ChatQuotaState(
        used: 0,
        limit: freeDailyLimit,
        resetDate: today,
      );
    }

    final used = p.getInt(_keyUsed) ?? 0;
    return ChatQuotaState(
      used: used,
      limit: freeDailyLimit,
      resetDate: today,
    );
  }

  Future<void> increment() async {
    final p = await SharedPreferences.getInstance();
    final used = (p.getInt(_keyUsed) ?? 0) + 1;
    await p.setInt(_keyUsed, used);
  }

  Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyUsed, 0);
    await p.setString(_keyDate, _today().toIso8601String());
  }
}

final chatQuotaRepositoryProvider =
    Provider<ChatQuotaRepository>((ref) => ChatQuotaRepository());

class ChatQuotaController extends StateNotifier<ChatQuotaState> {
  ChatQuotaController(this._repo)
      : super(ChatQuotaState(
          used: 0,
          limit: ChatQuotaRepository.freeDailyLimit,
          resetDate: DateTime.now(),
        )) {
    _init();
  }

  final ChatQuotaRepository _repo;

  Future<void> _init() async {
    state = await _repo.load();
  }

  /// Consume one question. Returns true if the question was allowed,
  /// false if the user hit the cap (caller should trigger paywall).
  Future<bool> consume() async {
    // Reload in case day changed since app open.
    final fresh = await _repo.load();
    state = fresh;
    if (fresh.exhausted) return false;
    await _repo.increment();
    state = fresh.copyWith(used: fresh.used + 1);
    return true;
  }
}

final chatQuotaProvider =
    StateNotifierProvider<ChatQuotaController, ChatQuotaState>(
  (ref) => ChatQuotaController(ref.watch(chatQuotaRepositoryProvider)),
);
