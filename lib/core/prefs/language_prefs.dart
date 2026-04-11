import 'dart:ui' show Locale;

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The 3 independent axes the user can override in Profile → Settings.
///
/// All three default to `null`, which means "auto-detect from the device /
/// system locale". The user can override any of them independently.
///
/// Supported values:
///   uiLanguage:      'en' | 'es' | null
///   contentLanguage: 'en' | 'es' | null
///   country:         ISO-3166 alpha-2 uppercase (e.g. 'US', 'MX', 'ES') | null
class LanguagePrefs {
  final String? uiLanguage;
  final String? contentLanguage;
  final String? country;

  const LanguagePrefs({
    this.uiLanguage,
    this.contentLanguage,
    this.country,
  });

  static const empty = LanguagePrefs();

  LanguagePrefs copyWith({
    Object? uiLanguage = _sentinel,
    Object? contentLanguage = _sentinel,
    Object? country = _sentinel,
  }) {
    return LanguagePrefs(
      uiLanguage:
          identical(uiLanguage, _sentinel) ? this.uiLanguage : uiLanguage as String?,
      contentLanguage: identical(contentLanguage, _sentinel)
          ? this.contentLanguage
          : contentLanguage as String?,
      country: identical(country, _sentinel) ? this.country : country as String?,
    );
  }

  static const _sentinel = Object();
}

/// SharedPreferences keys. Kept as constants so we never drift.
class _PrefsKeys {
  static const uiLanguage = 'prefs.uiLanguage';
  static const contentLanguage = 'prefs.contentLanguage';
  static const country = 'prefs.country';
}

/// StateNotifier that loads prefs from disk on start and persists every change.
class LanguagePrefsController extends StateNotifier<LanguagePrefs> {
  LanguagePrefsController() : super(LanguagePrefs.empty) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = LanguagePrefs(
      uiLanguage: p.getString(_PrefsKeys.uiLanguage),
      contentLanguage: p.getString(_PrefsKeys.contentLanguage),
      country: p.getString(_PrefsKeys.country),
    );
  }

  Future<void> setUiLanguage(String? code) async {
    state = state.copyWith(uiLanguage: code);
    final p = await SharedPreferences.getInstance();
    if (code == null) {
      await p.remove(_PrefsKeys.uiLanguage);
    } else {
      await p.setString(_PrefsKeys.uiLanguage, code);
    }
  }

  Future<void> setContentLanguage(String? code) async {
    state = state.copyWith(contentLanguage: code);
    final p = await SharedPreferences.getInstance();
    if (code == null) {
      await p.remove(_PrefsKeys.contentLanguage);
    } else {
      await p.setString(_PrefsKeys.contentLanguage, code);
    }
  }

  Future<void> setCountry(String? code) async {
    state = state.copyWith(country: code);
    final p = await SharedPreferences.getInstance();
    if (code == null) {
      await p.remove(_PrefsKeys.country);
    } else {
      await p.setString(_PrefsKeys.country, code);
    }
  }
}

final languagePrefsProvider =
    StateNotifierProvider<LanguagePrefsController, LanguagePrefs>(
  (ref) => LanguagePrefsController(),
);

/// Derives the effective UI [Locale] from prefs + system.
///
/// Rules (as agreed with Vivi 2026-04-07):
/// - If the user forced a UI language in Settings → use it as-is.
/// - Else, if the device locale is `es-*` → Spanish.
/// - Else (en-*, de-*, fr-*, it-*, ...) → English fallback.
///
/// Only `en` and `es` are supported by the app. Any other forced or detected
/// language collapses to English.
final uiLocaleProvider = Provider<Locale?>((ref) {
  final prefs = ref.watch(languagePrefsProvider);

  if (prefs.uiLanguage == 'es') return const Locale('es');
  if (prefs.uiLanguage == 'en') return const Locale('en');

  // Auto: follow system.
  final system = WidgetsBinding.instance.platformDispatcher.locale;
  if (system.languageCode == 'es') return const Locale('es');
  return const Locale('en');
});

/// The country code the rest of the app should use when querying regional
/// availability. Falls back to the device country, then 'US' as last resort.
final effectiveCountryProvider = Provider<String>((ref) {
  final prefs = ref.watch(languagePrefsProvider);
  final c = prefs.country;
  // 'XX' = "Rest of the world" (explicit user pick for unlisted markets).
  // Treat as auto: fall back to system country, then 'US' as last resort.
  if (c != null && c.isNotEmpty && c != 'XX') return c;
  final system = WidgetsBinding.instance.platformDispatcher.locale;
  return (system.countryCode ?? 'US').toUpperCase();
});

/// The language that should be used to fetch synopses, reviews, etc.
/// Falls back to the effective UI language.
final effectiveContentLanguageProvider = Provider<String>((ref) {
  final prefs = ref.watch(languagePrefsProvider);
  if (prefs.contentLanguage == 'es') return 'es';
  if (prefs.contentLanguage == 'en') return 'en';
  final uiLocale = ref.watch(uiLocaleProvider);
  return uiLocale?.languageCode ?? 'en';
});
