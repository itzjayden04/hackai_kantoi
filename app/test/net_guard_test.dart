import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kantoi/engine/forensics/net_guard.dart';
import 'package:kantoi/engine/forensics/safe_fetch.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/engine/url_analyzer.dart';

LogStep _log(String tool, String action, {bool sentOffDevice = false}) => LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice);

void main() {
  tearDown(() => debugResolveHost = null);

  group('addresses', () {
    test('every way of writing an address is understood', () {
      expect(literalAddress('127.0.0.1'), [127, 0, 0, 1]);
      expect(literalAddress('2130706433'), [127, 0, 0, 1]);
      expect(literalAddress('0x7f.1'), [127, 0, 0, 1]);
      expect(literalAddress('0177.0.0.1'), [127, 0, 0, 1]);
      expect(literalAddress('192.168.257'), [192, 168, 1, 1]);
      expect(literalAddress('[::1]'), [...List.filled(15, 0), 1]);
      expect(literalAddress('example.com'), isNull);
      expect(literalAddress('163.com'), isNull);
      expect(literalAddress('999.1.1.1'), isNull);
    });

    test('private, local and carrier addresses are not public', () {
      for (final a in ['10.1.2.3', '172.16.0.1', '172.31.255.255', '192.168.1.1', '127.0.0.1', '0.0.0.0', '169.254.169.254', '100.64.0.1', '224.0.0.1']) {
        expect(nonPublicReason(literalAddress(a)!), isNotNull, reason: a);
      }
      for (final a in ['::1', 'fc00::1', 'fd12:3456::1', 'fe80::1', '::ffff:192.168.0.1', '64:ff9b::a00:1', '2002:c0a8:101::1']) {
        expect(nonPublicReason(literalAddress(a)!), isNotNull, reason: a);
      }
      for (final a in ['8.8.8.8', '172.32.0.1', '100.128.0.1', '203.0.113.7', '2001:4860:4860::8888', '::ffff:8.8.8.8', '64:ff9b::808:808']) {
        expect(nonPublicReason(literalAddress(a)!), isNull, reason: a);
      }
      expect(formatAddress(literalAddress('::1')!), '::1');
      expect(formatAddress([192, 168, 1, 1]), '192.168.1.1');
    });

    test('names that only exist inside a network', () {
      for (final h in ['localhost', 'router', 'printer.local', 'nas.lan', 'intranet.corp', 'x.home.arpa', '192.168.0.1', '[::1]', '0x7f.1']) {
        expect(() => checkHostName(h), throwsA(isA<BlockedAddress>()), reason: h);
      }
      for (final h in ['example.com', 'poslaju-my-redelivery.top', '8.8.8.8', 'WWW.Maybank2u.com.my.']) {
        expect(() => checkHostName(h), returnsNormally, reason: h);
      }
    });

    test('a public name that resolves to a private address is stopped', () async {
      debugResolveHost = (h) async => h == 'evil.example' ? [[10, 0, 0, 5]] : [[93, 184, 216, 34]];
      await expectLater(ensurePublicHost(Uri.parse('https://evil.example/x')), throwsA(isA<BlockedAddress>()));
      await expectLater(ensurePublicHost(Uri.parse('https://fine.example/x')), completes);
      // A name that cannot be resolved is left to fail on its own.
      debugResolveHost = (h) async => throw Exception('no DNS');
      await expectLater(ensurePublicHost(Uri.parse('https://gone.example/')), completes);
    });
  });

  group('link checks never reach the local network', () {
    test('the isolated reader refuses a private link and a redirect into one', () async {
      final asked = <String>[];
      final client = MockClient((req) async {
        asked.add(req.url.toString());
        if (req.url.host == 'short.example') return http.Response('', 302, headers: {'location': 'http://192.168.1.1/admin'});
        return http.Response('<html></html>', 200, headers: {'content-type': 'text/html'});
      });
      await expectLater(fetchIsolated(Uri.parse('http://192.168.1.1/'), client: client), throwsA(isA<BlockedAddress>()));
      expect(asked, isEmpty);
      await expectLater(fetchIsolated(Uri.parse('https://short.example/a'), client: client), throwsA(isA<BlockedAddress>()));
      expect(asked, ['https://short.example/a']);
    });

    test('the redirect follower stops at the last public hop and says why', () async {
      final asked = <String>[];
      final client = MockClient((req) async {
        asked.add(req.url.toString());
        if (req.url.host == 'bit.ly') return http.Response('', 301, headers: {'location': 'http://127.0.0.1:8080/'});
        return http.Response('not found', 404);
      });
      final log = <LogStep>[];
      final a = await analyzeUrl('https://bit.ly/abc', client: client, log: (tool, action, {sentOffDevice = false}) {
        final s = _log(tool, action, sentOffDevice: sentOffDevice);
        log.add(s);
        return s;
      });
      expect(asked.where((u) => u.contains('127.0.0.1')), isEmpty);
      expect(a.report.finalUrl, 'https://bit.ly/abc');
      expect(a.findings.map((f) => f.title), contains('Points into your own network'));
      final follower = log.firstWhere((s) => s.tool == 'Redirect follower');
      expect(follower.result, startsWith('Stopped:'));
      expect(follower.status, StepStatus.done);
    });
  });
}
