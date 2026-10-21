import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/engine/cues_extra.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/engine/relationship.dart';
import 'package:kantoi/guard/chat_ai.dart';
import 'package:kantoi/guard/guard_core.dart';

const _rank = ['safe', 'caution', 'suspicious', 'danger'];

Future<Map<String, dynamic>> _one(String text, {GuardCore? core, String chat = 'Aiman'}) async =>
    (await (core ?? GuardCore()).check(app: 'com.whatsapp', chat: chat, text: text, network: false))!;

Matcher _atLeast(String level) => predicate<String>((l) => _rank.indexOf(l) >= _rank.indexOf(level), 'at least $level');

void main() {
  group('friend asking for money', () {
    // (message, lowest level expected). Every one must alert.
    const cases = <(String, String)>[
      ('Hey can you give me some money quick? I really need it', 'caution'),
      ('bro can transfer me RM500 now? urgent, i pay back tmr', 'caution'),
      ('Boleh pinjam duit RM300 sekejap? Emergency ni, nanti aku bayar balik', 'caution'),
      ('Bro send me 300 now pls, later I explain', 'caution'),
      ('Hi can you lend me RM150? I will return it next week', 'caution'),
      ("hey I'm stuck, need money fast pls send to this account 1234567890 maybank", 'suspicious'),
      ('Sis tolong bank in RM200 cepat, phone aku rosak guna nombor baru ni', 'suspicious'),
      ('Pls TNG me RM100 now, my card blocked. Dont tell mum ok', 'suspicious'),
      ('Can you buy me a Google Play gift card RM200 and send me the code? urgent', 'suspicious'),
      ('Bro I accidentally sent you a 6 digit code, can you send it to me?', 'danger'),
    ];
    for (final (text, level) in cases) {
      test(text, () async {
        final r = await _one(text);
        expect(r['alert'], isTrue);
        expect(r['level'], _atLeast(level));
        expect(r['moneyAsk'], isTrue);
        expect(r['alertKind'], _rank.indexOf(r['level'] as String) >= 2 ? 'pause' : 'notify');
        expect(r['checkedBy'], 'Checked on this phone');
      });
    }

    test('a caution-level ask tells the user to call their friend', () async {
      final r = await _one('Bro send me 300 now pls, later I explain');
      expect(r['level'], 'caution');
      expect(r['headline'], contains('Aiman is asking for money'));
      expect(r['nextStep'], contains('Call Aiman'));
    });
  });

  group('other scams', () {
    for (final text in [
      'Pos Laju: Your parcel is held due to unpaid fee RM2.50. Pay at https://poslaju-my.top/pay within 24 hours',
      'Join our VIP investment group, guaranteed 30% daily profit. Min deposit RM500',
      'Part time job: like and follow TikTok, earn RM300 daily. Add me on Telegram',
      'This is LHDN officer. You have unpaid tax, a warrant will be issued. Pay now to avoid arrest',
      'PDRM: Akaun bank anda terlibat dengan pengubahan wang haram. Jangan beritahu sesiapa',
      'Telegram security: someone tried to log in to your account. Send us the login code you just received.',
    ]) {
      test(text, () async {
        final r = await _one(text, chat: 'Unknown');
        expect(r['alert'], isTrue);
        expect(r['alertKind'], 'pause');
      });
    }
  });

  test('ordinary messages between friends never alert', () async {
    for (final text in [
      'dinner tonight?',
      'I transferred you the RM20 for lunch',
      'Thanks for paying me back the RM50 yesterday!',
      'I owe u rm25 for the movie ticket right? I transfer u tonight k',
      'Eh u reach home already? Traffic damn jam just now, I stuck at Federal Highway 1 hour',
      'Can you send me the photos from the wedding?',
      "Can't talk now, in a meeting. Call you later",
      'Jom makan nasi lemak esok pagi? Aku belanja',
    ]) {
      final r = await _one(text);
      expect(r['alert'], isFalse, reason: text);
      expect(r['level'], 'safe', reason: text);
    }
  });

  test('bank code messages are not money requests', () {
    for (final text in [
      'RM0 Maybank: Your TAC for Third Party Transfer of RM50.00 to account ending 1234 is 482913. Valid for 3 minutes.',
      'CIMB: Your OTP is 551203 for DuitNow transfer RM120.00. Never share your OTP with anyone.',
      'TNB: Bil elektrik anda bagi bulan Oktober ialah RM98.40. Bayar melalui aplikasi myTNB sebelum 30/10.',
    ]) {
      expect(moneyAskIn(text).level, isNull, reason: text);
    }
  });

  test('small amounts between friends stay at caution', () {
    expect(moneyAskIn('Can you TNG me RM10 now for the mamak').level, RiskLevel.caution);
    expect(moneyAskIn('Can you TNG me RM400 now, urgent').level, RiskLevel.suspicious);
  });

  test('alerts again only when the level rises', () async {
    final g = GuardCore();
    final a = await _one('Hi can you lend me RM150? I will return it next week', core: g);
    expect(a['alert'], isTrue);
    expect(a['level'], 'caution');
    final b = await _one('Can you help me with RM200 also? I pay you back tmr', core: g);
    expect(b['alert'], isFalse);
    final c = await _one('My phone rosak, this is my new number. Transfer to this account 1234567890 maybank now', core: g);
    expect(c['alert'], isTrue);
    expect(c['alertKind'], 'pause');
  });

  group('AI second opinion', () {
    late List<String> prompts;
    ChatAi fakeAi(Map<String, dynamic> Function(String user) reply, {Duration? delay, Duration timeout = const Duration(seconds: 8), int perDay = 60, DateTime Function()? now}) {
      return ChatAi(
        config: () => const LlmConfig(kind: LlmKind.none),
        timeout: timeout,
        perDay: perDay,
        now: now,
        classifier: (system, user) async {
          prompts.add(user);
          if (delay != null) await Future<void>.delayed(delay);
          return reply(user);
        },
      );
    }

    setUp(() => prompts = []);

    test('raises the level and is marked as an online AI check', () async {
      final g = GuardCore(ai: fakeAi((_) => {'level': 'danger', 'scam_type': 'Job task scam', 'reasons': ['Pays for simple likes, then asks for deposits'], 'advice': 'Do not pay.'}));
      final r = await _one('Hi, simple tasks from home, earn RM150 to RM500 a day. Reply YES for details', core: g, chat: 'HR Mira');
      expect(prompts, hasLength(1));
      expect(r['level'], 'danger');
      expect(r['ai'], 'cloud');
      expect(r['aiLevel'], 'danger');
      expect(r['scamType'], 'Job task scam');
      expect(r['checkedBy'], contains('AI online'));
      expect((r['reasons'] as List), contains('Pays for simple likes, then asks for deposits'));
    });

    test('sends only the masked last messages', () async {
      final g = GuardCore(ai: fakeAi((_) => {'level': 'suspicious', 'scam_type': 'Hijacked friend account', 'reasons': []}));
      await _one('Siti, are you free?', core: g, chat: 'Siti Aminah');
      await g.check(app: 'com.whatsapp', chat: 'Siti Aminah', text: 'Yes why', incoming: false, network: false);
      await _one('Pls bank in RM300 to 1234567890 maybank, call me at 012-345 6789. My IC 900101-14-5678', core: g, chat: 'Siti Aminah');
      expect(prompts, hasLength(1));
      final p = prompts.single;
      expect(p, contains('Them: '));
      expect(p, contains('Me: Yes why'));
      expect(p, isNot(contains('1234567890')));
      expect(p, isNot(contains('345 6789')));
      expect(p, isNot(contains('900101')));
      expect(p, isNot(contains('Siti Aminah')));
      expect(p, contains('RM300'));
    });

    test('is not asked about plain messages', () async {
      final g = GuardCore(ai: fakeAi((_) => {'level': 'danger', 'scam_type': 'x', 'reasons': []}));
      final r = await _one('dinner tonight?', core: g);
      expect(prompts, isEmpty);
      expect(r['level'], 'safe');
      expect(r['ai'], 'none');
    });

    test('cannot lower what the built-in checks found', () async {
      final g = GuardCore(ai: fakeAi((_) => {'level': 'safe', 'scam_type': 'Normal chat', 'reasons': ['Looks friendly']}));
      final r = await _one('bro can transfer me RM500 now? urgent, i pay back tmr', core: g);
      expect(prompts, hasLength(1));
      expect(r['level'], _atLeast('suspicious'));
      expect(r['alert'], isTrue);
      expect(r['ai'], 'cloud');
    });

    test('a slow AI falls back to the built-in checks', () async {
      final g = GuardCore(ai: fakeAi((_) => {'level': 'danger'}, delay: const Duration(milliseconds: 400), timeout: const Duration(milliseconds: 50)));
      final r = await _one('bro can transfer me RM500 now? urgent, i pay back tmr', core: g);
      expect(prompts, hasLength(1));
      expect(r['ai'], 'none');
      expect(r['alert'], isTrue);
      expect(r['checkedBy'], 'Checked on this phone');
    });

    test('rate limits per chat and per day, and caches answers', () async {
      var t = DateTime(2026, 10, 21, 9);
      final ai = fakeAi((_) => {'level': 'caution', 'scam_type': 'x', 'reasons': []}, perDay: 2, now: () => t);
      const them = ChatMessage(sender: 'A', text: 'lend me RM50', fromMe: false);
      expect(await ai.judge('a', [them]), isNotNull);
      expect(await ai.judge('a', [them]), isNotNull, reason: 'cached');
      const more = ChatMessage(sender: 'A', text: 'lend me RM80 la', fromMe: false);
      expect(await ai.judge('a', [them, more]), isNull, reason: 'same chat within 20s');
      t = t.add(const Duration(seconds: 21));
      expect(await ai.judge('a', [them, more]), isNotNull);
      expect(await ai.judge('b', [more]), isNull, reason: 'daily cap');
      expect(prompts, hasLength(2));
      t = t.add(const Duration(days: 1));
      expect(await ai.judge('b', [more]), isNotNull);
    });

    test('ignores replies without a valid level', () async {
      final ai = fakeAi((_) => {'level': 'totally fine', 'scam_type': 'x'});
      expect(await ai.judge('a', [const ChatMessage(sender: 'A', text: 'lend me RM50', fromMe: false)]), isNull);
    });

    test('without an AI service nothing is sent', () async {
      final ai = ChatAi(config: () => const LlmConfig(kind: LlmKind.gemini));
      expect(ai.available, isFalse);
      final r = await _one('bro can transfer me RM500 now? urgent', core: GuardCore(ai: ai));
      expect(r['ai'], 'none');
    });
  });
}
