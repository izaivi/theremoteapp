import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../l10n/app_localizations.dart';

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

  /// Apple, like Google, does NOT navigate inline. Earlier we used `_run(...)`
  /// here which synchronously calls `context.go('/home')` the moment the
  /// native Apple sheet resolves. That raced with the `AuthChangeEvent.signedIn`
  /// listener below (which ALSO navigates to /home) and with main.dart's
  /// signedIn handler that triggers `refreshFromRemote` on all repositories
  /// — the first rebuild of /auth during that window sometimes landed back
  /// on the auth screen ("veo mi carita y regresa al login" in Build 12).
  ///
  /// Fix: let the listener own navigation. Keep `_busy = true` until either
  /// (a) `signedIn` fires and we route away, or (b) the user cancels Apple.
  /// Same pattern as `_doGoogle`.
  Future<void> _doApple() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithApple();
      // Grace window for the deep-link + signedIn event. If the listener
      // hasn't navigated us away in 2s, clear busy so buttons re-enable
      // (covers "user cancelled Apple sheet" case on some iOS versions).
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

  /// Google uses the native iOS Google Sign-In sheet (Build 15+). The sheet
  /// presents inline, the user picks an account, the OS dismisses the sheet,
  /// and `signInWithGoogle` returns an `AuthResponse` once the id_token has
  /// been exchanged with Supabase. We don't navigate inline — the
  /// `currentUserProvider` listener in [build] detects null → User and
  /// routes to /home. Same pattern as `_doApple`.
  Future<void> _doGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      // Grace window: if the user cancels the Google sheet we get back
      // here quickly and want the buttons re-enabled.
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
      // Supabase has queued the 6-digit code email. Route to the OTP verify
      // screen where the user types the code. The old "check your inbox and
      // click the link" flow was replaced in Build 13 because Apple Mail
      // prefetch consumed the token and forced two clicks.
      if (mounted) {
        setState(() {
          _magicSent = true;
          _busy = false;
        });
        context.push('/auth/otp', extra: email);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Navigation strategy (Build 15): react to `currentUserProvider` going
    // from null → User instead of trying to capture `AuthChangeEvent.signedIn`
    // exactly. In Build 14 the AuthState event-based listener sometimes missed
    // the transition (whenData drops AsyncLoading frames, and the event can
    // arrive before ref.listen is wired on the first frame) — Apple login
    // authenticated correctly but the auth screen stayed up until the user
    // manually pressed the X that appeared once hasSession became true.
    //
    // Watching the derived `currentUserProvider` fires on every rebuild after
    // Supabase writes the session, regardless of which AuthState event got
    // us there. Same navigation for Apple, Google, Magic Link, Guest — no
    // need to special-case per flow.
    final user = ref.watch(currentUserProvider);
    ref.listen(currentUserProvider, (prev, next) {
      if (!mounted) return;
      if (prev == null && next != null) {
        // null → signed in. Route to /home. The router's redirect logic will
        // bounce the user to /quiz if they still need onboarding.
        context.go('/home');
      }
    });

    // Close button only makes sense when a session already exists (e.g. a
    // signed-in guest who came here from Profile to upgrade). First-time
    // users landing on /auth via Splash → Auth → Quiz → Home don't have one
    // yet — the close button would just bounce back here via the redirect.
    final hasSession = user != null;

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

              // ---- Legal disclosure (Build 16 — Apple UGC compliance) ----
              // Apple App Review expects Terms + Community Guidelines to be
              // visible on the sign-in / sign-up surface so the user agrees
              // before creating an account (even guest mode, since a guest
              // session can still post UGC once upgraded).
              const SizedBox(height: 18),
              _LegalBlurb(),

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

/// Tiny "By continuing, you agree to our Terms and Community Guidelines"
/// disclosure. Both link labels are tappable and navigate to the bundled
/// legal viewer. Apple UGC compliance — Build 16.
class _LegalBlurb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final linkStyle = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: AppColors.accent,
      decoration: TextDecoration.underline,
    );
    const baseStyle = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: AppColors.textMuted,
    );

    // The l10n blurb uses placeholders {terms} and {guidelines} so the
    // sentence structure differs per language. We build the RichText by
    // splitting on those sentinels rather than formatting them inline —
    // this keeps translators free to rearrange the sentence.
    final template =
        l10n.authLegalBlurb('{{TERMS}}', '{{GUIDELINES}}');
    final spans = <InlineSpan>[];
    var cursor = 0;
    void addText(String s) {
      if (s.isNotEmpty) spans.add(TextSpan(text: s, style: baseStyle));
    }

    // Find whichever marker appears first, append the link, and continue.
    while (cursor < template.length) {
      final tIdx = template.indexOf('{{TERMS}}', cursor);
      final gIdx = template.indexOf('{{GUIDELINES}}', cursor);
      final nextIdx = (tIdx == -1 && gIdx == -1)
          ? -1
          : (tIdx == -1
              ? gIdx
              : gIdx == -1
                  ? tIdx
                  : (tIdx < gIdx ? tIdx : gIdx));
      if (nextIdx == -1) {
        addText(template.substring(cursor));
        break;
      }
      addText(template.substring(cursor, nextIdx));
      if (nextIdx == tIdx) {
        spans.add(TextSpan(
          text: l10n.authTermsLink,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => context.push('/legal/terms'),
        ));
        cursor = nextIdx + '{{TERMS}}'.length;
      } else {
        spans.add(TextSpan(
          text: l10n.authGuidelinesLink,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => context.push('/legal/guidelines'),
        ));
        cursor = nextIdx + '{{GUIDELINES}}'.length;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text.rich(
        TextSpan(children: spans),
        textAlign: TextAlign.center,
      ),
    );
  }
}
