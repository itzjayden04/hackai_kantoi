import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kantoi/engine/forensics/allowlist.dart';
import 'package:kantoi/engine/forensics/hop_facts.dart';
import 'package:kantoi/engine/forensics/homoglyphs.dart';
import 'package:kantoi/engine/forensics/keys.dart';
import 'package:kantoi/engine/forensics/landing_page.dart';
import 'package:kantoi/engine/forensics/link_forensics.dart';
import 'package:kantoi/engine/forensics/mixed_language.dart';
import 'package:kantoi/engine/forensics/reputation.dart';
import 'package:kantoi/engine/forensics/safe_fetch.dart';
import 'package:kantoi/engine/forensics/scam_scripts.dart';
import 'package:kantoi/engine/forensics/tls_info.dart';
import 'package:kantoi/engine/forensics/urlscan.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';

const offline = InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false);

LogStep _log(String tool, String action, {bool sentOffDevice = false}) =>
    LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice);

// Recorded sample responses from each service.
final _now = DateTime.now().toUtc();
final _rdapDomain = jsonEncode({
  'events': [
    {'eventAction': 'registration', 'eventDate': _now.subtract(const Duration(days: 3)).toIso8601String()}
  ],
  'entities': [],
});
const _doh = '{"Status":0,"TC":false,"Answer":[{"name":"poslaju-my-redelivery.top.","type":5,"TTL":300,"data":"edge.example.net."},'
    '{"name":"edge.example.net.","type":1,"TTL":300,"data":"203.0.113.7"}]}';
const _rdapIp = '{"objectClassName":"ip network","handle":"203.0.113.0 - 203.0.113.255","name":"CLOUDNET-SG","country":"SG",'
    '"entities":[{"roles":["registrant"],"vcardArray":["vcard",[["version",{},"text","4.0"],["fn",{},"text","Example Cloud Hosting Pte Ltd"]]]}]}';
const _ipWhoIs = '{"ip":"203.0.113.7","success":true,"country":"Singapore","country_code":"SG","connection":{"asn":64500,"org":"Example Cloud","isp":"Example ISP"}}';
const _gsbHit = '{"matches":[{"threatType":"SOCIAL_ENGINEERING","platformType":"ANY_PLATFORM","threatEntryType":"URL","threat":{"url":"https://poslaju-my-redelivery.top/pay"}}]}';
const _vtHit = '{"data":{"id":"x","type":"url","attributes":{"last_analysis_stats":{"harmless":58,"malicious":6,"suspicious":1,"undetected":22,"timeout":0}}}}';
const _urlhausNone = '{"query_status":"no_results"}';
const _urlhausHost = '{"query_status":"ok","urlhaus_reference":"https://urlhaus.abuse.ch/host/x/","host":"poslaju-my-redelivery.top","url_count":"2",'
    '"urls":[{"id":"1","url":"https://poslaju-my-redelivery.top/a.apk","url_status":"online","threat":"malware_download","tags":["apk"]},'
    '{"id":"2","url":"https://poslaju-my-redelivery.top/b","url_status":"offline","threat":"malware_download","tags":[]}]}';
const _uuid = '0e37e828-a9d9-45c0-ac50-1ca579b86c72';
const _urlscanSubmit = '{"message":"Submission successful","uuid":"$_uuid","result":"https://urlscan.io/result/$_uuid/","api":"https://urlscan.io/api/v1/result/$_uuid/","visibility":"unlisted","country":"my"}';
const _urlscanResult = '{"task":{"uuid":"$_uuid","url":"https://poslaju-my-redelivery.top/pay","screenshotURL":"https://urlscan.io/screenshots/$_uuid.png"},'
    '"page":{"url":"https://poslaju-my-redelivery.top/pay/login","domain":"poslaju-my-redelivery.top","title":"Pos Laju | Redelivery","country":"SG","server":"nginx"},'
    '"verdicts":{"overall":{"score":100,"malicious":true,"brands":[{"name":"Pos Malaysia"}]},"urlscan":{"score":100,"brands":[]}}}';
const _phishHtml = '''<!doctype html><html><head><title>Pos Laju Malaysia | Redelivery</title></head>
<body><img src="/img/poslaju-logo.png" alt="Pos Laju"><h1>Pay RM2.50 to redeliver your parcel</h1>
<form action="https://collect.badhost.ru/p.php" method="post">
<input type="text" name="card_number" autocomplete="cc-number"><input type="text" name="cvv">
<input type="password" name="pin"><button>Log in to pay</button></form></body></html>''';
const _desktopHtml = '<html><head><title>Under construction</title></head><body>Coming soon</body></html>';

MockClient _mock({bool cloak = true, List<String>? calls}) => MockClient((req) async {
      calls?.add('${req.method} ${req.url.host}${req.url.path}');
      final u = req.url;
      final ua = req.headers['User-Agent'] ?? '';
      switch (u.host) {
        case 'bit.ly':
          return http.Response('', 301, headers: {'location': 'https://poslaju-my-redelivery.top/pay'});
        case 'poslaju-my-redelivery.top':
          final desktop = ua.contains('Windows');
          return http.Response(cloak && desktop ? _desktopHtml : _phishHtml, 200, headers: {'content-type': 'text/html; charset=utf-8'});
        case 'rdap.org':
          return u.path.startsWith('/ip/') ? http.Response(_rdapIp, 200) : http.Response(_rdapDomain, 200);
        case 'dns.google':
          return http.Response(_doh, 200);
        case 'ipwho.is':
          return http.Response(_ipWhoIs, 200);
        case 'safebrowsing.googleapis.com':
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final entries = body['threatInfo']['threatEntries'] as List;
          return http.Response(entries.any((e) => '${e['url']}'.contains('poslaju-my-redelivery')) ? _gsbHit : '{}', 200);
        case 'www.virustotal.com':
          return u.path.endsWith(virusTotalUrlId('https://poslaju-my-redelivery.top/pay'))
              ? http.Response(_vtHit, 200)
              : http.Response('{"error":{"code":"NotFoundError"}}', 404);
        case 'urlhaus-api.abuse.ch':
          return http.Response(u.path.contains('/host/') ? _urlhausHost : _urlhausNone, 200);
        case 'urlscan.io':
          if (u.path == '/api/v1/scan/') return http.Response(_urlscanSubmit, 200);
          if (u.path.startsWith('/api/v1/result/')) return http.Response(_urlscanResult, 200);
          if (u.path.startsWith('/screenshots/')) return http.Response.bytes([137, 80, 78, 71, 13, 10, 26, 10], 200, headers: {'content-type': 'image/png'});
      }
      return http.Response('not found', 404);
    });

const _keys = ForensicKeys(safeBrowsing: 'sb', virusTotal: 'vt', abuseCh: 'ah', urlscan: 'us');

void main() {
  group('existing verdicts still hold', () {
    test('genuine TAC message is safe', () async {
      final r = await investigate(
          'RM0 Maybank: Your TAC for Third Party Transfer of RM50.00 to account ending 1234 is 482913. Valid for 3 minutes. Do not share TAC with anyone.',
          options: offline);
      expect(r.verdict.level, RiskLevel.safe, reason: '${r.verdict.score} ${r.findings.map((f) => f.title)}');
    });

    test('parcel fee scam is danger', () async {
      final r = await investigate(
          'POS MALAYSIA: Your parcel is held due to unpaid fee RM2.50. Pay within 24 hours or it will be returned: https://poslaju-my-redelivery.top/pay',
          options: offline);
      expect(r.verdict.level, RiskLevel.danger, reason: '${r.verdict.score}');
      expect(r.script?.script, 'parcel scam');
    });
  });

  group('look-alike letters and l33t spelling', () {
    test('folding keeps positions', () {
      expect(foldConfusables('Маybаnk'), 'maybank'); // Cyrillic М and а
      expect(foldConfusables('ΡDRM'), 'pdrm'); // Greek Ρ
      expect(foldConfusables('ｍａｙｂａｎｋ'), 'maybank'); // full width
      expect(foldConfusables('c1mb', oneAsI: true), 'cimb');
      expect(foldConfusables('Маybаnk').length, 'Маybаnk'.length);
    });

    test('disguised brand names in text', () {
      final f = disguisedWordFindings('Your M4yb4nk account is frozen. Contact P0s L4ju or c1mb now.');
      final titles = f.map((x) => x.explanation).join(' | ');
      expect(f.where((x) => x.title == 'Disguised brand name').length, 3, reason: titles);
      expect(titles, contains('Maybank'));
      expect(titles, contains('Pos Malaysia'));
      expect(titles, contains('CIMB'));
    });

    test('normal words, amounts and the real brand spelling are not flagged', () {
      expect(findDisguisedWords('Maybank2u: RM50.00 paid on 12/10. Ref 482913. Call 1300886688'), isEmpty);
      expect(findDisguisedWords('See you at 7pm at Pavilion, bring 2 friends'), isEmpty);
    });

    test('disguised keywords are re-read by the cue rules', () async {
      final r = await investigate('Pls send me the 0TP you received, urgent', options: offline);
      expect(r.findings.any((f) => f.tool == 'Obfuscation check' && f.title == 'Disguised spelling'), isTrue);
    });

    test('l33t and Cyrillic domains are caught as brand imitation', () async {
      final a = await investigate('Login here http://c1mb-secure-verify.xyz/login', options: offline);
      expect(a.urls.single.imitates, 'CIMB');
      final b = await investigate('Login here http://m4yb4nk-update.com', options: offline);
      expect(b.urls.single.imitates, 'Maybank');
      final c = await investigate('Login here https://xn--mybank-3ve.com', options: offline); // mаybank with Cyrillic а
      expect(c.urls.single.imitates, isNotNull);
    });
  });

  group('scam-script stages', () {
    test('job task scam at the prepaid merchant task step', () {
      final r = detectScriptStage(
          'Hi, we are hiring part time staff, earn RM300 daily. Simple task: like and follow our page and send screenshot. '
          'Join our Telegram group, the receptionist will guide you. Today is a merchant task, top up RM500 for the task first.');
      expect(r, isNotNull);
      expect(r!.$1.script, 'job task scam');
      expect(r.$1.stage, 3);
      expect(r.$2.title, 'Matches step 4 of 5 of a job task scam');
    });

    test('fake officer scam reaches the safe account step', () {
      final r = detectScriptStage(
          'This is Pos Laju. Your IC was used to send a parcel with drugs. I will transfer this call to Inspector Lim. '
          'Do not tell anyone. Move your savings to a safe account for checking.');
      expect(r!.$1.script, 'fake officer scam');
      expect(r.$1.stage, 4);
    });

    test('love and investment scripts', () {
      expect(detectScriptStage('Sorry wrong number. You seem nice. Good night my dear')!.$1.script, 'love scam');
      expect(
          detectScriptStage('My uncle is an analyst. Guaranteed 30% profit monthly. Register on the trading platform and deposit RM1000')!.$1.script,
          'investment scam');
    });

    test('an ordinary message has no script', () {
      expect(detectScriptStage('Your parcel has been delivered. Thank you for shopping with us.'), isNull);
      expect(detectScriptStage('Hey are we still on for dinner at 7?'), isNull);
    });
  });

  group('mixed languages', () {
    test('detects languages and Chinese scam phrases', () {
      final s = scanLanguages('Hello 你好, akaun anda kena freeze. 请提供验证码 sekarang juga');
      expect(s.languages, containsAll(['English', 'Malay', 'Chinese']));
      expect(s.findings.map((f) => f.title), containsAll(['Asks for secret codes', 'Threat or penalty', 'Rushes you']));
    });

    test('a Chinese police scam scores as a scam', () async {
      final r = await investigate('我是警察，你的户口涉及洗钱，马上转账到安全户口', options: offline);
      expect(r.verdict.level.index, greaterThanOrEqualTo(RiskLevel.suspicious.index), reason: '${r.verdict.score}');
    });
  });

  group('legitimacy', () {
    test('official sender plus bank alert template looks legitimate', () async {
      final r = await investigate(
          'RM0 Maybank: Debit of RM120.50 from your account ending 1234 at TESCO on 12/10/26 14:32. If this was not you, call 1300886688.',
          sender: 'Maybank',
          options: offline);
      expect(r.verdict.level, RiskLevel.safe, reason: '${r.verdict.score} ${r.findings.map((f) => f.title)}');
      expect(r.verdict.headline, startsWith('Looks legitimate'));
      expect(r.findings.map((f) => f.title), containsAll(['Standard bank transaction alert', "Sent from Maybank's official sender name"]));
      expect(r.verdict.scamType, 'Legitimate message');
    });

    test('genuine delivery SMS', () async {
      final r = await investigate('Pos Laju: Your item EN123456789MY is out for delivery today. Track it in the official Pos Malaysia app.',
          options: offline);
      expect(r.findings.any((f) => f.title == 'Standard delivery update'), isTrue);
      expect(r.verdict.level, RiskLevel.safe);
    });

    test('hotline numbers match, and templates never vouch for a scam', () {
      expect(matchSender('+60 3-6204 7788')?.$1.brand, 'CIMB');
      final f = legitimacyFindings('Pos Laju: your parcel is out for delivery. Pay RM2 fee at http://x.top',
          sender: 'Pos Laju',
          urls: const [UrlReport(input: 'http://x.top', finalUrl: 'http://x.top', host: 'x.top', hops: [])],
          prior: const []);
      expect(f, isEmpty);
    });
  });

  group('landing page and cloaking', () {
    test('fake brand page asking for card and PIN', () {
      final r = analyzeLandingHtml(_phishHtml, Uri.parse('https://poslaju-my-redelivery.top/pay'));
      expect(r.title, 'Pos Laju Malaysia | Redelivery');
      expect(r.asksPassword && r.asksCard, isTrue);
      expect(r.brandsSeen, contains('Pos Malaysia'));
      expect(r.offsiteForms, ['collect.badhost.ru']);
      expect(r.findings.map((f) => f.title), contains('Asks for your password, one-time code and card details on a fake Pos Malaysia site'));
      expect(r.findings.map((f) => f.title), contains('Sends what you type to another website'));
    });

    test('official page is not flagged', () {
      final r = analyzeLandingHtml('<title>Maybank2u</title><input type="password" name="pw">', Uri.parse('https://www.maybank2u.com.my/'));
      expect(r.findings, isEmpty);
    });

    test('meta refresh and script redirects are found', () {
      final a = analyzeLandingHtml('<meta http-equiv="refresh" content="0; url=https://next.example/x">', Uri.parse('https://a.example/'));
      expect(a.hiddenRedirect.toString(), 'https://next.example/x');
      final b = analyzeLandingHtml('<script>window.location.href = "/go?id=1";</script>', Uri.parse('https://a.example/p'));
      expect(b.hiddenRedirect.toString(), 'https://a.example/go?id=1');
      expect(b.hiddenRedirectKind, 'script');
    });

    test('compareViews', () {
      final u = Uri.parse('https://a.example/');
      expect(
          compareViews(mobileStatus: 200, desktopStatus: 200, mobileFinal: u, desktopFinal: u, mobileTitle: 'A', desktopTitle: 'A', mobileBytes: 9000, desktopBytes: 9100),
          isNull);
      expect(
          compareViews(mobileStatus: 200, desktopStatus: 404, mobileFinal: u, desktopFinal: u, mobileTitle: 'Bank login', desktopTitle: null, mobileBytes: 20000, desktopBytes: 100)!
              .title,
          'Shows different pages to different visitors');
    });

    test('isolated fetch stops reading at the size cap and skips files', () async {
      final big = MockClient.streaming((req, _) async => http.StreamedResponse(
          Stream.fromIterable(List.generate(40, (_) => List.filled(64 * 1024, 65))), 200,
          headers: {'content-type': 'text/html'}));
      final p = await fetchIsolated(Uri.parse('https://a.example/'), client: big);
      expect(p.bytes, maxPageBytes);
      expect(p.truncated, isTrue);
      final apk = MockClient((req) async => http.Response('PK...', 200, headers: {'content-type': 'application/vnd.android.package-archive'}));
      final q = await fetchIsolated(Uri.parse('https://a.example/app.apk'), client: apk);
      expect(q.html, isNull);
    });
  });

  group('service response parsing', () {
    test('DNS, RDAP and ipwho.is', () {
      expect(parseDohAnswer(_doh), ['203.0.113.7']);
      expect(parseIpRdap(_rdapIp), ('Example Cloud Hosting Pte Ltd (CLOUDNET-SG)', 'SG'));
      expect(parseIpWhoIs(_ipWhoIs), ('Example Cloud (AS64500)', 'SG'));
      expect(flagFor('MY'), '🇲🇾');
    });

    test('reputation services', () {
      expect(parseSafeBrowsing(_gsbHit), {'SOCIAL_ENGINEERING'});
      expect(parseSafeBrowsing('{}'), isEmpty);
      expect(virusTotalUrlId('http://www.example.com/'), 'aHR0cDovL3d3dy5leGFtcGxlLmNvbS8');
      expect(parseVirusTotal(_vtHit), (6, 1, 58));
      expect(parseUrlhaus(_urlhausNone).$1, isFalse);
      expect(parseUrlhaus(_urlhausHost).$1, isTrue);
      final r = parseUrlscanResult(_uuid, _urlscanResult);
      expect(r.malicious, isTrue);
      expect(r.brands, ['Pos Malaysia']);
      expect(r.title, 'Pos Laju | Redelivery');
      expect(r.screenshotUrl, 'https://urlscan.io/screenshots/$_uuid.png');
      expect(urlscanSubmission('https://x')['visibility'], 'unlisted');
      expect(urlscanSubmission('https://x')['country'], 'my');
    });

    test('certificate issuer', () {
      final t = TlsInfo(
          issuer: '/C=US/O=Let\'s Encrypt/CN=R11', subject: '/CN=x', validFrom: DateTime.now(), validTo: DateTime.now(), trusted: true);
      expect(t.issuerName, "Let's Encrypt");
      expect(t.freeIssuer, isTrue);
    });

    test('vision answer becomes a finding only for a non-official host', () {
      final j = {'imitates': true, 'brand': 'Maybank', 'kind': 'bank', 'login_form': true, 'reason': 'Copies the M2U login'};
      expect(visionFinding(j, 'maybank-secure.xyz')!.title, 'Page looks like Maybank');
      expect(visionFinding(j, 'www.maybank2u.com.my'), isNull);
      expect(visionFinding({'imitates': false}, 'x.com'), isNull);
    });
  });

  group('deep link check with recorded responses', () {
    test('every online step runs, is logged and finds the scam', () async {
      final log = <LogStep>[];
      final calls = <String>[];
      LogStep step(String tool, String action, {bool sentOffDevice = false}) {
        final s = _log(tool, action, sentOffDevice: sentOffDevice);
        log.add(s);
        return s;
      }

      final base = UrlReport(
        input: 'https://bit.ly/3abcde',
        finalUrl: 'https://poslaju-my-redelivery.top/pay',
        host: 'poslaju-my-redelivery.top',
        hops: const [UrlHop('https://bit.ly/3abcde', 301), UrlHop('https://poslaju-my-redelivery.top/pay', 200)],
        imitates: 'Pos Malaysia',
      );
      final r = await deepLinkCheck(base,
          log: step,
          client: _mock(calls: calls),
          keys: _keys,
          probeCertificates: false,
          urlscanFirstWait: Duration.zero,
          urlscanWait: const Duration(seconds: 2));
      final titles = r.findings.map((f) => f.title).toSet();
      expect(titles, containsAll([
        'Flagged by Google Safe Browsing',
        'Flagged by VirusTotal',
        'Flagged by URLhaus',
        'Flagged by urlscan.io',
        'Shows different pages to different visitors',
        'Sends what you type to another website',
      ]), reason: '$titles');
      expect(titles.any((t) => t.contains('fake Pos Malaysia site')), isTrue);
      final hop = r.report.hops.last;
      expect(hop.country, 'SG');
      expect(hop.ip, '203.0.113.7');
      expect(hop.network, contains('Example Cloud Hosting'));
      expect(r.report.screenshotUrl, contains(_uuid));
      expect(r.report.cloaked, isTrue);
      expect(r.report.pageTitle, 'Pos Laju Malaysia | Redelivery');
      // Every online step is marked as leaving the device.
      for (final s in log.where((s) => s.tool != 'AI screenshot reader')) {
        expect(s.sentOffDevice, isTrue, reason: s.tool);
      }
      expect(log.any((s) => s.result.contains('isolated reader')), isTrue);
      // Only links went to the reputation services, never message text.
      expect(calls.where((c) => c.contains('safebrowsing')).length, greaterThan(0));
    });

    test('missing keys are logged as skipped, failures fail soft', () async {
      final log = <LogStep>[];
      final dead = MockClient((req) async => throw http.ClientException('offline'));
      final r = await deepLinkCheck(
        const UrlReport(input: 'https://a.example', finalUrl: 'https://a.example', host: 'a.example', hops: [UrlHop('https://a.example', null)]),
        log: (tool, action, {sentOffDevice = false}) {
          final s = _log(tool, action, sentOffDevice: sentOffDevice);
          log.add(s);
          return s;
        },
        client: dead,
        keys: ForensicKeys.none,
        probeCertificates: false,
      );
      expect(r.findings, isEmpty);
      expect(log.where((s) => s.status == StepStatus.skipped).map((s) => s.tool),
          containsAll(['Google Safe Browsing', 'VirusTotal', 'URLhaus', 'Remote isolated browser']));
      expect(log.where((s) => s.status == StepStatus.skipped).every((s) => !s.sentOffDevice), isTrue);
      expect(log.any((s) => s.status == StepStatus.running), isFalse);
    });

    test('full investigation through a shortener with the injected client', () async {
      final r = await investigate('Your parcel is held. Pay the fee here: https://bit.ly/3abcde',
          options: InvestigateOptions(llm: const LlmConfig(kind: LlmKind.none), httpClient: _mock(), keys: _keys, quick: true));
      expect(r.verdict.level, RiskLevel.danger);
      expect(r.urls.single.finalUrl, 'https://poslaju-my-redelivery.top/pay');
      expect(r.urls.single.domainAgeDays, lessThan(5));
      expect(r.urls.single.reputationHits, isNotEmpty);
      expect(r.log.any((s) => s.tool == 'Legitimacy check'), isTrue);
      expect(r.log.any((s) => s.tool == 'Cloaking check'), isFalse, reason: 'quick mode skips it');
    });
  });
}
