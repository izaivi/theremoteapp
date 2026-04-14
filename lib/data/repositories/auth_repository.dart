import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';

/// Custom URL scheme registered in `ios/Runner/Info.plist` (and, when we
/// ship Android, `AndroidManifest.xml`). Only used today by Magic Link
/// emails for backwards-compat if the Supabase template ever reverts to
/// a click-through `{{ .ConfirmationURL }}` format. The current template
/// sends a 6-digit code and doesn't use this redirect, but we keep the
/// constant + URL scheme registered so we can flip back without reconfiguring
/// the app bundle.
///
/// Google no longer uses this (Build 15): we moved to native Google Sign-In
/// + `signInWithIdToken`, which never touches a browser and therefore
/// doesn't need a redirect URL.
///
/// If it is used again, it MUST also be whitelisted in:
///   Supabase Dashboard → Auth → URL Configuration → Redirect URLs
const String kAuthRedirectUrl = 'io.theremote://login-callback/';

/// Auth — wraps Supabase Auth + the native social providers.
///
/// Four entry points, all returning the same [AuthResponse]-ish flow:
///
///   1. [signInWithApple]      — native iOS Sign in with Apple sheet.
///   2. [signInWithGoogle]     — native Google Sign In sheet (iOS).
///   3. [signInWithMagicLink]  — emails a magic link (passwordless OTP).
///   4. [signInAnonymously]    — guest mode, creates a real auth.users row
///                                with `is_anonymous = true`. Can be upgraded
///                                later via [linkEmailToCurrentSession].
///
/// All four converge on the same `auth.users` table in Supabase, which means
/// the rest of the app only ever needs to read [Supabase.instance.client.auth.currentUser]
/// — it doesn't care which method got the user there.
///
/// If [SupabaseConfig.isConfigured] is false (no `--dart-define`s), every
/// method throws [_NoSupabaseException]. Callers should catch it and fall
/// back to local-only mode.
class AuthRepository {
  AuthRepository();

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Current authenticated user, or null if not signed in.
  User? get currentUser =>
      SupabaseConfig.isConfigured ? _auth.currentUser : null;

  /// Stream of auth state changes — sign in, sign out, token refresh.
  Stream<AuthState> get onAuthStateChange =>
      SupabaseConfig.isConfigured
          ? _auth.onAuthStateChange
          : const Stream<AuthState>.empty();

  /// True if the current session is an anonymous (guest) one.
  bool get isAnonymous => currentUser?.isAnonymous ?? false;

  // -----------------------------------------------------------------------
  // Apple
  // -----------------------------------------------------------------------

  /// Trigger native Sign in with Apple, then exchange the resulting ID token
  /// with Supabase. Apple requires a hashed nonce in the request and the raw
  /// nonce in the Supabase exchange — we generate both here.
  Future<AuthResponse> signInWithApple() async {
    _ensureConfigured();
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256(rawNonce);

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple did not return an identity token.');
    }

    return _auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  // -----------------------------------------------------------------------
  // Google
  // -----------------------------------------------------------------------

  /// Launch the native iOS Google Sign-In sheet, receive the Google ID token,
  /// and exchange it for a Supabase session via `signInWithIdToken`.
  ///
  /// Why native instead of `signInWithOAuth` (Build 14 → 15):
  ///
  /// The previous `signInWithOAuth` path opened an in-app browser which, on
  /// iOS, maps to SFSafariViewController — and SFSafariViewController does
  /// NOT auto-dismiss on custom-scheme redirects. The user saw a white page
  /// after Google authentication completed and had to tap the "X" manually
  /// (Build 12 + 14 complaint). Native Google Sign-In presents Apple's own
  /// account picker sheet, which the OS dismisses the moment the user picks
  /// an account — no browser, no white page, no X button.
  ///
  /// About the nonce (live scar tissue — keep this comment intact):
  ///
  /// The native iOS Google Sign-In SDK generates a nonce internally and
  /// embeds its hash in the id_token. Flutter's `google_sign_in` 6.x does
  /// not expose that nonce, so we can't pass it to Supabase. Supabase
  /// then rejects the token with:
  ///
  ///     "Passed nonce and nonce in id_token should either both exist
  ///      or not. (statusCode: 400)"
  ///
  /// The fix lives in Supabase, not in the app: enable
  ///
  ///   Supabase Dashboard → Auth → Providers → Google → "Skip nonce checks"
  ///
  /// (the Supabase UI labels this as "useful in situations where you don't
  /// have access to the nonce used to issue the ID token, such as with iOS")
  ///
  /// With Skip Nonce Checks ON, Supabase still validates:
  ///   • the id_token signature (signed by Google),
  ///   • the `aud` claim (matches an authorized Client ID),
  ///   • the `exp` claim (token is not expired, typically ~5 min).
  /// Only the anti-replay nonce check is skipped — low risk given the
  /// short token lifetime.
  ///
  /// Required config (verify before shipping):
  ///   • `SupabaseConfig.googleIosClientId`    → iOS client ID (Google Cloud).
  ///   • `SupabaseConfig.googleServerClientId` → Web client ID; passed as
  ///     `serverClientId` so the id_token's `aud` claim is the Web ID, which
  ///     is the canonical Supabase primary Client ID.
  ///   • iOS Info.plist CFBundleURLSchemes contains the reversed iOS client
  ///     ID (`com.googleusercontent.apps.<iOS_CLIENT_ID>`).
  ///   • Supabase Dashboard → Auth → Providers → Google → "Client IDs" has
  ///     both the Web and iOS IDs (comma-separated). "Skip nonce checks" = ON.
  Future<AuthResponse> signInWithGoogle() async {
    _ensureConfigured();

    final googleSignIn = GoogleSignIn(
      clientId: SupabaseConfig.googleIosClientId,
      serverClientId: SupabaseConfig.googleServerClientId,
      scopes: const ['email', 'profile'],
    );

    final account = await googleSignIn.signIn();
    if (account == null) {
      // User cancelled the Google sheet.
      throw const AuthException('Google sign-in cancelled.');
    }

    final auth = await account.authentication;
    final idToken = auth.idToken;
    final accessToken = auth.accessToken;
    if (idToken == null) {
      throw const AuthException('Google did not return an identity token.');
    }

    // We intentionally do NOT pass `nonce:` here. Google's iOS SDK embedded
    // a nonce in the id_token that we cannot read from Flutter. Supabase
    // will bypass the nonce check because "Skip nonce checks" is enabled
    // in the Google provider settings (see comment above).
    return _auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  // -----------------------------------------------------------------------
  // Magic Link (passwordless OTP via email)
  // -----------------------------------------------------------------------

  /// Sends a 6-digit login code to [email].
  ///
  /// We deliberately removed the click-through magic link in Build 13: Apple
  /// Mail (and other iOS clients) aggressively prefetch links to generate
  /// previews, and that prefetch GETs the `{{ .ConfirmationURL }}` before
  /// the human clicks — consuming the one-time token. By the time the user
  /// taps the link, the token is invalid and they're bounced back to /auth.
  /// Users reported needing two clicks (Build 12 complaint).
  ///
  /// Now the email contains only `{{ .Token }}` (6-digit code, see
  /// Supabase Dashboard → Auth → Email Templates → Magic Link). The user
  /// types it into the OTP screen and we call [verifyMagicLinkOtp] to
  /// establish the session. Codes are not prefetchable, so the bug is gone
  /// by construction.
  ///
  /// UI should route to the OTP verification screen after this returns.
  Future<void> signInWithMagicLink(String email) async {
    _ensureConfigured();
    await _auth.signInWithOtp(
      email: email.trim(),
      // We keep `emailRedirectTo` for backwards-compat (if the template ever
      // reverts to a link-style template), but the v13 template has no link
      // so this is effectively ignored by the new flow.
      emailRedirectTo: kAuthRedirectUrl,
      shouldCreateUser: true,
    );
  }

  /// Exchange the 6-digit code the user typed for a full session.
  ///
  /// Throws [AuthException] with `message: 'Token has expired or is invalid'`
  /// if the user mistyped or waited too long (codes expire after 60 minutes
  /// by default — configurable in Supabase Dashboard → Auth → Providers →
  /// Email → "OTP expiry").
  ///
  /// On success, Supabase emits `AuthChangeEvent.signedIn` on the listener
  /// stream, which the app's main.dart handler picks up to pull profile
  /// data, and the OTP screen routes to /home.
  Future<AuthResponse> verifyMagicLinkOtp({
    required String email,
    required String token,
  }) async {
    _ensureConfigured();
    return _auth.verifyOTP(
      type: OtpType.email,
      token: token.trim(),
      email: email.trim(),
    );
  }

  // -----------------------------------------------------------------------
  // Anonymous (guest) — and the upgrade path
  // -----------------------------------------------------------------------

  /// Create a guest session. The resulting user has `is_anonymous = true`
  /// in `auth.users` and a matching row in `public.profiles` with
  /// `is_guest = true` (handled by the `handle_new_user` trigger).
  Future<AuthResponse> signInAnonymously() async {
    _ensureConfigured();
    return _auth.signInAnonymously();
  }

  /// Upgrade a guest session to a real account by attaching an email.
  /// Sends a confirmation magic link to [email]; on confirmation the
  /// existing `auth.users` row keeps its UID (so all the user's data
  /// stays linked) and just gets an email and `is_anonymous = false`.
  Future<UserResponse> linkEmailToCurrentSession(String email) async {
    _ensureConfigured();
    return _auth.updateUser(UserAttributes(email: email.trim()));
  }

  // -----------------------------------------------------------------------
  // Sign out
  // -----------------------------------------------------------------------

  Future<void> signOut() async {
    if (!SupabaseConfig.isConfigured) return;
    await _auth.signOut();
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  void _ensureConfigured() {
    if (!SupabaseConfig.isConfigured) {
      throw const AuthException(
          'Supabase is not configured — running in local-only mode.');
    }
  }

  /// Cryptographically random nonce (Apple requirement).
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }
}

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository());

/// Stream of the current Supabase auth state. Use this to gate UI on
/// signed-in / signed-out transitions.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).onAuthStateChange;
});

/// Convenience: current user (recomputed on auth state changes).
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(authRepositoryProvider).currentUser;
});
