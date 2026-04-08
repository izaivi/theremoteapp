import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/prefs/language_prefs.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';

void main() {
  runApp(const ProviderScope(child: TheRemoteApp()));
}

class TheRemoteApp extends ConsumerWidget {
  const TheRemoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(uiLocaleProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'The Remote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: router,

      // i18n — only EN and ES are supported.
      // Resolution rules live in `uiLocaleProvider`:
      //   1. User override from Profile → Settings wins.
      //   2. Else device locale: es-* → ES, anything else → EN.
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
