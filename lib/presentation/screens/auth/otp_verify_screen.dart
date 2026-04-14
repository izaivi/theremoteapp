import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../../../core/theme/app_colors.dart';
import '../../../data/repositories/auth_repository.dart';

/// Magic Link OTP verification — user types the 6-digit code that arrived
/// by email. Replaces the old "click the link in your inbox" flow which
/// was unreliable due to email-client prefetch consuming the one-time
/// token before the human could click (Build 12 complaint: "requirió que
/// le picara dos veces al link").
///
/// Reached via `context.push('/auth/otp', extra: email)` from auth_screen
/// immediately after calling `signInWithMagicLink(email)`.
class OtpVerifyScreen extends ConsumerStatefulWidget {
  final String email;
  const OtpVerifyScreen({super.key, required this.email});

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  static const _len = 6;

  // One controller + focusNode per digit so we can auto-advance/auto-backtrack.
  late final List<TextEditingController> _ctrls =
      List.generate(_len, (_) => TextEditingController());
  late final List<FocusNode> _focusNodes =
      List.generate(_len, (_) => FocusNode());

  bool _busy = false;
  bool _resending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-focus the first box on mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _ctrls.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    // Handle paste: if user pastes "123456" into the first box, distribute
    // across all 6 boxes.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < _len; i++) {
        _ctrls[i].text = i < digits.length ? digits[i] : '';
      }
      if (digits.length >= _len) {
        _focusNodes[_len - 1].unfocus();
        _verify();
      } else {
        _focusNodes[digits.length].requestFocus();
      }
      setState(() {});
      return;
    }

    if (value.isNotEmpty && index < _len - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      // Only jump back if user deleted — keeps cursor flow intuitive.
      _focusNodes[index - 1].requestFocus();
    }

    setState(() {}); // re-evaluate verify button enable state

    // Auto-submit when all 6 digits filled.
    if (_code.length == _len && !_code.contains('')) {
      _verify();
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    final code = _code;
    if (code.length != _len) {
      setState(() => _error = 'Enter all 6 digits.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyMagicLinkOtp(
            email: widget.email,
            token: code,
          );
      // Session is established. Navigation is handled by the
      // `authStateChangesProvider` listener below, which also covers the
      // case of a delayed signedIn event.
    } catch (e) {
      if (mounted) {
        // Clear the boxes so the user can re-type without deleting manually.
        for (final c in _ctrls) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
        setState(() {
          _busy = false;
          _error = _friendlyError(e);
        });
      }
    }
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithMagicLink(widget.email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New code sent to ${widget.email}'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('expired') || s.contains('invalid')) {
      return 'That code is invalid or expired. Request a new one.';
    }
    if (s.contains('rate') || s.contains('too many')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateChangesProvider, (prev, next) {
      next.whenData((state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.signedIn) {
          context.go('/home');
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.canPop() ? context.pop() : context.go('/auth'),
        ),
        title: const Text('Enter code'),
      ),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            children: [
              Center(
                child: Image.asset(
                  'assets/mascots/mascot_loved.png',
                  width: 96,
                  height: 96,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.mark_email_read_outlined, size: 64),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Check your email',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'We sent a 6-digit code to\n${widget.email}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // ---- 6 code boxes ----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_len, (i) => _DigitBox(
                      controller: _ctrls[i],
                      focusNode: _focusNodes[i],
                      onChanged: (v) => _onDigitChanged(i, v),
                    )),
              ),

              const SizedBox(height: 20),

              // ---- Verify button ----
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: (_busy || _code.length != _len) ? null : _verify,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor:
                        AppColors.accent.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verify code',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
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

              const SizedBox(height: 22),

              // ---- Resend ----
              Center(
                child: TextButton(
                  onPressed: _resending ? null : _resend,
                  child: Text(
                    _resending ? 'Sending…' : "Didn't get it? Resend code",
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DigitBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _DigitBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        // Allow paste of full 6-digit code into any box — handled in
        // onDigitChanged by detecting value.length > 1.
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.accent, width: 2),
          ),
        ),
      ),
    );
  }
}
