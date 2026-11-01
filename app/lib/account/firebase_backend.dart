/// Firebase Authentication and Cloud Firestore behind Kantoi's interfaces.
///
/// Firestore layout (see firestore.rules at the repo root):
///   users/{uid}                         name, email, createdAt, lastLoginAt
///   indicators/{kind_sha256}/reports/{uid}
///                                       verdict, kind, display, scamType, at
/// One report per account per indicator, written only by verified accounts.
/// Indicator ids are hashes, and displays are masked, so full phone numbers
/// and bank accounts are never stored.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../engine/community/community.dart';
import 'auth_service.dart';

AccountUser? _toAccount(User? u) =>
    u == null ? null : AccountUser(uid: u.uid, email: u.email ?? '', name: u.displayName ?? '', emailVerified: u.emailVerified);

AuthFailure _fail(Object e) {
  if (e is FirebaseAuthException) return AuthFailure(e.code, authMessage(e.code));
  if (e is AuthFailure) return e;
  return AuthFailure('unknown', authMessage('$e'));
}

class FirebaseAuthBackend implements AuthBackend {
  final FirebaseAuth _auth;
  FirebaseAuthBackend([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;

  @override
  AccountUser? get current => _toAccount(_auth.currentUser);

  @override
  Stream<AccountUser?> changes() => _auth.userChanges().map(_toAccount);

  @override
  Future<AccountUser> signIn(String email, String password) async {
    try {
      final c = await _auth.signInWithEmailAndPassword(email: email, password: password);
      return _toAccount(c.user)!;
    } catch (e) {
      throw _fail(e);
    }
  }

  @override
  Future<AccountUser> register(String name, String email, String password) async {
    try {
      final c = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      final u = c.user!;
      if (name.isNotEmpty) {
        await u.updateDisplayName(name);
        await u.reload();
      }
      return _toAccount(_auth.currentUser ?? u)!;
    } catch (e) {
      throw _fail(e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      // Do not reveal whether an account exists for this email.
      if (e.code == 'user-not-found') return;
      throw _fail(e);
    }
  }

  @override
  Future<void> sendVerification() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
    } catch (e) {
      throw _fail(e);
    }
  }

  @override
  Future<AccountUser?> reload() async {
    try {
      await _auth.currentUser?.reload();
      // The ID token carries email_verified for the security rules, so
      // refresh it too.
      await _auth.currentUser?.getIdToken(true);
      return _toAccount(_auth.currentUser);
    } catch (e) {
      throw _fail(e);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

/// Saves the user's profile in users/{uid}.
Future<void> saveProfile(AccountUser u, {required bool isNew, FirebaseFirestore? db}) async {
  final d = (db ?? FirebaseFirestore.instance).collection('users').doc(u.uid);
  await d.set({
    'name': u.name,
    'email': u.email,
    'lastLoginAt': FieldValue.serverTimestamp(),
    if (isNew) 'createdAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Community reports in Firestore.
class FirestoreCommunity implements CommunityIntel {
  final FirebaseFirestore _db;
  final AuthService _auth;
  FirestoreCommunity(this._auth, [FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  @override
  String get name => 'Kantoi community (Firestore)';

  @override
  bool get canReport => _auth.signedIn && _auth.verified;

  @override
  String get whyNot => !_auth.signedIn
      ? 'Sign in to share reports with other Kantoi users.'
      : !_auth.verified
          ? 'Verify your email to share reports (check your inbox, then tap "I have verified" in Settings).'
          : '';

  CollectionReference<Map<String, dynamic>> _reports(Indicator i) => _db.collection('indicators').doc(i.key).collection('reports');

  @override
  Future<List<CommunityTally>> lookup(List<Indicator> indicators) async {
    // Reading needs an account too, so the store can't be scraped anonymously.
    if (!_auth.signedIn) return const [];
    final now = DateTime.now();
    return Future.wait(indicators.map((i) async {
      final snap = await _reports(i).orderBy('at', descending: true).limit(100).get();
      final reports = [
        for (final d in snap.docs)
          CommunityReport(
            scam: d.data()['verdict'] == 'scam',
            at: (d.data()['at'] as Timestamp?)?.toDate() ?? now,
            scamType: d.data()['scamType'] as String?,
          ),
      ];
      return CommunityTally(i, reports);
    }));
  }

  @override
  Future<int> report(List<Indicator> indicators, {required bool scam, String? scamType}) async {
    final uid = _auth.user.value?.uid;
    if (uid == null || !canReport || indicators.isEmpty) return 0;
    final batch = _db.batch();
    final type = scamType?.trim();
    for (final i in indicators) {
      batch.set(_reports(i).doc(uid), {
        'verdict': scam ? 'scam' : 'legit',
        'kind': i.kind.name,
        'display': i.display.length > 80 ? i.display.substring(0, 80) : i.display,
        if (scam && type != null && type.isNotEmpty) 'scamType': type.length > 60 ? type.substring(0, 60) : type,
        'at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return indicators.length;
  }
}
