/// Accounts: register, sign in, forgot password, email verification.
///
/// The UI talks to [AuthService]; [AuthService] talks to an [AuthBackend].
/// The real backend is Firebase Authentication; tests use a fake.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountUser {
  final String uid;
  final String email;
  final String name;
  final bool emailVerified;
  const AccountUser({required this.uid, required this.email, this.name = '', this.emailVerified = false});

  String get greetingName => name.trim().isNotEmpty ? name.trim().split(' ').first : email.split('@').first;
}

/// A failure the user can read.
class AuthFailure implements Exception {
  final String code;
  final String message;
  const AuthFailure(this.code, this.message);
  @override
  String toString() => message;
}

abstract class AuthBackend {
  AccountUser? get current;
  Stream<AccountUser?> changes();
  Future<AccountUser> signIn(String email, String password);
  Future<AccountUser> register(String name, String email, String password);
  Future<void> sendPasswordReset(String email);
  Future<void> sendVerification();

  /// Fetches the latest user (after they tapped the verification link).
  Future<AccountUser?> reload();
  Future<void> signOut();
}

/// Plain-words messages for Firebase Auth error codes.
String authMessage(String code) => switch (code) {
      'invalid-email' => 'That email address does not look right.',
      'user-disabled' => 'This account has been turned off. Contact support.',
      'user-not-found' || 'wrong-password' || 'invalid-credential' || 'INVALID_LOGIN_CREDENTIALS' =>
        'Wrong email or password.',
      'email-already-in-use' => 'An account with this email already exists. Sign in, or reset your password.',
      'weak-password' => 'That password is too weak. Use at least 8 characters with letters and numbers.',
      'too-many-requests' => 'Too many tries. Wait a few minutes, then try again.',
      'network-request-failed' => 'No internet connection. Check your connection and try again.',
      'operation-not-allowed' => 'Email sign-in is not turned on for this app yet.',
      'missing-email' => 'Enter your email address.',
      _ => 'Something went wrong ($code). Please try again.',
    };

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Null when fine, otherwise what to fix.
String? emailProblem(String v) {
  final e = v.trim();
  if (e.isEmpty) return 'Enter your email address';
  if (!_emailRe.hasMatch(e)) return 'That email address does not look right';
  return null;
}

/// Kantoi asks for at least 8 characters with a letter and a number.
String? passwordProblem(String v) {
  if (v.isEmpty) return 'Enter a password';
  if (v.length < 8) return 'Use at least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) return 'Use both letters and numbers';
  return null;
}

/// 0 (weak) to 3 (strong), for the strength bar.
int passwordStrength(String v) {
  var s = 0;
  if (v.length >= 8) s++;
  if (v.length >= 12) s++;
  if (RegExp(r'[A-Za-z]').hasMatch(v) && RegExp(r'\d').hasMatch(v)) s++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(v)) s++;
  return s.clamp(0, 3);
}

String? nameProblem(String v) => v.trim().length < 2 ? 'Enter your name' : null;

/// The app-wide account state.
class AuthService {
  final AuthBackend? backend;

  /// Called after sign-in or registration (saves the profile to Firestore).
  final Future<void> Function(AccountUser user, {required bool isNew})? onSignedIn;

  final user = ValueNotifier<AccountUser?>(null);

  /// The user chose "Continue without an account" on this phone.
  final guest = ValueNotifier<bool>(false);

  StreamSubscription<AccountUser?>? _sub;

  AuthService(this.backend, {this.onSignedIn});

  /// Whether accounts exist in this build at all.
  bool get available => backend != null;
  bool get signedIn => user.value != null;
  bool get verified => user.value?.emailVerified ?? false;

  Future<void> start() async {
    try {
      guest.value = (await SharedPreferences.getInstance()).getBool('accountGuest') ?? false;
    } catch (_) {}
    final b = backend;
    if (b == null) return;
    user.value = b.current;
    _sub = b.changes().listen((u) => user.value = u);
  }

  Future<void> continueAsGuest() async {
    guest.value = true;
    try {
      await (await SharedPreferences.getInstance()).setBool('accountGuest', true);
    } catch (_) {}
  }

  Future<void> _clearGuest() async {
    guest.value = false;
    try {
      await (await SharedPreferences.getInstance()).remove('accountGuest');
    } catch (_) {}
  }

  AuthBackend get _b => backend ?? (throw const AuthFailure('unavailable', 'Accounts are not set up in this build.'));

  Future<AccountUser> signIn(String email, String password) async {
    final u = await _b.signIn(email.trim(), password);
    user.value = u;
    await _clearGuest();
    await _afterSignIn(u, isNew: false);
    return u;
  }

  Future<AccountUser> register(String name, String email, String password) async {
    final u = await _b.register(name.trim(), email.trim(), password);
    user.value = u;
    await _clearGuest();
    // The account works right away; verification only unlocks community
    // reporting, so a failed email does not block sign-up.
    try {
      await _b.sendVerification();
    } catch (_) {}
    await _afterSignIn(u, isNew: true);
    return u;
  }

  Future<void> _afterSignIn(AccountUser u, {required bool isNew}) async {
    try {
      await onSignedIn?.call(u, isNew: isNew);
    } catch (e) {
      debugPrint('Kantoi: saving the profile failed: $e');
    }
  }

  Future<void> sendPasswordReset(String email) => _b.sendPasswordReset(email.trim());

  Future<void> resendVerification() => _b.sendVerification();

  /// Returns true when the email is now verified.
  Future<bool> refresh() async {
    final u = await _b.reload();
    user.value = u;
    return u?.emailVerified ?? false;
  }

  Future<void> signOut() async {
    await _b.signOut();
    user.value = null;
  }

  void dispose() {
    _sub?.cancel();
  }
}

/// The app's account service. Without Firebase it has no backend, and the
/// app runs exactly as before.
AuthService auth = AuthService(null);
