import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';

/// Custom URL scheme registered in `ios/Runner/Info.plist` (and, when we
/// ship Android, `AndroidManifest.xml`). Used as the redirect target for:
///
///   - Google OAuth via `signInWithOAuth` — Supabase hosts the Google flow
///     in SFSafariViewController and bounces back here when done.
///   - Magic Link emails — the link in the email opens this URL, iOS routes
///     it to the app, and `supabase_flutter` closes the session.
///
/// MUST also be whitelisted in:
///   Supabase Dashboard → Auth → URL Configuration → Redirect URLs
///   (add both `io.theremote://login-callback/` and
///    `io.theremote://login-callback/**` for wildcard safety).
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

  /// Launch the Google OAuth flow via Supabase. This opens a secure in-app
  /// browser (SFSafariViewController on iOS), the user signs in with Google,
  /// Google bounces back to Supabase, and Supabase finally redirects to our
  /// custom `io.theremote://login-callback/` deep link — at which point
  /// `supabase_flutter` detects the incoming URL, exchanges the auth code for
  /// a session (PKCE), and emits `AuthChangeEvent.signedIn`.
  ///
  /// This replaces the previous native `google_sign_in` + `signInWithIdToken`
  /// path because that flow fails with "Passed nonce and nonce in id_token
  /// should either both exist or not" — Google auto-includes a nonce in its
  /// id_token that Supabase then rejects. OAuth via browser sidesteps the
  /// entire id_token exchange.
  ///
  /// Returns `true` if the browser opened successfully. The actual session
  /// arrives asynchronously via the `authStateChangesProvider` stream once
  /// the deep link round-trip completes.
  Future<bool> signInWithGoogle() async {
    _ensureConfigured();
    // The default uses ASWebAuthenticationSession on iOS, which completes
    // auth but may leave a blank sheet the user must dismiss with "X".
    // This is a known iOS limitation; we accept it for now and will revisit
    // when supabase_flutter exposes launch-mode options.
    return _auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kAuthRedirectUrl,
    );
  }

  // -----------------------------------------------------------------------
  // Magic Link (passwordless OTP via email)
  // -----------------------------------------------------------------------

  /// Sends a one-time login link to [email]. The user clicks the link in
  /// their inbox, iOS routes `io.theremote://login-callback/?code=...` to
  /// the app, and `supabase_flutter` closes the session.
  ///
  /// UI should display "check your email" after this returns.
  Future<void> signInWithMagicLink(String email) async {
    _ensureConfigured();
    await _auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: kAuthRedirectUrl,
      shouldCreateUser: true,
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
