import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  // Bottom nav: Home · Discover · Vault (Mi Bóveda) · Creators · Remoty.
  // Settings moved out of the shell — accessible via gear icon in Home header.
  static const _routes = [
    '/home',
    '/discover',
    '/vault',
    '/creators',
    '/chat',
  ];

  static const _icons = [
    Icons.home_outlined,
    Icons.search,
    Icons.bookmark_outline,
    Icons.movie_filter_outlined,
    Icons.smart_toy_outlined,
  ];

  int _indexFromLocation(String loc) {
    for (var i = 0; i < _routes.length; i++) {
      if (loc.startsWith(_routes[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final loc = GoRouterState.of(context).uri.toString();
    final idx = _indexFromLocation(loc);

    final labels = [
      l10n.tabHome,
      l10n.tabDiscover,
      l10n.tabVault,
      l10n.tabCreators,
      l10n.tabAi,
    ];

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        onTap: (i) => context.go(_routes[i]),
        items: [
          for (var i = 0; i < _routes.length; i++)
            BottomNavigationBarItem(icon: Icon(_icons[i]), label: labels[i]),
        ],
      ),
    );
  }
}
