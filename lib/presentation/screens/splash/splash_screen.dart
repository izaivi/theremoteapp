import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';

/// Splash / Welcome screen.
///
/// Full-bleed hero image (hand holding the glowing remote) with a dark
/// gradient overlay at the bottom for the tagline + CTA. Tapping the
/// button routes to `/home` — the router redirect then decides whether
/// to show onboarding or the real Home depending on quiz completion.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- Hero image ---
          Image.asset(
            'assets/images/startapp.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),

          // --- Dark gradient so text is always readable ---
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.45, 1.0],
                colors: [
                  Colors.transparent,
                  Color(0x33000000),
                  Color(0xEE000000),
                ],
              ),
            ),
          ),

          // --- Copy + CTA ---
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    l10n.splashTagline,
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(
                          color: Color(0xAA4F8CFF),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.splashSubtitle,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => context.go('/home'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F8CFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                        elevation: 0,
                      ),
                      child: Text(l10n.splashCta),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
