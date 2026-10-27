import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kantoi/engine/forensics/keys.dart';
import 'package:kantoi/engine/forensics/reputation.dart';
import 'package:kantoi/engine/models.dart';

const _scam = 'https://poslaju-my-redelivery.top/pay';
final _analysed = DateTime.now().toUtc().subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000;

String _urlObject({int bad = 0, int sus = 0, int clean = 60, int? analysed, Map<String, String> flagged = const {}}) => jsonEncode({
      'data': {
        'id': 'x',
        'type': 'url',
        'attributes': {
          'last_analysis_stats': {'malicious': bad, 'suspicious': sus, 'harmless': clean, 'undetected': 10, 'timeout': 0},
          'last_analysis_results': {
            for (final e in flagged.entries) e.key: {'engine_name': e.key, 'category': 'malicious', 'result': e.value},
            'CleanEngine': {'engine_name': 'CleanEngine', 'category': 'harmless', 'result': 'clean'},
          },
          'last_analysis_date': analysed ?? _analysed,
          'first_submission_date': _analysed,
          'last_final_url': '$_scam/login',
          'title': 'Pos Laju | Redelivery',
          'total_votes': {'harmless': 0, 'malicious': 1},
        },
      },
    });

String _analysis(String status, {int bad = 0}) => jsonEncode({
      'data': {
        'id': 'u-abc-1',
        'type': 'analysis',
        'attributes': {
          'status': status,
          'date': _analysed,
          'stats': {'malicious': bad, 'suspicious': 0, 'harmless': 50, 'undetected': 20, 'timeout': 0},
          'results': {
            for (var i = 0; i < bad; i++) 'Engine$i': {'engine_name': 'Engine$i', 'category': 'malicious', 'result': 'phishing'},
          },
        },
      },
    });

String _domain({int bad = 0, Map<String, String> categories = const {}}) => jsonEncode({
      'data': {
        'id': 'poslaju-my-redelivery.top',
        'type': 'domain',
        'attributes': {
          'last_analysis_stats': {'malicious': bad, 'suspicious': 0, 'harmless': 60, 'undetected': 20, 'timeout': 0},
          'last_analysis_results': {
            for (var i = 0; i < bad; i++) 'Vendor$i': {'engine_name': 'Vendor$i', 'category': 'malicious', 'result': 'phishing'},
          },
          'categories': categories,
          'creation_date': DateTime.now().toUtc().subtract(const Duration(days: 3)).millisecondsSinceEpoch ~/ 1000,
        },
      },
    });

class _Fake {
  final List<String> calls = [];
  final List<String> submitted = [];
  String? url;
  String? analysis;
  String? domain;
  int status = 200;

  http.Client get client => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (status != 200) return http.Response('{"error":{"code":"QuotaExceededError"}}', status);
        final p = req.url.path;
        if (req.method == 'POST' && p == '/api/v3/urls') {
          submitted.add(Uri.splitQueryString(req.body)['url'] ?? '');
          return http.Response('{"data":{"type":"analysis","id":"u-abc-1"}}', 200);
        }
        if (p.startsWith('/api/v3/urls/')) return url == null ? http.Response('{"error":{"code":"NotFoundError"}}', 404) : http.Response(url!, 200);
        if (p.startsWith('/api/v3/analyses/')) return http.Response(analysis ?? _analysis('queued'), 200);
        if (p.startsWith('/api/v3/domains/') || p.startsWith('/api/v3/ip_addresses/')) {
          return domain == null ? http.Response('{"error":{"code":"NotFoundError"}}', 404) : http.Response(domain!, 200);
        }
        return http.Response('not found', 404);
      });
}

void main() {
  late List<LogStep> log;
  LogStep step(String tool, String action, {bool sentOffDevice = false}) {
    final s = LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice);
    log.add(s);
    return s;
  }

  setUp(() => log = []);

  Future<List<ReputationHit>> run(_Fake f,
          {String url = _scam, VtDepth depth = VtDepth.full, bool quick = false, VtLimiter? limiter, VtCache? cache}) =>
      checkVirusTotal(url,
          apiKey: 'vt',
          client: f.client,
          log: step,
          depth: depth,
          quick: quick,
          limiter: limiter ?? VtLimiter.unlimited(),
          cache: cache ?? VtCache(enabled: false),
          pollDelays: const [Duration.zero, Duration.zero]);

  group('parsing', () {
    test('a flagged link names the companies and the threat', () {
      final v = parseVtObject(_urlObject(bad: 5, flagged: {
        'Fortinet': 'phishing',
        'Kaspersky': 'phishing',
        'BitDefender': 'phishing',
        'Sophos': 'malicious',
        'ESET': 'phishing',
      }))!;
      expect(v.malicious, 5);
      expect(v.threat, 'phishing');
      expect(v.vendorList(), 'Fortinet, Kaspersky, BitDefender and 2 more');
      expect(v.finalUrl, '$_scam/login');
      expect(v.title, 'Pos Laju | Redelivery');
      expect(v.staleAt(DateTime.now()), isFalse);
      expect(parseVirusTotal(_urlObject(bad: 6, sus: 1, clean: 58)), (6, 1, 58));
      expect(describeVt(v), allOf(contains('5 malicious'), contains('flagged as phishing by Fortinet'), contains('last scanned 2 days ago')));
    });

    test('scans, submissions and websites', () {
      expect(parseVtAnalysis(_analysis('queued')), isNull);
      expect(parseVtAnalysis(_analysis('completed', bad: 3))!.malicious, 3);
      expect(parseVtSubmission('{"data":{"type":"analysis","id":"u-abc-1"}}'), 'u-abc-1');
      expect(parseVtSubmission('{}'), isNull);
      final d = parseVtObject(_domain(categories: {'Forcepoint ThreatSeeker': 'phishing and other frauds', 'Sophos': 'shopping'}))!;
      expect(d.badCategories, ['phishing and other frauds']);
      expect(d.registered, isNotNull);
      expect(parseVtObject('{"data":{"attributes":{}}}'), isNull);
    });

    test('hits and their weights', () {
      expect(linkHit(parseVtObject(_urlObject())!), isNull);
      expect(linkHit(parseVtObject(_urlObject(bad: 1))!)!.weight, 14);
      expect(linkHit(parseVtObject(_urlObject(bad: 3))!)!.weight, 24);
      expect(linkHit(parseVtObject(_urlObject(bad: 7))!)!.weight, 30);
      expect(linkHit(parseVtObject(_urlObject(sus: 2))!)!.weight, 6);
      expect(linkHit(parseVtAnalysis(_analysis('completed', bad: 3))!, fresh: true)!.summary, startsWith('In a fresh scan just now'));
      final site = websiteHit(parseVtObject(_domain(bad: 4))!, 'x.top', linkKnown: false)!;
      expect(site.service, vtWebsiteService);
      expect(site.weight, 20);
      expect(site.summary, contains('new to VirusTotal'));
      expect(websiteHit(parseVtObject(_domain(categories: {'Sophos': 'phishing'}))!, 'x.top', linkKnown: true)!.weight, 10);
      expect(websiteHit(parseVtObject(_domain())!, 'x.top', linkKnown: true), isNull);
    });
  });

  group('personal details never go into a scan', () {
    test('phone numbers, emails and IC numbers are removed', () {
      expect(shareableUrl('https://a.top/pay?ref=abc'), ('https://a.top/pay?ref=abc', false));
      final (u1, s1) = shareableUrl('https://a.top/pay?phone=0123456789&x=1');
      expect((u1, s1), ('https://a.top/pay', true));
      expect(shareableUrl('https://a.top/u/ali%40gmail.com').$1, 'https://a.top/');
      expect(shareableUrl('https://user:pw@a.top/pay').$1, 'https://a.top/pay');
      expect(shareableUrl('https://a.top/claim#ic=900101-14-5678').$1, 'https://a.top/claim');
    });
  });

  group('rate limit', () {
    test('4 a minute, then a pause after VirusTotal says no', () async {
      var t = DateTime(2026, 10, 27, 12);
      final l = VtLimiter(clock: () => t);
      for (var i = 0; i < 4; i++) {
        expect(l.tryTake(), isTrue);
      }
      expect(l.tryTake(), isFalse);
      expect(l.untilNext, const Duration(minutes: 1));
      expect(await l.take(), isFalse);
      t = t.add(const Duration(seconds: 61));
      expect(l.tryTake(), isTrue);
      l.pause();
      expect(l.tryTake(), isFalse);
      t = t.add(const Duration(minutes: 2));
      expect(l.tryTake(), isTrue);
    });

    test('daily cap', () {
      var t = DateTime(2026, 10, 27, 12);
      final l = VtLimiter(perMinute: 100, perDay: 2, clock: () => t);
      expect(l.tryTake() && l.tryTake(), isTrue);
      expect(l.tryTake(), isFalse);
      expect(l.untilNext, isNull);
      t = t.add(const Duration(days: 1));
      expect(l.tryTake(), isTrue);
    });
  });

  group('the check', () {
    test('a link VirusTotal already flags: one request, no scan, no website lookup', () async {
      final f = _Fake()..url = _urlObject(bad: 6, flagged: {'Fortinet': 'phishing', 'Kaspersky': 'phishing'});
      final hits = await run(f);
      expect(f.calls, ['GET /api/v3/urls/${virusTotalUrlId(_scam)}']);
      expect(hits.single.service, 'VirusTotal');
      expect(hits.single.weight, 30);
      expect(hits.single.summary, contains('as phishing'));
      expect(log.single.sentOffDevice, isTrue);
      expect(log.every((s) => s.status != StepStatus.running), isTrue);
    });

    test('an unknown link is scanned fresh and the website is looked up', () async {
      final f = _Fake()
        ..analysis = _analysis('completed', bad: 4)
        ..domain = _domain(bad: 1);
      final hits = await run(f);
      expect(f.calls, containsAll(['POST /api/v3/urls', 'GET /api/v3/analyses/u-abc-1', 'GET /api/v3/domains/poslaju-my-redelivery.top']));
      expect(f.submitted, [_scam]);
      // The fresh scan flags the link, so the weaker website hit is dropped.
      expect(hits.map((h) => h.service), ['VirusTotal']);
      expect(hits.single.weight, 24);
      expect(hits.single.summary, startsWith('In a fresh scan just now'));
      expect(log.map((s) => s.tool), containsAll(['VirusTotal', 'VirusTotal scan']));
      expect(log.every((s) => s.sentOffDevice && s.status == StepStatus.done), isTrue, reason: log.map((s) => '${s.tool}: ${s.result}').join('\n'));
    });

    test('a brand-new link on a flagged website still counts', () async {
      final f = _Fake()
        ..analysis = _analysis('completed')
        ..domain = _domain(bad: 3);
      final hits = await run(f);
      expect(hits.single.service, vtWebsiteService);
      expect(hits.single.weight, 20);
    });

    test('a scan that does not finish in time is reported honestly', () async {
      final f = _Fake();
      final hits = await run(f);
      expect(hits, isEmpty);
      final scan = log.firstWhere((s) => s.tool == 'VirusTotal scan');
      expect(scan.status, StepStatus.failed);
      expect(scan.result, contains('Still scanning'));
    });

    test('personal details are stripped before a scan', () async {
      final f = _Fake()..analysis = _analysis('completed');
      await run(f, url: 'https://pos-my.top/track?hp=0123456789');
      expect(f.submitted, ['https://pos-my.top/track']);
      expect(log.firstWhere((s) => s.tool == 'VirusTotal scan').action, contains('personal details in the link removed first'));
    });

    test('quick mode and extra hops never start a scan', () async {
      final f = _Fake();
      await run(f, quick: true);
      expect(f.calls.where((c) => c.startsWith('POST')), isEmpty);
      expect(f.calls, contains('GET /api/v3/domains/poslaju-my-redelivery.top'));
      final g = _Fake();
      await run(g, depth: VtDepth.lookup);
      expect(g.calls, hasLength(1));
    });

    test('official brand websites are not looked up as websites', () async {
      final f = _Fake()..url = _urlObject();
      await run(f, url: 'https://www.maybank2u.com.my/home');
      expect(f.calls.where((c) => c.contains('/domains/')), isEmpty);
    });

    test('over the limit: skipped and logged, nothing sent', () async {
      final f = _Fake();
      final t = DateTime(2026, 10, 27, 12);
      final l = VtLimiter(clock: () => t);
      for (var i = 0; i < 4; i++) {
        l.tryTake();
      }
      final hits = await run(f, limiter: l);
      expect(hits, isEmpty);
      expect(f.calls, isEmpty);
      expect(log.single.status, StepStatus.skipped);
      expect(log.single.sentOffDevice, isFalse);
      expect(log.single.result, contains('free limit'));
    });

    test('HTTP 429 pauses VirusTotal', () async {
      final f = _Fake()..status = 429;
      final l = VtLimiter.unlimited();
      await run(f, limiter: l);
      expect(log.single.status, StepStatus.failed);
      expect(log.single.result, contains('limit'));
      expect(l.tryTake(), isFalse);
    });

    test('a saved answer is reused without sending anything', () async {
      final f = _Fake()..url = _urlObject(bad: 2, flagged: {'Fortinet': 'phishing', 'ESET': 'phishing'});
      final cache = VtCache();
      await run(f, cache: cache, depth: VtDepth.lookup);
      log.clear();
      final hits = await run(f, cache: cache, depth: VtDepth.lookup);
      expect(f.calls, hasLength(1));
      expect(hits.single.weight, 14);
      expect(log.single.sentOffDevice, isFalse);
      expect(log.single.result, contains('nothing sent'));
    });
  });

  test('checkReputation without a VirusTotal key skips it', () async {
    final hits = await checkReputation(_scam, keys: ForensicKeys.none, client: _Fake().client, log: step, vtDepth: VtDepth.full);
    expect(hits, isEmpty);
    expect(log.firstWhere((s) => s.tool == 'VirusTotal').status, StepStatus.skipped);
  });
}
