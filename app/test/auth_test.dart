import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/account/auth_service.dart';
import 'package:kantoi/account/account.dart' show needsSignIn;
import 'package:kantoi/ui/account/auth_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firebase-free accounts, kept in memory.
class FakeAuth implements AuthBackend {
  final Map<String, (String password, AccountUser user)> accounts = {};
  final resets = <String>[];
  var verificationsSent = 0;
  final _changes = StreamController<AccountUser?>.broadcast();
  AccountUser? _current;

  @override
  AccountUser? get current => _current;
  @override
  Stream<AccountUser?> changes() => _changes.stream;

  @override
  Future<AccountUser> signIn(String email, String password) async {
    final a = accounts[email];
    if (a == null || a.$1 != password) throw AuthFailure('invalid-credential', authMessage('invalid-credential'));
    return _current = a.$2;
  }

  @override
  Future<AccountUser> register(String name, String email, String password) async {
    if (accounts.containsKey(email)) throw AuthFailure('email-already-in-use', authMessage('email-already-in-use'));
    final u = AccountUser(uid: 'u${accounts.length}', email: email, name: name);
    accounts[email] = (password, u);
    return _current = u;
  }

  @override
  Future<void> sendPasswordReset(String email) async => resets.add(email);
  @override
  Future<void> sendVerification() async => verificationsSent++;

  /// The user tapped the link in the email.
  void verify(String email) {
    final a = accounts[email]!;
    accounts[email] = (a.$1, AccountUser(uid: a.$2.uid, email: email, name: a.$2.name, emailVerified: true));
  }

  @override
  Future<AccountUser?> reload() async => _current = _current == null ? null : accounts[_current!.email]!.$2;
  @override
  Future<void> signOut() async => _current = null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('validation', () {
    test('email', () {
      expect(emailProblem(''), isNotNull);
      expect(emailProblem('ali@'), isNotNull);
      expect(emailProblem('ali@mail'), isNotNull);
      expect(emailProblem(' ali@mail.com '), isNull);
    });
    test('password needs 8+ characters with letters and numbers', () {
      expect(passwordProblem('abc123'), 'Use at least 8 characters');
      expect(passwordProblem('abcdefgh'), 'Use both letters and numbers');
      expect(passwordProblem('12345678'), 'Use both letters and numbers');
      expect(passwordProblem('kantoi2026'), isNull);
      expect(passwordStrength('kantoi2026'), 2);
      expect(passwordStrength('Kantoi-2026-safe!'), 3);
    });
    test('Firebase codes become plain words', () {
      expect(authMessage('wrong-password'), 'Wrong email or password.');
      expect(authMessage('email-already-in-use'), contains('already exists'));
      expect(authMessage('something-new'), contains('something-new'));
    });
  });

  group('service', () {
    test('register signs in, sends verification and saves the profile', () async {
      final saved = <(String, bool)>[];
      final s = AuthService(FakeAuth(), onSignedIn: (u, {required isNew}) async => saved.add((u.email, isNew)));
      await s.start();
      final u = await s.register(' Aina ', 'aina@mail.com', 'kantoi2026');
      expect(u.name, 'Aina');
      expect(s.signedIn, isTrue);
      expect(s.verified, isFalse);
      expect((s.backend as FakeAuth).verificationsSent, 1);
      expect(saved, [('aina@mail.com', true)]);
    });

    test('verification shows up after refresh', () async {
      final b = FakeAuth();
      final s = AuthService(b);
      await s.register('Aina', 'aina@mail.com', 'kantoi2026');
      expect(await s.refresh(), isFalse);
      b.verify('aina@mail.com');
      expect(await s.refresh(), isTrue);
      expect(s.verified, isTrue);
    });

    test('wrong password is a readable failure; guest choice is remembered', () async {
      final b = FakeAuth();
      final s = AuthService(b);
      await s.register('Aina', 'aina@mail.com', 'kantoi2026');
      await s.signOut();
      expect(() => s.signIn('aina@mail.com', 'nope12345'), throwsA(isA<AuthFailure>()));
      await s.continueAsGuest();
      final again = AuthService(b);
      await again.start();
      expect(again.guest.value, isTrue);
      await again.signIn('aina@mail.com', 'kantoi2026');
      expect(again.guest.value, isFalse, reason: 'signing in clears guest mode');
    });

    test('without Firebase there is no sign-in screen', () async {
      auth = AuthService(null);
      await auth.start();
      expect(auth.available, isFalse);
      expect(needsSignIn, isFalse);
    });
  });

  group('screens', () {
    late FakeAuth backend;
    setUp(() async {
      backend = FakeAuth();
      auth = AuthService(backend);
      await auth.start();
    });
    tearDown(() => auth = AuthService(null));

    Widget app() => const MaterialApp(home: AuthGate(child: Scaffold(body: Text('HOME'))));

    /// A tall phone screen, so the whole form fits like on a real device.
    void phone(WidgetTester t) {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
    }

    testWidgets('gate shows sign in, then the app after registering', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);

      await t.tap(find.text('Create an account'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Aina');
      await t.enterText(find.widgetWithText(TextFormField, 'Email'), 'aina@mail.com');
      await t.enterText(find.widgetWithText(TextFormField, 'Password'), 'kantoi2026');
      await t.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'kantoi2027');
      await t.ensureVisible(find.text('Create account'));
      await t.tap(find.text('Create account'));
      await t.pumpAndSettle();
      expect(find.text('The passwords do not match'), findsOneWidget);

      await t.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'kantoi2026');
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.tap(find.byType(CheckboxListTile));
      await t.ensureVisible(find.text('Create account'));
      await t.tap(find.text('Create account'));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(backend.accounts.containsKey('aina@mail.com'), isTrue);
      expect(find.text('Account created'), findsOneWidget);
      // Let the toast close itself.
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
    });

    testWidgets('wrong password shows an error, forgot password sends a link', (t) async {
      await backend.register('Aina', 'aina@mail.com', 'kantoi2026');
      await backend.signOut();
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextFormField, 'Email'), 'aina@mail.com');
      await t.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrongpass1');
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      expect(find.text('Wrong email or password.'), findsOneWidget);

      await t.tap(find.text('Forgot password?'));
      await t.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);
      await t.tap(find.text('Send reset link'));
      await t.pumpAndSettle();
      expect(backend.resets, ['aina@mail.com'], reason: 'the email carries over from the sign-in form');
      expect(find.text('Check your inbox'), findsOneWidget);
    });

    testWidgets('continue without an account', (t) async {
      phone(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await t.tap(find.text('Continue without an account'));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
