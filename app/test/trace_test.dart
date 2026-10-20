import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kantoi/engine/attribution/intel_store.dart';
import 'package:kantoi/engine/forensics/tls_info.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/engine/trace/trace_input.dart';
import 'package:kantoi/engine/trace/trace_models.dart';
import 'package:kantoi/engine/trace/trace_pdf.dart';
import 'package:kantoi/engine/trace/tracer.dart';
import 'package:shared_preferences/shared_preferences.dart';

final seed = File('assets/intel_seed.json').readAsStringSync();

String _iso(Duration ago) => DateTime.now().subtract(ago).toUtc().toIso8601String();

/// A small fake internet: a shortener that redirects to a Maybank look-alike.
http.Response _web(http.Request r) {
  final u = r.url;
  if (u.host == 'bit.ly') return http.Response('', 301, headers: {'location': 'https://login.maybank2u-secure.top/verify'});
  if (u.host == 'login.maybank2u-secure.top') return http.Response('<html></html>', 200, headers: {'content-type': 'text/html'});
  if (u.host == 'rdap.org' && u.path == '/domain/maybank2u-secure.top') {
    return http.Response(
        jsonEncode({
          'events': [
            {'eventAction': 'registration', 'eventDate': _iso(const Duration(days: 3))}
          ],
          'entities': [
            {
              'roles': ['registrar'],
              'vcardArray': [
                'vcard',
                [
                  ['fn', {}, 'text', 'NameCheap, Inc.']
                ]
              ]
            }
          ],
          'nameservers': [
            {'ldhName': 'dns1.registrar-servers.com'}
          ],
        }),
        200);
  }
  if (u.host == 'dns.google') {
    final type = u.queryParameters['type'];
    final answer = switch (type) {
      'A' => [
          {'type': 1, 'data': '203.0.113.9'}
        ],
      'NS' => [
          {'type': 2, 'data': 'dns2.registrar-servers.com.'}
        ],
      'MX' => [
          {'type': 15, 'data': '10 mx.maybank2u-secure.top.'}
        ],
      _ => <Map<String, Object>>[],
    };
    return http.Response(jsonEncode({'Status': 0, 'Answer': answer}), 200);
  }
  if (u.host == 'ipwho.is') {
    return http.Response(
        jsonEncode({
          'success': true,
          'country_code': 'NL',
          'connection': {'org': 'Example Hosting BV', 'asn': 64500}
        }),
        200);
  }
  if (u.host == 'crt.sh') {
    return http.Response(
        jsonEncode([
          {'not_before': _iso(const Duration(days: 2)), 'name_value': 'login.maybank2u-secure.top\ncimbclicks-verify.top', 'common_name': 'login.maybank2u-secure.top'},
          {'not_before': _iso(const Duration(days: 1)), 'name_value': 'pay.maybank2u-secure.top', 'common_name': 'pay.maybank2u-secure.top'},
        ]),
        200);
  }
  return http.Response('not found', 404);
}

Future<TraceState> _trace(String input, {required http.Client client, Tracer? tracer, IntelService? intel}) async {
  final t = tracer ??
      Tracer(
        client: client,
        graph: intel?.graph,
        tlsProbe: (host) async => TlsInfo(
            issuer: "C=US, O=Let's Encrypt, CN=R11",
            subject: 'CN=$host',
            validFrom: DateTime.now().subtract(const Duration(days: 1)),
            validTo: DateTime.now().add(const Duration(days: 89)),
            trusted: true),
      );
  final s = TraceState();
  await t.run(input).forEach(s.apply);
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('input', () {
    test('recognises links, numbers, accounts, emails and messages', () {
      expect(parseTraceInput('bit.ly/abc').seeds.single.kind, SeedKind.url);
      expect(parseTraceInput('012-345 6789').seeds.single.kind, SeedKind.phone);
      expect(parseTraceInput('+855 12 345 678').seeds.single.kind, SeedKind.phone);
      expect(parseTraceInput('5140 1234 9821').seeds.single.kind, SeedKind.account);
      expect(parseTraceInput('help@maybank-care.com').seeds.single.kind, SeedKind.email);
      final m = parseTraceInput('Your parcel is held. Pay at https://poslaju-fee.top/pay or call 011-2004 7731');
      expect(m.message, isTrue);
      expect(m.seeds.map((s) => s.kind), containsAll([SeedKind.url, SeedKind.phone]));
    });

    test('reads phone numbers by format only', () {
      final my = analyzePhone('012-345 6789');
      expect(my.country, 'MY');
      expect(my.lineType, 'Mobile number');
      expect(analyzePhone('015-4600 1234').lineType, startsWith('Internet phone'));
      expect(analyzePhone('03-2123 4567').area, contains('Kuala Lumpur'));
      expect(analyzePhone('+855 12 345 678').country, 'KH');
      expect(analyzeAccount('514012349821').banksByLength, contains('Maybank'));
      expect(analyzeAccount('1111111111').oddities, isNotEmpty);
    });
  });

  group('tracer', () {
    test('builds the map from redirects, RDAP, DNS, IP owner, certificate and CT logs', () async {
      final s = await _trace('https://bit.ly/abc', client: MockClient((r) async => _web(r)));
      expect(s.finished, isTrue);
      expect(s.originId, 'url:https://bit.ly/abc');
      final kinds = s.nodes.values.map((n) => n.kind).toSet();
      expect(kinds, containsAll([TraceKind.url, TraceKind.domain, TraceKind.ip, TraceKind.hosting, TraceKind.country, TraceKind.cert, TraceKind.nameserver, TraceKind.mail, TraceKind.subdomain, TraceKind.sibling, TraceKind.brand]));
      expect(s.countries, {'NL'});
      final dom = s.nodes['domain:maybank2u-secure.top']!;
      expect(dom.facts.map((f) => f.$1), containsAll(['Registered', 'Registrar']));
      expect(dom.flagged, isTrue);
      expect(s.nodes['hosting:example hosting bv (as64500)']?.label, 'Example Hosting BV (AS64500)');
      expect(s.flags.map((f) => f.title), containsAll(['Brand-new website', 'Pretends to be Maybank', 'Brand-new certificate']));
      expect(s.flags.map((f) => f.title), contains(startsWith('Shares a certificate with a CIMB')));
      expect(s.level, RiskLevel.danger);
      // Every edge joins two real nodes, and the log says what went online.
      for (final e in s.edges.values) {
        expect(s.nodes.containsKey(e.from) && s.nodes.containsKey(e.to), isTrue, reason: e.key);
      }
      expect(s.lookups.where((l) => l.online).map((l) => l.step.tool), containsAll(['Redirect follower', 'Domain registry (RDAP)', 'DNS (dns.google)', 'IP owner (ipwho.is)', 'Certificate logs (crt.sh)', 'TLS certificate']));
      expect(s.lookups.firstWhere((l) => l.step.tool == 'Look-alike check').online, isFalse);
      expect(s.lookups.any((l) => l.alarming), isTrue);
      expect(s.progress, 1);
    });

    test('finishes offline with what it found on the phone', () async {
      final client = MockClient((r) async => throw const SocketException('offline'));
      final s = await _trace('https://maybank2u-secure.top/login', client: client, tracer: Tracer(client: client));
      expect(s.finished, isTrue);
      expect(s.nodes.keys, contains('brand:Maybank'));
      expect(s.lookups.where((l) => l.online).every((l) => l.step.status == StepStatus.failed), isTrue);
      expect(s.lookups.every((l) => l.step.status != StepStatus.running), isTrue);
    });

    test('a lookup that hangs times out and the trace still ends', () async {
      final never = Completer<http.StreamedResponse>();
      final client = _HangingClient(never.future);
      final t = Tracer(client: client, timeout: const Duration(milliseconds: 40), slowTimeout: const Duration(milliseconds: 60));
      final s = await _trace('example-shop.top', client: client, tracer: t).timeout(const Duration(seconds: 5));
      expect(s.finished, isTrue);
      expect(s.lookups.where((l) => l.step.result.startsWith('No answer')), isNotEmpty);
    });

    test('phone numbers: country, line type, scam map match and Semak Mule note', () async {
      final intel = IntelService(seedJson: seed, persist: false);
      await intel.ensureLoaded();
      final s = await _trace('+60 11-2004 7731', client: MockClient((r) async => http.Response('', 404)), intel: intel);
      final phone = s.nodes['phone:601120047731']!;
      expect(phone.facts.map((f) => f.$1), contains('Line type'));
      expect(s.countries, {'MY'});
      final related = s.nodes.values.where((n) => n.kind == TraceKind.related).toList();
      expect(related, isNotEmpty);
      expect(related.every((n) => n.demo), isTrue, reason: 'seeded matches must be labelled demo');
      expect(s.lookups.any((l) => l.step.tool == 'Semak Mule (PDRM)' && l.step.status == StepStatus.skipped), isTrue);
      expect(s.lookups.where((l) => l.online), isEmpty, reason: 'phone checks stay on the phone');
    });

    test('a known demo domain links to its campaign and siblings', () async {
      final intel = IntelService(seedJson: seed, persist: false);
      await intel.ensureLoaded();
      final s = await _trace('poslaju-my-redelivery.top', client: MockClient((r) async => throw const SocketException('offline')), intel: intel);
      expect(s.nodes.values.where((n) => n.kind == TraceKind.related && n.demo), isNotEmpty);
      expect(s.hasDemo, isTrue);
    });

    test('messages: entities are extracted and each is traced', () async {
      final s = await _trace('Akaun anda dibekukan. Hubungi 011-2004 7731 atau bayar ke 5140 1234 9821 di Maybank segera.',
          client: MockClient((r) async => http.Response('', 404)));
      expect(s.nodes[s.originId]!.kind, TraceKind.message);
      expect(s.nodes.values.map((n) => n.kind), containsAll([TraceKind.phone]));
    });

    test('pause holds the next lookup until resume', () async {
      final t = Tracer(client: MockClient((r) async => http.Response('', 404)));
      final s = TraceState();
      t.pause();
      final done = t.run('012-345 6789').forEach(s.apply);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(s.lookups, isEmpty);
      t.resume();
      await done;
      expect(s.finished, isTrue);
      expect(s.lookups, isNotEmpty);
    });

    test('caps the map at the node limit', () async {
      final t = Tracer(client: MockClient((r) async => _web(r)), maxNodes: 6);
      final s = await _trace('https://bit.ly/abc', client: MockClient((r) async => _web(r)), tracer: t);
      expect(s.nodes.length, lessThanOrEqualTo(6));
      expect(s.lookups.any((l) => l.step.tool == 'Map'), isTrue);
    });

    test('CT parser splits sub-domains from other websites', () {
      final c = parseCtNames(jsonEncode([
        {'not_before': '2026-10-01T00:00:00', 'name_value': '*.a.top\nwww.a.top\nb-maybank.top'}
      ]), 'a.top');
      expect(c.subdomains, ['www.a.top']);
      expect(c.siblings, ['b-maybank.top']);
      expect(c.first, DateTime(2026, 10, 1));
    });

    test('police report PDF and text summary', () async {
      final s = await _trace('https://bit.ly/abc', client: MockClient((r) async => _web(r)));
      final text = traceSummaryText(s);
      expect(text, contains('maybank2u-secure.top'));
      expect(text, contains('Brand-new website'));
      final pdf = await buildTracePdf(s, now: DateTime(2026, 10, 20));
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    });
  });
}

class _HangingClient extends http.BaseClient {
  final Future<http.StreamedResponse> never;
  _HangingClient(this.never);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => never;
}
