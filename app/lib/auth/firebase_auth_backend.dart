import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'account.dart';
import 'auth_service.dart';

const _badLogin = "That username or password isn't right.";
const _taken = AuthProblem('That username is taken.', field: 'username');

/// Plain-English messages for Firebase's error codes, so no Firebase wording
/// ever reaches the screen.
AuthProblem authProblemFor(String code) => switch (code) {
      'email-already-in-use' => const AuthProblem('This email is already registered. Log in instead?', field: 'email'),
      'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-email' || 'INVALID_LOGIN_CREDENTIALS' =>
        const AuthProblem(_badLogin),
      'weak-password' => const AuthProblem('Use at least 8 characters with letters and numbers.', field: 'password'),
      'too-many-requests' => const AuthProblem('Too many tries. Please wait a few minutes and try again.'),
      'network-request-failed' || 'unavailable' || 'deadline-exceeded' =>
        const AuthProblem("Couldn't reach Kantoi. Check your internet connection and try again."),
      'user-disabled' => const AuthProblem('This account has been turned off.'),
      'requires-recent-login' => const AuthProblem('For your safety, please log out, log in again, then try once more.'),
      'account-exists-with-different-credential' =>
        const AuthProblem('This email already has a Kantoi password. Log in with your username or email instead.'),
      _ => const AuthProblem('Something went wrong. Please try again.'),
    };

AuthProblem _problem(Object e) => switch (e) {
      AuthProblem p => p,
      FirebaseException(:final code) => authProblemFor(code),
      TimeoutException() => authProblemFor('network-request-failed'),
      _ => authProblemFor(''),
    };

/// What users/{uid} holds. Email stays in Firebase Auth only.
Map<String, dynamic> profileOf(KantoiUser u) => {
      'fullName': u.fullName,
      'username': u.username,
      'phone': u.phone,
      'method': u.method.name,
      'created': Timestamp.fromDate(u.created),
      'consent': u.consent,
      'consentAt': Timestamp.fromDate(u.consentAt),
    };

KantoiUser userFromProfile(String uid, String email, Map<String, dynamic> d) {
  DateTime at(Object? v) => v is Timestamp ? v.toDate() : DateTime.now();
  return KantoiUser(
    uid: uid,
    method: SignInMethod.values.firstWhere((m) => m.name == d['method'], orElse: () => SignInMethod.email),
    fullName: d['fullName'] as String? ?? '',
    email: email.toLowerCase(),
    username: d['username'] as String? ?? '',
    phone: d['phone'] as String? ?? '',
    created: at(d['created']),
    consent: d['consent'] as String? ?? '',
    consentAt: at(d['consentAt']),
  );
}

/// Accounts in Firebase Authentication, profiles in Firestore:
///   users/{uid}           [profileOf]
///   usernames/{username}  {uid, email}, so people can log in by username
/// The email code (server/otp) is still checked before [register]. Spark has
/// no server code, so its proof cannot be re-checked by Firebase.
class FirebaseAuthBackend implements AuthBackend {
  static const timeout = Duration(seconds: 20);

  final FirebaseAuth? _auth;
  final FirebaseFirestore? _db;
  FirebaseAuthBackend({this._auth, this._db});

  FirebaseAuth get _a => _auth ?? FirebaseAuth.instance;
  FirebaseFirestore get _d => _db ?? FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> _name(String username) => _d.collection('usernames').doc(username);
  DocumentReference<Map<String, dynamic>> _profile(String uid) => _d.collection('users').doc(uid);

  /// Runs [f], turning every failure (and a dead connection) into an [AuthProblem].
  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f().timeout(timeout);
    } catch (e) {
      throw _problem(e);
    }
  }

  @override
  bool get isCloud => true;

  @override
  Future<KantoiUser> register(Registration r, {required String proof, DateTime? now}) => _run(() async {
        if (proof.isEmpty) throw const AuthProblem('Please verify your email first.');
        final email = r.email.trim().toLowerCase();
        final username = r.username.trim().toLowerCase();
        final name = _name(username);
        if ((await name.get()).exists) throw _taken;
        final u = (await _a.createUserWithEmailAndPassword(email: email, password: r.password)).user!;
        try {
          await _d.runTransaction((tx) async {
            if ((await tx.get(name)).exists) throw _taken;
            tx.set(name, {'uid': u.uid, 'email': email});
          });
          await u.updateDisplayName(r.fullName.trim());
          final t = now ?? DateTime.now();
          final user = KantoiUser(
            uid: u.uid,
            method: SignInMethod.email,
            fullName: r.fullName.trim(),
            email: email,
            username: username,
            phone: r.phone.trim(),
            created: t,
            consent: consentVersion,
            consentAt: t,
          );
          await _profile(u.uid).set(profileOf(user));
          return user;
        } catch (_) {
          // Leave nothing half-made, so the email and username can be used again.
          try {
            if ((await name.get()).data()?['uid'] == u.uid) await name.delete();
            await u.delete();
          } catch (_) {}
          rethrow;
        }
      });

  @override
  Future<KantoiUser> signInPassword(String usernameOrEmail, String password) => _run(() async {
        var email = usernameOrEmail.trim().toLowerCase();
        if (!email.contains('@')) {
          // Unknown usernames get the same answer as a wrong password, so
          // nobody can find out which usernames exist.
          if (!RegExp(r'^[a-z0-9_.]{3,20}$').hasMatch(email)) throw const AuthProblem(_badLogin);
          final found = (await _name(email).get()).data()?['email'];
          if (found is! String) throw const AuthProblem(_badLogin);
          email = found;
        }
        final u = (await _a.signInWithEmailAndPassword(email: email, password: password)).user!;
        return _userFor(u, SignInMethod.email);
      });

  @override
  Future<KantoiUser> signInGoogle({required String id, required String email, required String name, DateTime? now, String? idToken}) =>
      _run(() async {
        if (idToken == null || idToken.isEmpty) {
          throw const AuthProblem("Google didn't confirm this account. Try again or register with email.");
        }
        final u = (await _a.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken))).user!;
        return _userFor(u, SignInMethod.google, name: name, now: now);
      });

  /// The saved profile, made on first sign-in (Google users ticked the
  /// Privacy Notice in the consent dialog before signing in).
  Future<KantoiUser> _userFor(User u, SignInMethod method, {String? name, DateTime? now}) async {
    final d = (await _profile(u.uid).get()).data();
    if (d != null) return userFromProfile(u.uid, u.email ?? '', d);
    final t = now ?? DateTime.now();
    final user = KantoiUser(
        uid: u.uid,
        method: method,
        fullName: u.displayName ?? name ?? '',
        email: (u.email ?? '').toLowerCase(),
        created: t,
        consent: consentVersion,
        consentAt: t);
    await _profile(u.uid).set(profileOf(user));
    return user;
  }

  /// PDPA "delete my data": the user's shared records, username and profile,
  /// then the account itself.
  @override
  Future<void> deleteAccount(KantoiUser u) => _run(() async {
        final me = _a.currentUser;
        if (me == null) throw authProblemFor('requires-recent-login');
        // Firebase only deletes an account soon after a sign-in. Check first,
        // so the shared records aren't deleted while the account stays.
        final last = me.metadata.lastSignInTime;
        if (last == null || DateTime.now().difference(last) > const Duration(minutes: 4)) {
          throw authProblemFor('requires-recent-login');
        }
        for (final c in const ['reports', 'detections']) {
          final mine = await _d.collection(c).where('uid', isEqualTo: me.uid).get();
          final batch = _d.batch();
          for (final doc in mine.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }
        if (u.username.isNotEmpty && (await _name(u.username).get()).data()?['uid'] == me.uid) {
          await _name(u.username).delete();
        }
        await _profile(me.uid).delete();
        await me.delete();
      });

  /// With email enumeration protection on, Firebase will not say whether an
  /// email has an account, so the reset step answers the same either way.
  @override
  Future<bool> hasPasswordAccount(String email) async => true;

  @override
  Future<void> resetPassword(String email, String password, {required String proof}) =>
      throw UnsupportedError('Firebase accounts reset by email link.');

  @override
  Future<void> sendResetLink(String email) => _run(() async {
        try {
          await _a.sendPasswordResetEmail(email: email);
        } on FirebaseAuthException catch (e) {
          if (e.code != 'user-not-found') rethrow;
        }
      });

  @override
  Future<bool> restoreSession(KantoiUser cached) async {
    // Firebase reloads its saved session just after start-up.
    final u = _a.currentUser ?? await _a.authStateChanges().first.timeout(const Duration(seconds: 3), onTimeout: () => null);
    return u?.uid == cached.uid;
  }

  @override
  Future<void> signOut() => _a.signOut();
}
