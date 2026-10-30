import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'otp_client.dart';

/// Where accounts live. The phone-only backend works today; Firebase
/// (next version) implements the same interface.
abstract class AuthBackend {
  /// Creates an account after the email code was verified ([proof]).
  Future<KantoiUser> register(Registration r, {required String proof, DateTime? now});

  /// Signs in with username or email and password, or throws [AuthProblem].
  Future<KantoiUser> signInPassword(String usernameOrEmail, String password);

  /// Records (or finds) a Google account.
  Future<KantoiUser> signInGoogle({required String id, required String email, required String name, DateTime? now});

  Future<void> deleteAccount(KantoiUser u);
}

class AuthProblem implements Exception {
  final String message;
  final String? field;
  const AuthProblem(this.message, {this.field});
  @override
  String toString() => message;
}

/// Accounts kept on this phone, passwords stored as salted PBKDF2 hashes.
class LocalAuthBackend implements AuthBackend {
  static const _k = 'auth.accounts';
  final Random _rand;
  LocalAuthBackend({Random? random}) : _rand = random ?? Random.secure();

  Future<List<Map<String, dynamic>>> _all() async {
    final p = await SharedPreferences.getInstance();
    return [for (final s in p.getStringList(_k) ?? const <String>[]) jsonDecode(s) as Map<String, dynamic>];
  }

  Future<void> _save(List<Map<String, dynamic>> a) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_k, a.map(jsonEncode).toList());
  }

  String _id() => List.generate(16, (_) => _rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  @override
  Future<KantoiUser> register(Registration r, {required String proof, DateTime? now}) async {
    if (proof.isEmpty) throw const AuthProblem('Please verify your email first.');
    final all = await _all();
    final email = r.email.trim().toLowerCase();
    final username = r.username.trim().toLowerCase();
    for (final a in all) {
      final u = KantoiUser.fromJson((a['user'] as Map).cast<String, dynamic>());
      if (u.email == email) throw const AuthProblem('This email is already registered. Log in instead?', field: 'email');
      if (u.username.isNotEmpty && u.username == username) throw const AuthProblem('That username is taken.', field: 'username');
    }
    final t = now ?? DateTime.now();
    final user = KantoiUser(
      uid: _id(),
      method: SignInMethod.email,
      fullName: r.fullName.trim(),
      email: email,
      username: username,
      phone: r.phone.trim(),
      created: t,
      consent: consentVersion,
      consentAt: t,
    );
    final salt = _id();
    all.add({'user': user.toJson(), 'salt': salt, 'hash': hashPassword(r.password, salt)});
    await _save(all);
    return user;
  }

  @override
  Future<KantoiUser> signInPassword(String usernameOrEmail, String password) async {
    final id = usernameOrEmail.trim().toLowerCase();
    for (final a in await _all()) {
      final u = KantoiUser.fromJson((a['user'] as Map).cast<String, dynamic>());
      if (u.method != SignInMethod.email || (u.email != id && u.username != id)) continue;
      if (hashPassword(password, a['salt'] as String) == a['hash']) return u;
      break;
    }
    throw const AuthProblem("That username or password isn't right.");
  }

  @override
  Future<KantoiUser> signInGoogle({required String id, required String email, required String name, DateTime? now}) async {
    final all = await _all();
    for (final a in all) {
      final u = KantoiUser.fromJson((a['user'] as Map).cast<String, dynamic>());
      if (u.method == SignInMethod.google && u.uid == 'g:$id') return u;
    }
    final t = now ?? DateTime.now();
    final user = KantoiUser(
        uid: 'g:$id', method: SignInMethod.google, fullName: name, email: email.toLowerCase(), created: t, consent: consentVersion, consentAt: t);
    all.add({'user': user.toJson()});
    await _save(all);
    return user;
  }

  @override
  Future<void> deleteAccount(KantoiUser u) async {
    final all = await _all();
    all.removeWhere((a) => (a['user'] as Map)['uid'] == u.uid);
    await _save(all);
  }
}

/// The signed-in user, the 7-day inactivity rule and the sign-in flows.
/// Phone protection does not depend on being signed in.
class AuthService extends ChangeNotifier {
  static const inactiveLimit = Duration(days: 7);
  static const _kUser = 'auth.user';
  static const _kActive = 'auth.lastActive';
  static const _googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  AuthBackend backend;
  OtpClient otp;
  AuthService({AuthBackend? backend, OtpClient? otp})
      : backend = backend ?? LocalAuthBackend(),
        otp = otp ?? OtpClient();

  KantoiUser? user;
  DateTime? lastActive;
  /// True right after an automatic logout, so the app can explain why once.
  bool expired = false;
  bool _googleReady = false;

  bool get signedIn => user != null;

  Future<void> load({DateTime? now}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_kUser);
      user = s == null ? null : KantoiUser.fromJson(jsonDecode(s) as Map<String, dynamic>);
      lastActive = DateTime.tryParse(p.getString(_kActive) ?? '');
    } catch (_) {
      user = null;
    }
    await checkInactivity(now: now);
  }

  /// Logs out a user who has not opened Kantoi for 7 days.
  Future<void> checkInactivity({DateTime? now}) async {
    final t = now ?? DateTime.now();
    if (user != null && lastActive != null && t.difference(lastActive!) > inactiveLimit) {
      await signOut();
      expired = true;
    } else if (user != null) {
      await touch(now: t);
    }
    notifyListeners();
  }

  /// Marks the user active (called when the app opens or resumes).
  Future<void> touch({DateTime? now}) async {
    lastActive = now ?? DateTime.now();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kActive, lastActive!.toIso8601String());
    } catch (_) {}
  }

  Future<void> _setUser(KantoiUser? u) async {
    user = u;
    expired = false;
    try {
      final p = await SharedPreferences.getInstance();
      if (u == null) {
        await p.remove(_kUser);
      } else {
        await p.setString(_kUser, jsonEncode(u.toJson()));
      }
    } catch (_) {}
    if (u != null) await touch();
    notifyListeners();
  }

  /// Step 1 of registering: checks the form and emails a code.
  /// Returns field problems, or an empty map when the code was sent.
  /// False in a build without the email-code sender (no OTP secrets): sign-up
  /// then skips the code so the app is never locked.
  bool get emailCodes => otp.configured;

  /// Sign-up without an email code, only for builds without the sender.
  Future<Map<String, String>> registerWithoutCode(Registration r) async {
    final problems = validateRegistration(r);
    if (problems.isNotEmpty) return problems;
    if (emailCodes) return const {'form': 'Please verify your email first.'};
    try {
      await _setUser(await backend.register(r, proof: 'unverified'));
      return const {};
    } on AuthProblem catch (e) {
      return {'form': e.message};
    }
  }

  Future<Map<String, String>> startRegistration(Registration r) async {
    final problems = validateRegistration(r);
    if (problems.isNotEmpty) return problems;
    final err = await otp.send(r.email.trim().toLowerCase());
    return err == null ? const {} : {'form': err};
  }

  /// Step 2: checks the code and creates the account.
  Future<String?> finishRegistration(Registration r, String code) async {
    final v = await otp.verify(r.email.trim().toLowerCase(), code.trim());
    if (!v.ok) {
      return v.triesLeft == null ? v.problem : '${v.problem} ${v.triesLeft} tries left.';
    }
    try {
      await _setUser(await backend.register(r, proof: v.proof!));
      return null;
    } on AuthProblem catch (e) {
      return e.message;
    }
  }

  Future<String?> signInPassword(String id, String password) async {
    try {
      await _setUser(await backend.signInPassword(id, password));
      return null;
    } on AuthProblem catch (e) {
      return e.message;
    }
  }

  /// Google's account picker. Returns a problem, or null when signed in.
  Future<String?> signInGoogle() async {
    try {
      final g = GoogleSignIn.instance;
      if (!_googleReady) {
        await g.initialize(serverClientId: _googleServerClientId.isEmpty ? null : _googleServerClientId);
        _googleReady = true;
      }
      if (!g.supportsAuthenticate()) return 'Google sign-in is not available on this phone.';
      final a = await g.authenticate();
      await _setUser(await backend.signInGoogle(id: a.id, email: a.email, name: a.displayName ?? a.email));
      return null;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return 'Sign-in cancelled.';
      return "Google sign-in didn't work (${e.code.name}). Try again or register with email.";
    } catch (e) {
      return "Google sign-in didn't work. Try again or register with email.";
    }
  }

  Future<void> signOut() async {
    if (user?.method == SignInMethod.google) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _setUser(null);
  }

  Future<void> deleteAccount() async {
    final u = user;
    if (u == null) return;
    await backend.deleteAccount(u);
    await signOut();
  }
}

final auth = AuthService();
