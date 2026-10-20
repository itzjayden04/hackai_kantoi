import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/awareness/checkup.dart';
import 'package:kantoi/awareness/coach.dart';
import 'package:kantoi/awareness/drills.dart';
import 'package:kantoi/awareness/explainers.dart';
import 'package:kantoi/awareness/guardian.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/ui/checkup_page.dart';
import 'package:kantoi/ui/drill_page.dart';
import 'package:kantoi/ui/explainer_card.dart';
import 'package:kantoi/ui/guardian_ui.dart';
import 'package:kantoi/ui/learn_page.dart';
import 'package:kantoi/ui/result_view.dart';
import 'package:kantoi/ui/warning_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

const offline = InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false);

/// Taps every word that overlaps the given cues.
List<Token> tapsFor(Drill d, Iterable<DrillCue> cues) {
  final toks = tokenize(d.full);
  return toks.where((t) => cues.any((c) {
        final s = d.span(c)!;
        return t.$1 < s.$2 && t.$2 > s.$1;
      })).toList();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('drill bank', () {
    test('has enough drills of every kind', () {
      expect(drills.length, greaterThanOrEqualTo(30));
      expect(drills.where((d) => !d.isScam).length, greaterThanOrEqualTo(8));
      for (final l in DrillLevel.values) {
        expect(drills.where((d) => d.level == l).length, greaterThanOrEqualTo(6), reason: l.name);
      }
      for (final c in Channel.values) {
        expect(drills.any((d) => d.channel == c), isTrue, reason: c.name);
      }
      expect(drills.map((d) => d.id).toSet().length, drills.length);
    });

    test('every cue quote appears in the drill', () {
      for (final d in drills) {
        expect(d.cues, isNotEmpty, reason: d.id);
        for (final c in d.cues) {
          expect(d.span(c), isNotNull, reason: '${d.id}: "${c.quote}"');
        }
        if (d.isScam) expect(d.riskCues, isNotEmpty, reason: d.id);
        if (!d.isScam) expect(d.riskCues, isEmpty, reason: d.id);
        expect(explainerById(d.explainerId), isNotNull, reason: d.id);
      }
    });
  });

  group('grading', () {
    final d = drills.firstWhere((d) => d.id == 'parcel-1');

    test('finds tapped cues and reports the missed ones', () {
      final urgency = d.cues.firstWhere((c) => c.category == CueCategory.urgency);
      final link = d.cues.firstWhere((c) => c.category == CueCategory.link);
      final r = grade(d, tapsFor(d, [urgency, link]), saidScam: true);
      expect(r.found.map((c) => c.category), containsAll([CueCategory.urgency, CueCategory.link]));
      expect(r.missed.map((c) => c.category), containsAll([CueCategory.payment, CueCategory.impersonation]));
      expect(r.falseTaps, isEmpty);
      expect(r.verdictRight, isTrue);
      expect(r.passed, isTrue);
    });

    test('a wrong verdict fails and stray taps are counted', () {
      final toks = tokenize(d.full);
      final stray = toks.firstWhere((t) => d.full.substring(t.$1, t.$2) == 'returned:');
      final r = grade(d, [stray], saidScam: false);
      expect(r.verdictRight, isFalse);
      expect(r.passed, isFalse);
      expect(r.falseTaps, [stray]);
      expect(r.missed.length, d.riskCues.length);
    });

    test('genuine drill passes with no taps', () {
      final g = drills.firstWhere((d) => d.id == 'legit-tac');
      final r = grade(g, const [], saidScam: false);
      expect(r.passed, isTrue);
    });
  });

  group('coach', () {
    test('missed cues come back in later drills', () {
      final c = Coach();
      final love = drills.firstWhere((d) => d.id == 'love-1');
      c.record(grade(love, const [], saidScam: false));
      expect(c.review, contains(CueCategory.romance));
      expect(c.streak, 0);
      c.recentIds.clear();
      var withRomance = 0;
      final rnd = Random(7);
      for (var i = 0; i < 300; i++) {
        if (c.next(random: rnd).categories.contains(CueCategory.romance)) withRomance++;
      }
      final share = drills.where((d) => d.categories.contains(CueCategory.romance)).length / drills.length;
      expect(withRomance / 300, greaterThan(share * 1.5));
    });

    test('finding every cue clears the review and builds a streak', () {
      final c = Coach();
      final love = drills.firstWhere((d) => d.id == 'love-1');
      c.record(grade(love, const [], saidScam: false));
      c.record(grade(love, tapsFor(love, love.riskCues), saidScam: true));
      expect(c.review, isNot(contains(CueCategory.romance)));
      expect(c.streak, 1);
      expect(c.skill(CueCategory.romance).hits, 3);
    });

    test('difficulty goes up after 4 passes and down after misses', () {
      final c = Coach();
      final easy = drills.where((d) => d.level == DrillLevel.obvious && d.isScam).toList();
      for (final d in easy.take(4)) {
        c.record(grade(d, tapsFor(d, d.riskCues), saidScam: true));
      }
      expect(c.level, DrillLevel.medium);
      expect(c.streak, 4);
      for (final d in easy.take(2)) {
        c.record(grade(d, const [], saidScam: false));
      }
      expect(c.level, DrillLevel.obvious);
      expect(c.streak, 0);
      expect(c.bestStreak, 4);
    });

    test('genuine drills train not over-flagging', () {
      final c = Coach();
      final g = drills.firstWhere((d) => d.id == 'legit-shopee');
      c.record(grade(g, const [], saidScam: true));
      expect(c.review.first, CueCategory.legitimacy);
      expect(c.skill(CueCategory.legitimacy).misses, 1);
    });

    test('progress is saved and restored', () async {
      final a = Coach();
      await a.load();
      final d = drills.first;
      a.record(grade(d, tapsFor(d, d.riskCues), saidScam: true));
      await Future<void>.delayed(Duration.zero);
      final b = Coach();
      await b.load();
      expect(b.done, 1);
      expect(b.streak, 1);
      expect(b.skill(CueCategory.link).hits, 1);
      expect(b.recentIds, [d.id]);
    });
  });

  group('explainers', () {
    test('every engine scam type maps to the right card', () {
      const cases = {
        'Parcel fee scam': 'parcel',
        'Pos Malaysia phishing': 'parcel',
        'Bank phishing': 'phishing',
        'Maybank phishing': 'phishing',
        'Fake officer (Macau) scam': 'officer',
        'Job task scam': 'job',
        'Investment scam': 'investment',
        'Love scam': 'love',
        'Love and investment scam': 'love_investment',
        'Prize scam': 'prize',
        'Account phishing': 'otp',
        'Fake LHDN refund': 'lhdn',
        'Fake seller scam': 'ecommerce',
        'E-commerce scam': 'ecommerce',
        'Hijacked friend account': 'friend',
        'Legitimate message': 'legit',
        'Unclear': 'general',
      };
      cases.forEach((type, id) => expect(explainerFor(type).id, id, reason: type));
    });

    test('ambiguous types are settled by the cues', () {
      expect(explainerFor('Investment or job scam', cueTitles: ['Easy-money job offer']).id, 'job');
      expect(explainerFor('Investment or job scam', cueTitles: ['Unrealistic returns']).id, 'investment');
      expect(explainerFor('Suspicious message', categories: [CueCategory.authority, CueCategory.fear, CueCategory.secrecy]).id, 'officer');
      expect(explainerFor('Suspicious message', categories: [CueCategory.urgency]).id, 'general');
    });

    test('each card is complete', () {
      for (final e in [...explainers, generalExplainer]) {
        expect(e.steps.length, inInclusiveRange(3, 4), reason: e.id);
        expect(e.signs.length, 3, reason: e.id);
        expect(e.todo, isNotEmpty, reason: e.id);
        expect(e.example, isNotEmpty, reason: e.id);
        for (final s in [e.title, e.summary, ...e.steps, ...e.signs, ...e.todo]) {
          expect(s.contains('—'), isFalse, reason: 'em-dash in ${e.id}');
        }
      }
    });
  });

  group('guardian', () {
    test('phone numbers are normalised to Malaysia', () {
      expect(normalisePhone('012-345 6789'), '60123456789');
      expect(normalisePhone('+60 12-345 6789'), '60123456789');
      expect(normalisePhone('0060123456789'), '60123456789');
      expect(normalisePhone('11-2345 6789'), '601123456789');
      expect(normalisePhone('+65 9123 4567'), '6591234567');
      expect(normalisePhone('hello'), isNull);
      expect(normalisePhone('123'), isNull);
    });

    test('alert never contains the message or personal details', () async {
      const msg = 'Inspector Tan here, PDRM. Your IC 900101-14-5678 is linked to money laundering. A warrant is issued. '
          'Do not tell anyone. Transfer RM9,000 to safe account 5123456789012 Maybank today.';
      final inv = await investigate(msg, options: offline);
      expect(inv.verdict.level, RiskLevel.danger);
      final a = guardianAlert(guardianName: 'Aisyah', inv: inv);
      expect(a, startsWith('Hi Aisyah'));
      expect(a, contains('Very likely a scam'));
      expect(a, contains('Fake officer'));
      expect(a, contains('pay or transfer money'));
      for (final bad in ['900101', '5123456789012', '9,000', 'Inspector Tan', 'laundering']) {
        expect(a.contains(bad), isFalse, reason: bad);
      }
      final e = guardianAlert(guardianName: 'Aisyah', inv: inv, emergency: true);
      expect(e, contains('already paid'));
      expect(e.contains('5123456789012'), isFalse);
    });

    test('links open WhatsApp or SMS with the text', () {
      const g = Guardian(name: 'Ali', phone: '012-345 6789', consent: true);
      final u = guardianUri(g, 'Hi Ali, call me');
      expect(u.toString(), 'https://wa.me/60123456789?text=Hi%20Ali%2C%20call%20me');
      final s = guardianUri(const Guardian(name: 'Ali', phone: '0123456789', consent: true, useSms: true), 'Hi');
      expect(s.toString(), 'sms:+60123456789?body=Hi');
    });

    test('no consent means no alert button', () async {
      final store = GuardianStore();
      await store.save(const Guardian(name: 'Ali', phone: '0123456789'));
      expect(store.ready, isNull);
      await store.save(const Guardian(name: 'Ali', phone: '0123456789', consent: true));
      expect(store.ready?.name, 'Ali');
      final again = GuardianStore();
      await again.load();
      expect(again.ready?.phone, '0123456789');
    });
  });

  group('check-up', () {
    test('scores answers and lists what to fix', () async {
      final c = Checkup();
      await c.load();
      for (final i in checkItems) {
        c.answer(i.id, i.id == 'codeWord' || i.id == 'semakMule' ? Answer.no : Answer.yes);
      }
      expect(c.finished, isTrue);
      expect(c.safeCount, checkItems.length - 2);
      expect(c.toFix.map((i) => i.id), ['codeWord', 'semakMule']);
      c.answer('codeWord', Answer.yes);
      await Future<void>.delayed(Duration.zero);
      final again = Checkup();
      await again.load();
      expect(again.toFix.map((i) => i.id), ['semakMule']);
      expect(checkItems.length, 8);
    });
  });

  group('screens', () {
    testWidgets('Learn tab shows practice, check-up, guardian and library', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: LearnPage())));
      await t.pumpAndSettle();
      expect(find.text('Practice: 2 minutes'), findsOneWidget);
      expect(find.text('Safety check-up'), findsOneWidget);
      expect(find.text('Add a family guardian'), findsOneWidget);
      expect(find.text('Parcel fee scam'), findsOneWidget);
    });

    testWidgets('drill screen is labelled as practice and gives feedback', (t) async {
      await t.pumpWidget(const MaterialApp(home: DrillPage()));
      await t.pumpAndSettle();
      expect(find.text('Practice. This is not a real message.'), findsOneWidget);
      await t.ensureVisible(find.text('Scam'));
      await t.tap(find.text('Scam'));
      await t.pumpAndSettle();
      expect(find.text('Next practice'), findsOneWidget);
      expect(find.text('Practice. This is not a real message.'), findsOneWidget);
    });

    testWidgets('result view shows the explainer tile and the picture option', (t) async {
      final inv = (await t.runAsync(() => investigate(
          'POS MALAYSIA: Your parcel is held due to unpaid fee RM2.50. Pay within 24 hours: https://poslaju-my-redelivery.top/pay',
          options: offline)))!;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ResultView(inv: inv)))));
      await t.pumpAndSettle();
      expect(find.text('How this scam works'), findsOneWidget);
      await t.tap(find.text('Warn family'));
      await t.pumpAndSettle();
      expect(find.text('Send as a picture'), findsOneWidget);
      expect(find.text('Copy as text'), findsOneWidget);
    });

    testWidgets('warning poster renders without the message', (t) async {
      final inv = (await t.runAsync(() => investigate('Hi dear, this is my new number. Can you bank in RM800 to 5123456789012?', options: offline)))!;
      final content = WarningContent.fromInvestigation(inv);
      expect(content.signs.length, 3);
      await t.pumpWidget(MaterialApp(home: WarningImagePage(content: content)));
      await t.pumpAndSettle();
      expect(find.text('SCAM WARNING'), findsOneWidget);
      expect(find.text('Checked with Kantoi'), findsOneWidget);
      expect(find.textContaining('5123456789012'), findsNothing);
    });

    testWidgets('every screen fits a small phone', (t) async {
      t.view.physicalSize = const Size(360, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      for (final w in <Widget>[
        const Scaffold(body: LearnPage()),
        const DrillPage(),
        const CheckupPage(),
        const GuardianPage(),
        for (final e in [...explainers, generalExplainer]) ExplainerPage(e: e),
        WarningImagePage(content: WarningContent.fromExplainer(explainers.first)),
      ]) {
        await t.pumpWidget(MaterialApp(home: w));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
      for (final d in drills) {
        await t.pumpWidget(MaterialApp(home: DrillPage(key: ValueKey(d.id), first: d)));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: d.id);
        await t.scrollUntilVisible(find.text('Genuine'), 200);
        await t.tap(find.text('Genuine'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: d.id);
      }
    });
  });
}
