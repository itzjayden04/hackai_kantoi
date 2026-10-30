import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kantoi/auth/account.dart';
import 'package:kantoi/auth/auth_service.dart';
import 'package:kantoi/auth/otp_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake email code service: the code is always 123456.
OtpClient _otp({List<String>? sent}) => OtpClient(
    url: 'https://script.example/exec',
    appKey: 'k',
    client: MockClient((r) async {
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      if (b['appKey'] != 'k') return http.Response('{"ok":false,"error":"forbidden"}', 200);
      if (b['action'] == 'send') {
        sent?.add(b['email'] as String);
        return http.Response('{"ok":true}', 200);
      }
      return b['code'] == '123456'
          ? http.Response('{"ok":true,"proof":"p","exp":1}', 200)
          : http.Response('{"ok":false,"error":"wrong","triesLeft":4}', 200);
    }));

const _reg = Registration(
    fullName: 'Jayden Kow', email: 'Jayden@Example.com', phone: '012-345 6789', username: 'jayden', password: 'Mango-lantern-42', agreed: true);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the form is checked before any code is sent', () async {
    final sent = <String>[];
    final a = AuthService(otp: _otp(sent: sent));
    final p = await a.startRegistration(const Registration(fullName: 'J', email: 'nope', username: 'a', password: 'short', agreed: false));
    expect(p.keys, containsAll(['fullName', 'email', 'username', 'password', 'agreed']));
    expect(sent, isEmpty);
    expect(await a.startRegistration(_reg), isEmpty);
    expect(sent, ['jayden@example.com']);
  });

  test('register with the code, then log in with username or email', () async {
    final a = AuthService(otp: _otp());
    expect(await a.finishRegistration(_reg, '000000'), contains('4 tries left'));
    expect(a.signedIn, isFalse);
    expect(await a.finishRegistration(_reg, '123456'), isNull);
    expect(a.user!.email, 'jayden@example.com');
    expect(a.user!.consent, consentVersion);
    await a.signOut();
    expect(await a.signInPassword('jayden', 'wrong-password'), isNotNull);
    expect(await a.signInPassword('JAYDEN@example.com', 'Mango-lantern-42'), isNull);
    expect(a.user!.username, 'jayden');
    // Same email again is refused.
    await a.signOut();
    expect(await a.finishRegistration(_reg, '123456'), contains('already registered'));
  });

  test('7 days without opening the app logs out, and says so once', () async {
    final a = AuthService(otp: _otp());
    await a.finishRegistration(_reg, '123456');
    final t = DateTime.now();
    await a.touch(now: t);
    final b = AuthService(otp: _otp());
    await b.load(now: t.add(const Duration(days: 6)));
    expect(b.signedIn, isTrue);
    final c = AuthService(otp: _otp());
    await c.load(now: t.add(const Duration(days: 6 + 8)));
    expect(c.signedIn, isFalse);
    expect(c.expired, isTrue);
  });

  test('a build without the code service says so plainly', () async {
    final a = AuthService(otp: OtpClient(url: '', appKey: ''));
    expect((await a.startRegistration(_reg))['form'], contains('Google sign-in'));
  });

  test('password strength and hashing', () {
    expect(passwordStrength('abc'), 0);
    expect(passwordStrength('password123'), 1);
    expect(passwordStrength('Mango-lantern-42'), 3);
    expect(hashPassword('x', 's', iterations: 10), hashPassword('x', 's', iterations: 10));
    expect(hashPassword('x', 's', iterations: 10), isNot(hashPassword('x', 't', iterations: 10)));
  });
}
