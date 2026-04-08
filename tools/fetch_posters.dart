// Fetches TMDB poster paths for every title in the mock catalog and prints
// a Dart map you can paste into `lib/data/mock/mock_content.dart`.
//
// Usage:
//   1. Create `the-remote-flutter/.env` with one line:
//        TMDB_TOKEN=eyJhbGci... (your v4 Read Access Token)
//      (.env is gitignored, token never enters the repo)
//   2. From `the-remote-flutter/`:
//        dart run tools/fetch_posters.dart
//   3. Copy the printed block into `mock_content.dart` (instructions in output).
//
// No external dependencies — uses dart:io HttpClient only.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Mock catalog — ids, titles, years, and expected media type.
// Keep this list in sync with lib/data/mock/mock_content.dart when you add
// new titles, then re-run the script.
// ---------------------------------------------------------------------------

const _items = <_Item>[
  _Item('c-1', 'The Bear', 2024, 'tv'),
  _Item('c-2', 'Severance', 2022, 'tv'),
  _Item('c-3', 'Shogun', 2024, 'tv'),
  _Item('c-4', 'Ripley', 2024, 'tv'),
  _Item('c-5', 'The Holdovers', 2023, 'movie'),
  _Item('c-6', 'Past Lives', 2023, 'movie'),
  _Item('c-7', 'Aftersun', 2022, 'movie'),
  _Item('c-classic-1', 'Blade Runner', 1982, 'movie'),
  _Item('c-classic-2', 'Heat', 1995, 'movie'),
  _Item('c-classic-3', 'Eternal Sunshine of the Spotless Mind', 2004, 'movie'),
  _Item('c-8', 'Argylle', 2024, 'movie'),
  _Item('c-9', 'Madame Web', 2024, 'movie'),
];

class _Item {
  final String id;
  final String title;
  final int year;
  final String mediaType; // 'movie' | 'tv'
  const _Item(this.id, this.title, this.year, this.mediaType);
}

// ---------------------------------------------------------------------------

Future<void> main() async {
  final token = _readToken();
  if (token == null) {
    stderr.writeln(
        'ERROR: could not read TMDB_TOKEN. Create `.env` with TMDB_TOKEN=... '
        'at the project root and try again.');
    exit(1);
  }

  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);

  final results = <String, String>{};
  for (final item in _items) {
    try {
      final posterPath = await _search(client, token, item);
      if (posterPath == null) {
        stderr.writeln('✗ ${item.id} — ${item.title}: no match');
        continue;
      }
      results[item.id] = 'https://image.tmdb.org/t/p/w500$posterPath';
      stdout.writeln('✓ ${item.id} — ${item.title}: $posterPath');
    } catch (e) {
      stderr.writeln('✗ ${item.id} — ${item.title}: $e');
    }
  }

  client.close();

  stdout.writeln('\n---\n');
  stdout.writeln('// Paste this map into mock_content.dart (top of the file):');
  stdout.writeln('const Map<String, String> kPosterUrls = {');
  for (final e in results.entries) {
    stdout.writeln("  '${e.key}': '${e.value}',");
  }
  stdout.writeln('};');
  stdout.writeln(
      '\n// Then in each Content(...) add: posterUrl: kPosterUrls[\'<id>\'],');
}

Future<String?> _search(
    HttpClient client, String token, _Item item) async {
  // Use media-type-specific endpoint — more reliable than /search/multi.
  final endpoint = item.mediaType == 'tv' ? 'tv' : 'movie';
  final yearParam =
      item.mediaType == 'tv' ? 'first_air_date_year' : 'primary_release_year';
  final uri = Uri.https('api.themoviedb.org', '/3/search/$endpoint', {
    'query': item.title,
    yearParam: '${item.year}',
    'include_adult': 'false',
    'language': 'en-US',
  });

  final req = await client.getUrl(uri);
  req.headers.add('Authorization', 'Bearer $token');
  req.headers.add('accept', 'application/json');
  final res = await req.close();
  if (res.statusCode != 200) {
    throw 'HTTP ${res.statusCode}';
  }
  final body = await res.transform(utf8.decoder).join();
  final json = jsonDecode(body) as Map<String, dynamic>;
  final list = (json['results'] as List?) ?? const [];
  if (list.isEmpty) return null;
  final first = list.first as Map<String, dynamic>;
  return first['poster_path'] as String?;
}

String? _readToken() {
  // Priority: env var → .env file
  final envVar = Platform.environment['TMDB_TOKEN'];
  if (envVar != null && envVar.isNotEmpty) return envVar;

  final envFile = File('.env');
  if (!envFile.existsSync()) return null;
  for (final line in envFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final idx = trimmed.indexOf('=');
    if (idx < 0) continue;
    final key = trimmed.substring(0, idx).trim();
    final value = trimmed.substring(idx + 1).trim();
    if (key == 'TMDB_TOKEN') return value;
  }
  return null;
}
