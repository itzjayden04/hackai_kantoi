import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kantoi/engine/cases.dart';
import 'package:kantoi/engine/consistency.dart';
import 'package:kantoi/engine/evaluation.dart';
import 'package:kantoi/engine/fingerprint.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/engine/pdf_report.dart';
import 'package:kantoi/engine/relationship.dart';
import 'package:kantoi/engine/relationship_check.dart';
import 'package:kantoi/engine/report.dart';
import 'package:kantoi/engine/retention.dart';
import 'package:kantoi/engine/review.dart';
import 'package:kantoi/engine/rhythm.dart';
import 'package:kantoi/local_store.dart';
import 'package:kantoi/state.dart';
import 'package:kantoi/ui/emergency/hotlines.dart';
import 'package:shared_preferences/shared_preferences.dart';

const offline = InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false);
const noAi = LlmConfig(kind: LlmKind.none);

ChatMessage them(String text, DateTime t) => ChatMessage(time: t, sender: 'Amanda', text: text, fromMe: false);
ChatMessage me(String text, DateTime t) => ChatMessage(time: t, sender: 'Me', text: text, fromMe: true);

void main() {
  group('Branch 3: relationship', () {
    test('identifiers from pasted text, including a bare account number', () {
      final ids = extractIdentifiers('Account 5642 1234 5678, call +60 12-345 6789, facebook.com/amanda.lee.77');
      expect(ids, contains('564212345678'));
      expect(ids.any((i) => i.contains('facebook.com/amanda.lee.77')), isTrue);
      expect(ids.any((i) => i.contains('345')), isTrue);
    });

    test('one-line summary and safe next step', () {
      final start = DateTime(2026, 10, 1, 21);
      final msgs = [
        them('Hi, sorry wrong number. Is this Kevin?', start),
        me('No sorry', start.add(const Duration(minutes: 3))),
        them('Good night my dear, you are my soulmate', start.add(const Duration(days: 2))),
        them('My uncle gives me tips, I made 30% profit on a trading platform', start.add(const Duration(days: 5))),
        them('Just deposit RM3000 first, guaranteed returns', start.add(const Duration(days: 9))),
      ];
      final r = analyzeConversation(msgs, origin: Origin.wrongNumber, metOnVideo: false, money: MoneyAnswer.asked, identifiers: ['5642123456']);
      expect(r.level, RiskLevel.danger);
      expect(r.headline,
          'This chat follows the pattern of a love and investment scam. You have never met this person, and the first money request came 9 days after first contact.');
      expect(r.nextStep, contains('Ask for a live video call'));
      expect(r.nextStep, contains('press the red button'));
      expect(r.keyMessages.length, inInclusiveRange(1, 4));
      expect(r.identifiers, contains('5642123456'));
      expect(r.signals.any((s) => s.title == 'They have asked you for money'), isTrue);
    });

    test('texting rhythm: shifts, copy-paste and fast long replies', () {
      final msgs = <ChatMessage>[];
      final long = 'I understand how you feel, my dear. ' * 8;
      for (var d = 0; d < 8; d++) {
        final day = DateTime(2026, 9, 1 + d, 9);
        msgs.add(me('morning', day.subtract(const Duration(minutes: 1))));
        msgs.add(them('Good morning dear, have you eaten breakfast? Remember to drink water today', day));
        for (var k = 1; k < 4; k++) {
          msgs.add(them('Message $k on day $d about my work at the office', day.add(Duration(hours: k * 2))));
        }
        msgs.add(me('ok', day.add(const Duration(hours: 7))));
        msgs.add(them(long, day.add(const Duration(hours: 7, seconds: 30))));
      }
      final s = textingRhythm(msgs, theirMessages(msgs));
      expect(s.looksLikeShift, isTrue, reason: '${s.windowLength} ${s.firstHourSpread}');
      expect(s.duplicatePairs.length, greaterThanOrEqualTo(2));
      expect(s.fastLongReplies.length, greaterThanOrEqualTo(2));
      final titles = rhythmSignals(s).map((x) => x.title).toSet();
      expect(titles, containsAll(['Messages arrive in fixed shifts', 'Copy-paste messages', 'Long replies typed too fast']));
    });

    test('story contradictions found on the device', () {
      final t = DateTime(2026, 10, 1);
      final msgs = [
        them("I'm a doctor working with the UN", t),
        them('I am 34 years old', t.add(const Duration(days: 1))),
        them('I live in Singapore now', t.add(const Duration(days: 2))),
        them('As an engineer I travel a lot. I work as an engineer on oil rigs', t.add(const Duration(days: 6))),
        them("I'm 29 years old, still young haha", t.add(const Duration(days: 7))),
        them('I live in KL actually', t.add(const Duration(days: 8))),
      ];
      final c = findContradictions(msgs, (_) => true);
      expect(c.map((x) => x.topic).toSet(), containsAll(['job', 'age', 'where they live']));
      // KL and Kuala Lumpur are the same place.
      final same = findContradictions([them('I live in KL', t), them('I live in Kuala Lumpur', t)], (_) => true);
      expect(same, isEmpty);
    });

    test('AI contradictions are kept only when both quotes are verbatim', () {
      final lines = ['I work in a hospital in London', 'My office in Dubai is busy today', 'hello'];
      final j = {
        'contradictions': [
          {'topic': 'location', 'quote_a': 'hospital in London', 'quote_b': 'office in Dubai', 'why': 'Two different cities.'},
          {'topic': 'age', 'quote_a': 'I am 40', 'quote_b': 'hospital in London', 'why': 'Invented quote.'},
        ]
      };
      final c = parseContradictions(j, lines, [3, 7, 9]);
      expect(c.length, 1);
      expect(c.single.topic, 'where they live');
      expect(c.single.indexA, 3);
      expect(c.single.indexB, 7);
    });

    test('full check: AI step is logged as sent off the device, linked reports hook', () async {
      final t = DateTime(2026, 10, 1, 20);
      final msgs = [
        them('Hi, I work in a hospital in London', t),
        me('nice', t.add(const Duration(minutes: 2))),
        them('My office in Dubai is busy today', t.add(const Duration(days: 3))),
        them('Please bank in RM500 to account 5642 1234 5678 Maybank', t.add(const Duration(days: 4))),
      ];
      final aiJson = jsonEncode({
        'contradictions': [
          {'topic': 'location', 'quote_a': 'hospital in London', 'quote_b': 'office in Dubai', 'why': 'Two different cities.'}
        ]
      });
      String? sentBody;
      final mock = MockClient((req) async {
        sentBody = req.body;
        return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': aiJson}
                    ]
                  }
                }
              ]
            }),
            200);
      });
      List<String>? looked;
      linkedReportCounter = (ids) async {
        looked = ids;
        return 3;
      };
      addTearDown(() => linkedReportCounter = null);
      final r = await checkRelationship(msgs,
          metOnVideo: false,
          pastedIdentifiers: '0123456789',
          llm: const LlmConfig(kind: LlmKind.gemini, apiKey: 'test'),
          httpClient: mock);
      expect(sentBody, isNot(contains('nice')), reason: "the user's own messages are never sent");
      expect(r.signals.any((s) => s.title == 'Their story changed: where they live'), isTrue);
      expect(r.signals.any((s) => s.title == 'Already reported by others'), isTrue);
      expect(looked, containsAll(['0123456789', '564212345678']));
      final ai = r.log.firstWhere((s) => s.tool == 'AI consistency check');
      expect(ai.sentOffDevice, isTrue);
      expect(ai.status, StepStatus.done);
      expect(r.identifiers, contains('0123456789'));
    });

    test('AI failure falls back to on-device checks', () async {
      final mock = MockClient((_) async => http.Response('quota', 429));
      final t = DateTime(2026, 10, 1);
      final r = await checkRelationship([for (var i = 0; i < 4; i++) them('hello $i', t)],
          llm: const LlmConfig(kind: LlmKind.gemini, apiKey: 'x'), httpClient: mock);
      expect(r.log.firstWhere((s) => s.tool == 'AI consistency check').status, StepStatus.failed);
    });

    test('known-contact mode flags a likely hijacked account', () {
      final msgs = <ChatMessage>[];
      final start = DateTime(2026, 1, 1, 20);
      for (var i = 0; i < 40; i++) {
        final t = start.add(Duration(days: i * 2, hours: i % 5));
        msgs.add(ChatMessage(time: t, sender: 'Ali', text: 'weh jom makan kat mamak malam ni 😂😂 aku belanja lah', fromMe: false));
        msgs.add(me('ok jom', t.add(const Duration(minutes: 10))));
      }
      final last = start.add(const Duration(days: 82));
      msgs.addAll([
        ChatMessage(time: last, sender: 'Ali', text: 'Hello. I need your help urgently. Please transfer RM2,000 to this account now.', fromMe: false),
        ChatMessage(time: last.add(const Duration(minutes: 5)), sender: 'Ali', text: 'Hello. Do not tell anyone. I will explain later.', fromMe: false),
        ChatMessage(time: last.add(const Duration(minutes: 9)), sender: 'Ali', text: 'Hello. Please pay today, it is very urgent.', fromMe: false),
      ]);
      final sig = knownContactSignals(msgs, theirMessages(msgs));
      expect(sig.single.title, 'Sudden change in writing style, then a money request');
      final r = analyzeConversation(msgs);
      expect(r.patternType, 'a hijacked or cloned account');
      expect(r.nextStep, contains('number you already know'));
    });

    test('questionnaire keeps identifiers', () async {
      final r = await checkQuestionnaire({'origin': 2, 'money': 2}, pastedIdentifiers: '7012345678');
      expect(r.identifiers, ['7012345678']);
      expect(r.log, isNotEmpty);
    });
  });

  group('Branch 5: verdict and explainability', () {
    test('review summary holds no message text or numbers', () async {
      const text = 'Transfer RM500 to Maybank account 1234 5678 9012 now, call 012-345 6789';
      final inv = await investigate(text, options: offline);
      final s = jsonEncode(investigationSummary(inv));
      expect(s, isNot(contains('1234 5678')));
      expect(s, isNot(contains('012-345')));
      expect(s, isNot(contains('Transfer RM500')));
      final item = ReviewItem(id: '1', at: DateTime.now(), label: UserLabel.legit, kind: 'message', summary: investigationSummary(inv));
      expect(ReviewItem.fromJson(jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>).label, UserLabel.legit);
    });

    test('labelled set: at least 60 messages, good precision and recall', () async {
      final data = parseLabelledCsv(File('test/data/labelled_messages.csv').readAsStringSync());
      expect(data.length, greaterThanOrEqualTo(60));
      expect(data.map((d) => d.lang).toSet(), containsAll(['en', 'ms', 'manglish']));
      final r = await evaluate(data);
      final at40 = r.at(40);
      expect(at40.precision, greaterThanOrEqualTo(0.9), reason: r.format());
      expect(at40.recall, greaterThanOrEqualTo(0.85), reason: r.format());
      final hold = await evaluate(parseLabelledCsv(File('test/data/holdout_messages.csv').readAsStringSync()));
      expect(hold.at(40).precision, greaterThanOrEqualTo(0.85), reason: hold.format());
    });

    test('UCI SMS format and quoted CSV parse', () {
      final u = parseUciSms('ham\tSee you at 5\nspam\tWINNER! Claim your prize, call now\n');
      expect(u.map((m) => m.scam), [false, true]);
      final c = parseLabelledCsv('label,lang,type,text\nscam,en,x,"Hello, ""friend""\nline two"\n');
      expect(c.single.text, 'Hello, "friend"\nline two');
    });
  });

  group('Branch 6: act', () {
    test('platform channels and report pack order', () async {
      final ch = channelsFor(Situation.onlyReceived, platform: ContactPlatform.facebook);
      expect(ch.first.id, 'facebook');
      expect(channelsFor(Situation.onlyReceived, platform: ContactPlatform.smsOrCall).where((c) => c.id == 'mcmc').length, 1);
      expect(channelsFor(Situation.lostMoney, platform: ContactPlatform.tiktok).last.id, 'tiktok');

      final inv = await investigate('Pay RM300 to Maybank account 5642 1234 5678 to release your loan', options: offline);
      final d = ReportDetails()
        ..amount = 'RM300'
        ..when = '20/10/2026 3pm'
        ..paidFromBank = 'CIMB'
        ..paidTo = '564212345678'
        ..transactionRef = 'REF123';
      final fields = reportPack(nsrc, inv, d, Situation.lostMoney, 'masked');
      expect(fields.map((f) => f.label).toList(),
          ['Amount', 'Date and time', 'Your bank', "Scammer's account number", 'Transaction reference', 'Description']);
      expect(fields.last.value, contains('I transferred RM300 from my CIMB account to account 564212345678'));
    });

    test('PDF report builds, with a broken image skipped', () async {
      final inv = await investigate('Your parcel is held, pay RM2 at https://poslaju-my.top 😀 你好', options: offline);
      final c = ScamCase(id: 'x', createdAt: DateTime(2026, 10, 20), title: 'Parcel scam')..done['call997'] = DateTime(2026, 10, 20, 1);
      final pdf = await buildPdfReport(
        inv: inv,
        scamText: inv.artefact.text,
        details: ReportDetails()..amount = 'RM2',
        situation: Situation.lostMoney,
        scamCase: c,
        images: [EvidenceImage('broken.png', Uint8List.fromList([1, 2, 3]))],
      );
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
      expect(pdfSafe('a 😀 b ✓ “c”'), 'a ? b (done) "c"');
    });

    test('report without a checked message uses what the user typed', () async {
      final d = ReportDetails()
        ..amount = 'RM900'
        ..scammerContact = '+60 11-2222 3333'
        ..story = 'They said my parcel had drugs.';
      final text = buildReport(null, '', d, Situation.lostMoney);
      expect(text, contains('They said my parcel had drugs.'));
      expect(text, contains('+60 11-2222 3333'));
      expect(text, isNot(contains('Type:')));
      expect(text, isNot(contains('ORIGINAL MESSAGE')));
      final pack = reportPack(police, null, d, Situation.lostMoney, '');
      expect(pack.map((f) => f.label), containsAll(['Description', 'Amount', "Scammer's phone number"]));
      expect(reportPack(mcmc, null, d, Situation.lostMoney, '').first.value, '+60 11-2222 3333');
      expect(authorities.map(authorityLabel), ['Police', 'NSRC 997', 'Bank', 'MCMC']);
      final pdf = await buildPdfReport(inv: null, scamText: '', details: d, situation: Situation.lostMoney);
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    });

    test('bank hotlines are dialable and the call script shows blanks', () {
      for (final h in bankHotlines) {
        expect(h.dial, matches(RegExp(r'^0\d{8,9}$')), reason: h.bank);
      }
      expect(nsrcNumber, '997');
      final script = callScript(ReportDetails(), null);
      expect(script, contains('[amount]'));
      expect(script, contains('[your bank]'));
    });

    test('case checklist summary and reminders', () {
      final c = ScamCase(id: '1', createdAt: DateTime(2026, 10, 20, 8), title: 'Investment scam');
      c.done['call997'] = DateTime(2026, 10, 20, 8, 5);
      c.done['callBank'] = DateTime(2026, 10, 20, 8, 10);
      expect(c.summary, startsWith('Called 997 ✓, Called bank ✓'));
      expect(c.summary, contains('Police report pending'));
      expect(c.needsReminder(DateTime(2026, 10, 20, 9)), isFalse);
      expect(c.needsReminder(DateTime(2026, 10, 20, 12)), isTrue);
      c.snoozedUntil = DateTime(2026, 10, 21);
      expect(c.needsReminder(DateTime(2026, 10, 20, 12)), isFalse);
      expect(ScamCase.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>).done.length, 2);
    });
  });

  group('Branch 8: trust and privacy', () {
    test('retention prunes old items', () {
      final now = DateTime(2026, 10, 20);
      final items = [now.subtract(const Duration(days: 40)), now.subtract(const Duration(days: 10)), now];
      expect(pruneOld(List.of(items), (d) => d, Retention.forever, now: now), 0);
      final l30 = List.of(items);
      expect(pruneOld(l30, (d) => d, Retention.days30, now: now), 1);
      final l7 = List.of(items);
      expect(pruneOld(l7, (d) => d, Retention.days7, now: now), 2);
    });

    test('store: retention on load and delete all', () async {
      final old = ScamCase(id: 'old', createdAt: DateTime.now().subtract(const Duration(days: 45)), title: 't');
      final fresh = ScamCase(id: 'new', createdAt: DateTime.now(), title: 't');
      SharedPreferences.setMockInitialValues({
        'cases': [jsonEncode(old.toJson()), jsonEncode(fresh.toJson())],
        'ownDetails': ['Tan Mei Ling'],
      });
      await appState.load();
      await localStore.load();
      expect(localStore.cases.map((c) => c.id), ['new']);
      expect(appState.ownDetails, isNotEmpty);
      await localStore.deleteAll();
      expect(localStore.cases, isEmpty);
      expect(appState.ownDetails, isEmpty);
      expect(appState.llm.apiKey, LlmConfig.defaults.apiKey);
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys(), isEmpty);
    });
  });

  test('style profile basics', () {
    final p = profileOf(['weh jom makan 😂', 'aku nak balik']);
    expect(p.emojiPerMessage, greaterThan(0));
    expect(p.malayShare, 1);
  });
}
