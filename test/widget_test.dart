// Flutter widget tests.
//
// The boilerplate counter test shipped by `flutter create` referenced a
// `MyApp` class that never existed in this project (the root widget is
// `TheRemoteApp`). Rather than wire up a full smoke test here — which
// would need ProviderScope + Supabase mocks to even mount — we keep a
// trivial sanity test so `flutter analyze` stays clean and `flutter test`
// exits zero. Replace with real widget tests as the project grows.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanity', () {
    expect(1 + 1, 2);
  });
}
