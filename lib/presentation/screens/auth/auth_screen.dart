import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../../../core/theme/app_colors.dart';
import '../../../data/repositories/auth_repository.dart';

/// Sign-in screen — 4 entry points (Apple, Google, Magic Link, Guest).
///
/// Reachable from:
///   - Profile → "Sign in" card (regular flow)
///   - Splash redirect (when we eventually gate Home behind a session)
///
/// Design philosophy: the user should never feel forced to create an account.
/// Guest is a first-class option, displayed prominently. Apple/Google are
/// the fast paths; Magic Link is the fallback for users who hate social
/// sign-in.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _busy = false;
  bool _magicSent = false;
  String? _error;
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doApple() => _run(() async {
        await ref.read(authRepositoryProvider).signInWithApple();
      });

  /// Google uses Supabase's OAuth browser flow: we launch
  /// ASWebAuthenticationSession and then sit on the auth screen until the
  /// deep link round-trip finishes and `authStateChangesProvider` emits
  /// `signedIn` (handled by the ref.listen in [build]). We therefore do NOT
  /// navigate here — calling context.go('/home') right after signInWithGoogle
  /// returns would fire while the user is still in the browser.
  Future<void> _doGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      // Keep _busy = true so the spinner stays up until either (a) the
      // auth state listener navigates us away, or (b) the user cancels and
      // returns to the auth screen. In case (b) we want to re-enable the
      // buttons — handle that by clearing _busy after a short grace period
      // if no signedIn event arrived.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _busy) setState(() => _busy = false);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _doGuest() => _run(() async {
        await ref.read(authRepositoryProvider).signInAnonymously();
      });

  Future<void> _doMagicLink() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithMagicLink(email);
      if (mounted) setState(() => _magicSent = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // When the deep-link round-trip for Google OAuth (or Magic Link) finishes,
    // Supabase emits AuthChangeEvent.signedIn. If we're still sitting on the
    // auth screen at that moment, pop/navigate to home. This is the piece
    // that closes the loop for the OAuth flow, since _doGoogle doesn't
    // navigate synchronously.
    ref.listen(authStateChangesProvider, (prev, next) {
      next.whenData((state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.signedIn) {
          context.go('/home');
        }
      });
    });

    // When the user lands on /auth as part of the mandatory entry flow
    // (Splash → Auth → Quiz → Home) they don't yet have a session — the
    // close button would just bounce them back here via the router redirect.
    // Only show it if a session already exists (e.g. a signed-in guest who
    // came here from Profile to upgrade to a real account).
    final hasSession = ref.watch(currentUserProvider) != null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: hasSession
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
              )
            : null,
        title: const Text('Sign in'),
      ),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            children: [
              const SizedBox(height: 8),
              Center(
                child: Image.asset(
                  'assets/mascots/mascot_loved.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.lock_outline, size: 72),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Welcome to Flixscope',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sign in to sync your ratings, vault, and follows across devices — or jump in as a guest.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
              const SizedBox(height: 28),

              // ---- Apple ----
              _ProviderButton(
                icon: Icons.apple,
                label: 'Continue with Apple',
                background: Colors.black,
                foreground: Colors.white,
                onPressed: _doApple,
              ),
              const SizedBox(height: 10),

              // ---- Google ----
              _ProviderButton(
                icon: Icons.g_mobiledata,
                label: 'Continue with Google',
                background: Colors.white,
                foreground: Colors.black87,
                bordered: true,
                onPressed: _doGoogle,
              ),
              const SizedBox(height: 18),

              const Row(children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: TextStyle(color: AppColors.textMuted)),
                ),
                Expanded(child: Divider()),
              ]),
              const SizedBox(height: 18),

              // ---- Magic Link ----
              if (!_magicSent) ...[
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'you@example.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                _ProviderButton(
                  icon: Icons.mail_outline,
                  label: 'Email me a magic link',
                  background: AppColors.accent,
                  foreground: Colors.white,
                  onPressed: _doMagicLink,
                ),
              ] else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.accent, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        "Check your inbox — we sent a sign-in link to ${_emailCtrl.text.trim()}.",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 22),

              // ---- Guest ----
              TextButton(
                onPressed: _doGuest,
                child: const Text(
                  'Continue as guest',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],

              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final bool bordered;
  final VoidCallback onPressed;

  const _ProviderButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22, color: foreground),
        label: Text(
          label,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: foreground),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: bordered
                ? const BorderSide(color: Colors.black12)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
