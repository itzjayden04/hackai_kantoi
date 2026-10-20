import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/guard/app_check.dart';
import 'package:kantoi/guard/call_check.dart';
import 'package:kantoi/guard/guard_control.dart';
import 'package:kantoi/guard/guard_core.dart';
import 'package:kantoi/guard/link_guard.dart';
import 'package:kantoi/ui/protection_page.dart';
import 'package:kantoi/ui/theme.dart';

void main() {
  group('Web & link blocker', () {
    test('reads links from the address bar, not searches', () {
      expect(addressBarLink('pos-tracking-my.top/pay'), 'https://pos-tracking-my.top/pay');
      expect(addressBarLink('https://www.maybank2u.com.my'), 'https://www.maybank2u.com.my');
      expect(addressBarLink('how to bake bread'), isNull);
      expect(addressBarLink('photo.jpg'), isNull);
      expect(addressBarLink('hello'), isNull);
    });

    test('closes look-alike bank sites and leaves official ones open', () async {
      final fake = await siteVerdict('maybank2u-secure-login.top/verify');
      expect(fake!.block, isTrue);
      expect(fake.reasons, contains('Pretends to be Maybank'));
      final real = await siteVerdict('www.maybank2u.com.my/home');
      expect(real!.block, isFalse);
      expect((await siteVerdict('cimbclicks.com.my'))!.block, isFalse);
    });

    test('catches Cyrillic look-alike letters', () async {
      final v = await siteVerdict('mаybank.com'); // Cyrillic "а"
      expect(v!.block, isTrue);
    });

    test('a cheap domain ending alone is not enough to close a page', () async {
      final v = await siteVerdict('myblog.xyz');
      expect(v!.block, isFalse);
      expect(v.level, RiskLevel.caution);
    });

    test('sites on the scam list are closed, and demo entries say so', () async {
      final v = await siteVerdict('random-shop.net', known: (_) => (true, true));
      expect(v!.block, isTrue);
      expect(v.reasons.first, contains('demo'));
    });

    test('GuardCore caches verdicts per address', () async {
      var lookups = 0;
      final core = GuardCore(knownSite: (_) {
        lookups++;
        return (false, false);
      });
      await core.checkSite('example.org');
      await core.checkSite('example.org');
      expect(lookups, 1);
      expect(await core.checkSite('not a link'), isNull);
    });
  });

  group('Call guard', () {
    test('normal Malaysian numbers raise no warning', () {
      expect(checkCaller('+60 12-345 6789').warn, isFalse);
      expect(checkCaller('011-1234 5678').warn, isFalse);
      expect(checkCaller('03-2345 6789').warn, isFalse);
      expect(checkCaller('1300 88 6688').warn, isFalse);
    });

    test('faked or odd numbers are flagged', () {
      expect(checkCaller('+60 12-345 67').level, RiskLevel.suspicious);
      expect(checkCaller('+600 3 1234 5678').level, RiskLevel.suspicious);
      expect(checkCaller('+882 1234 5678').level, RiskLevel.suspicious);
      expect(checkCaller('0000000000').warn, isTrue);
    });

    test('overseas and hidden callers get a gentle note only', () {
      expect(checkCaller('+44 20 7946 0000').level, RiskLevel.caution);
      expect(checkCaller(null).level, RiskLevel.caution);
      expect(checkCaller('').title, 'Hidden number');
    });

    test('numbers the user marked or on the scam list are dangerous', () {
      expect(checkCaller('+60123456789', marked: true).level, RiskLevel.danger);
      final listed = checkCaller('012-345 6789', listed: (n) => (n == '60123456789', false));
      expect(listed.level, RiskLevel.danger);
      expect(listed.number, '+60123456789');
    });
  });

  group('New apps', () {
    test('a store app with normal access is fine', () {
      final v = checkNewApp(const NewApp(name: 'Grab', package: 'com.grabtaxi.passenger', installer: 'com.android.vending'));
      expect(v.level, RiskLevel.safe);
    });

    test('a side-loaded app that reads SMS and controls the screen is a scam app', () {
      final v = checkNewApp(const NewApp(
        name: 'Pos Laju Tracking',
        package: 'com.xyz.parcel',
        permissions: ['android.permission.RECEIVE_SMS', 'android.permission.READ_SMS'],
        accessibility: true,
      ));
      expect(v.level, RiskLevel.danger);
      expect(v.toJson()['warn'], isTrue);
      expect(v.reasons.first, 'Installed from outside an app store');
    });

    test('a side-loaded app using a bank name is suspicious', () {
      final v = checkNewApp(NewApp.fromMap({'name': 'Maybank Secure', 'package': 'com.mb.secure', 'installer': 'com.whatsapp'}));
      expect(v.level, RiskLevel.suspicious);
    });
  });

  test('chat badge scores the whole chat seen so far', () {
    final core = GuardCore();
    final first = core.checkChat(app: 'com.whatsapp', chat: 'Amanda', visible: [('Hi, is this Mr Tan? Sorry, wrong number!', true)]);
    expect(first['messages'], 1);
    final later = core.checkChat(app: 'com.whatsapp', chat: 'Amanda', visible: [
      ('Hi, is this Mr Tan? Sorry, wrong number!', true),
      ('My uncle is a crypto trader. Guaranteed 30% profit every week.', true),
      ('Dear, transfer RM5000 to start today only', true),
    ]);
    expect(later['messages'], 3);
    expect(RiskLevel.values.byName(later['level'] as String).index, greaterThanOrEqualTo(RiskLevel.suspicious.index));
    expect(later['signals'] as List, isNotEmpty);
  });

  testWidgets('Protection centre shows real counters, guards and warnings', (tester) async {
    final s = GuardStatus(
      supported: true,
      enabled: true,
      perms: const {'notifications': true, 'accessibility': true, 'overlay': true},
      guards: const {'photos': false},
      stats: const {'warnings': 4, 'pages': 2, 'calls': 1},
      recent: [
        GuardAlert('com.android.chrome', 'pos-tracking-my.top', 'danger', 'Very likely a scam', 'This website is known for scams.', '',
            const ['On Kantoi\'s list of scam websites'], DateTime.now(), kind: 'site', target: 'pos-tracking-my.top'),
      ],
    );
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ProtectionPage(initial: s)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Auto-protection: on'), findsOneWidget);
    expect(find.text('Pages blocked'), findsOneWidget);
    expect(find.text('Calls'), findsOneWidget);
    expect(find.text('Web & link blocker'), findsOneWidget);
    expect(find.text('5 ON'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('pos-tracking-my.top'), 300);
    expect(find.text('pos-tracking-my.top'), findsOneWidget);
  });
}
