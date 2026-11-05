import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/auth/account.dart';
import 'package:kantoi/auth/auth_service.dart';
import 'package:kantoi/auth/firebase_auth_backend.dart';
import 'package:kantoi/cloud/firestore_sink.dart';
import 'package:kantoi/cloud/outbox.dart';
import 'package:kantoi/report/scam_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A phone backend whose session has ended, like a Firebase sign-out.
class _Ended extends LocalAuthBackend {
  @override
  Future<bool> restoreSession(KantoiUser cached) async => false;
}

/// A sink that holds every write until released.
class _SlowSink implements CloudSink {
  final writes = <String>[];
  final gate = Completer<void>();
  @override
  Future<void> write(String collection, String id, Map<String, dynamic> data) async {
    writes.add('$collection/$id');
    await gate.future;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Firebase errors become the plain messages the screens expect', () {
    expect(authProblemFor('email-already-in-use').message, 'This email is already registered. Log in instead?');
    expect(authProblemFor('email-already-in-use').field, 'email');
    for (final c in ['invalid-credential', 'wrong-password', 'user-not-found', 'INVALID_LOGIN_CREDENTIALS']) {
      expect(authProblemFor(c).message, "That username or password isn't right.");
    }
    expect(authProblemFor('network-request-failed').message, contains('internet'));
    expect(authProblemFor('some-new-code').message, 'Something went wrong. Please try again.');
    for (final c in ['too-many-requests', 'requires-recent-login', 'weak-password', 'user-disabled']) {
      expect(authProblemFor(c).message, isNot(contains(c)));
    }
  });

  test('cloud documents add the owner and identifier codes, nothing else', () {
    final r = ScamReport(id: 'rep-1', kind: 'cyber.phishing', attackers: [const AttackerId(IdentifierType.phone, '012-345 6789')]);
    final payload = r.sharedPayload();
    final doc = cloudDoc('u1', payload);
    expect(cloudDocId('u1', 'rep-1'), 'u1_rep-1');
    expect(doc['uid'], 'u1');
    expect(doc['idCodes'], [identifierCode(const AttackerId(IdentifierType.phone, '0123456789'))]);
    expect(doc.keys.toSet().difference(payload.keys.toSet()), {'uid', 'idCodes'});
    expect(cloudDoc('u1', {'v': 1})['idCodes'], isEmpty);
  });

  test('a profile round-trips through Firestore fields', () {
    // Local time: Firestore timestamps read back as local time.
    final t = DateTime(2026, 11, 3, 9);
    final u = KantoiUser(
        uid: 'u1', method: SignInMethod.email, fullName: 'Jayden Kow', email: 'j@x.my', username: 'jayden', phone: '0123456789',
        created: t, consent: consentVersion, consentAt: t);
    final p = profileOf(u);
    expect(p.containsKey('email'), isFalse);
    final back = userFromProfile('u1', 'J@X.my', p);
    expect(back.toJson(), u.toJson());
  });

  test('a remembered user whose session ended is logged out on start', () async {
    final local = AuthService();
    expect(await local.registerWithoutCode(
        const Registration(fullName: 'Jayden Kow', email: 'j@x.my', username: 'jayden', password: 'Mango-lantern-42', agreed: true)), isEmpty);
    expect(local.signedIn, isTrue);
    expect(local.resetsByLink, isFalse);

    final again = AuthService();
    await again.load();
    expect(again.signedIn, isTrue);

    final ended = AuthService(backend: _Ended());
    await ended.load();
    expect(ended.signedIn, isFalse);
  });

  test('adding to the outbox does not wait for the send, and flushes never overlap', () async {
    final box = Outbox();
    final sink = _SlowSink();
    box.sink = sink;
    await box.add('reports', 'r1', {'v': 1}).timeout(const Duration(seconds: 1));
    final second = box.flush();
    await Future<void>.delayed(Duration.zero);
    expect(sink.writes, ['reports/r1']);
    sink.gate.complete();
    expect(await second, 1);
    expect(box.items, isEmpty);
    expect(box.sent, 1);
  });
}
