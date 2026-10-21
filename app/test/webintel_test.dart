import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/engine/trace/trace_models.dart';
import 'package:kantoi/engine/trace/tracer.dart';
import 'package:kantoi/engine/webintel/grounding.dart';
import 'package:kantoi/engine/webintel/search_parsers.dart';
import 'package:kantoi/engine/webintel/web_intel.dart';
import 'package:kantoi/ui/result_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ddg = File('test/data/webintel/ddg_results.html').readAsStringSync();
final bing = File('test/data/webintel/bing_results.html').readAsStringSync();
final gemini = File('test/data/webintel/gemini_grounded.json').readAsStringSync();
const noKey = LlmConfig(kind: LlmKind.none);
const withKey = LlmConfig(kind: LlmKind.gemini, apiKey: 'test-key', model: 'gemini-flash-latest');

http.Response _html(String body) => http.Response(body, 200, headers: {'content-type': 'text/html; charset=utf-8'});

/// A small fake internet. [pages] decides whether the result pages open.
MockClient _net({
  bool pages = true,
  bool bingPage = true,
  String? ddgBody,
  String? bingBody,
  http.Response Function()? geminiReply,
  List<Uri>? calls,
}) =>
    MockClient((r) async {
      calls?.add(r.url);
      final u = r.url;
      switch (u.host) {
        case 'generativelanguage.googleapis.com':
          return geminiReply?.call() ?? http.Response(gemini, 200);
        case 'html.duckduckgo.com':
          return _html(ddgBody ?? ddg);
        case 'www.bing.com':
          return _html(bingBody ?? bing);
        case 'vertexaisearch.cloud.google.com':
          if (u.path.endsWith('AAA111')) return http.Response('', 302, headers: {'location': 'https://forum.example.com/threads/macau-scam-call.1234/'});
          return http.Response('', 403);
        case 'forum.example.com':
          if (!pages) return http.Response('', 403);
          return _html('<html><body><h1>Macau scam call</h1><p>Got a call from 012-345 6789 claiming to be police. It is a scam, do not transfer.</p>'
              '<script>var x = "0123456789 scam";</script></body></html>');
        case 'scamreports.example.my':
          if (!pages || !bingPage) return http.Response('', 403);
          return _html('<html><body><p>Nombor 0123456789 dilaporkan sebagai penipuan oleh 3 pengguna.</p></body></html>');
      }
      return http.Response('not found', 404);
    });

WebIntel _web(http.Client c, {LlmConfig llm = noKey, WebIntelCache? cache, GroundingLimiter? limiter, DateTime Function()? now}) =>
    WebIntel(client: c, llm: llm, cache: cache ?? WebIntelCache(persist: false), limiter: limiter ?? GroundingLimiter(), now: now);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final number = WebIdentifier.phone('012-345 6789');

  group('identifiers', () {
    test('every common Malaysian format is searched and recognised', () {
      expect(number.key, '60123456789');
      expect(number.display, '+60 12-345 6789');
      expect(number.variants, containsAll(['+60 12-345 6789', '012-3456789', '0123456789', '60123456789']));
      for (final f in ['+60 12-345 6789', '012-3456789', '0123456789', '60123456789', '+60123456789', '012-345 6789', '(012) 345-6789']) {
        expect(number.foundIn('call $f now'), isTrue, reason: f);
      }
      expect(number.foundIn('01234567890'), isFalse);
      expect(number.foundIn('0123456788'), isFalse);
      expect(WebIdentifier.phone('011-2004 7731').variants, contains('011-2004 7731'));
    });

    test("the user's own details are never searched", () {
      expect(number.isOwn({'+60123456789'}), isTrue);
      expect(number.isOwn({'0198765432'}), isFalse);
      final ids = webIdentifiersIn('Call 012-345 6789 or pay to Maybank account 5140 1234 9821, email help@bank-care.example');
      expect(ids.map((i) => i.kind), containsAll([WebIdKind.phone, WebIdKind.account, WebIdKind.email]));
      expect(webIdentifiersIn('Call 012-345 6789', own: {'0123456789'}), isEmpty);
    });
  });

  group('grounding', () {
    test('request shape uses the google_search tool', () {
      final body = LlmClient.groundedRequestBody('hi');
      expect(body['tools'], [
        {'google_search': <String, dynamic>{}}
      ]);
      expect((body['generationConfig'] as Map).containsKey('responseMimeType'), isFalse);
    });

    test('sources come only from the grounding metadata', () {
      final j = jsonDecode(gemini) as Map<String, dynamic>;
      final c = (j['candidates'] as List).first as Map<String, dynamic>;
      final reply = GroundedReply((c['content']['parts'] as List).first['text'] as String, c['groundingMetadata'] as Map<String, dynamic>);
      final a = parseGrounded(reply, number);
      expect(a.searched, isTrue);
      expect(a.reported, 'yes');
      expect(a.scamTypes, ['Fake officer (Macau) scam']);
      expect(a.sources.map((s) => s.domain), ['forum.example.com', 'scamreports.example.my', 'news.example.com']);
      expect(a.sources.every((s) => s.url.startsWith('https://vertexaisearch.cloud.google.com/')), isTrue);
      expect(a.sources.any((s) => s.url.contains('invented-by-model') || s.url.contains('made-up-path')), isFalse,
          reason: 'URLs the model writes in its text are never trusted');
      expect(a.sources[0].evidence, WebEvidence.grounded);
      expect(a.sources[2].evidence, WebEvidence.snippet, reason: 'cited for general advice, not a scam report');
    });

    test('an answer without grounding metadata is not used', () {
      final a = parseGrounded(const GroundedReply('{"reported_as_scam":"yes"}', null), number);
      expect(a.searched, isFalse);
      expect(a.sources, isEmpty);
    });
  });

  group('search pages', () {
    test('DuckDuckGo: ads dropped, redirect links unwrapped', () {
      final hits = parseDuckDuckGo(ddg);
      expect(hits.length, 4);
      expect(hits.first.url, 'https://forum.example.com/threads/macau-scam-call.1234/');
      expect(hits.first.snippet, contains('012-3456789'));
      expect(hits.any((h) => h.url.contains('y.js')), isFalse);
      final scammy = hits.where((h) => mentionsWithScamWords(h.text, number)).map((h) => hostOf(h.url)).toList();
      expect(scammy, ['forum.example.com'], reason: '"spam or scam?" pages, unrelated stories and plain contact pages do not count');
    });

    test('Bing: tracking links decoded, snippets read', () {
      final hits = parseBing(bing);
      expect(hits.length, 2);
      expect(hits.first.url, 'https://scamreports.example.my/number/60123456789');
      expect(hits.first.title, '+60 12-345 6789 dilaporkan: penipuan');
      expect(mentionsWithScamWords(hits.first.text, number), isTrue);
      expect(mentionsWithScamWords(hits.last.text, number), isFalse);
    });

    test('robot checks are reported, not parsed as empty', () {
      expect(() => parseDuckDuckGo('<div class="anomaly-modal">bots use DuckDuckGo too</div>'), throwsA(isA<SearchBlocked>()));
      expect(() => parseBing('<html><div id="b_captcha">captcha</div></html>'), throwsA(isA<SearchBlocked>()));
    });
  });

  group('lookup', () {
    test('Gemini grounding plus search pages, confirmed by opening the pages', () async {
      final log = <LogStep>[];
      final r = await _web(_net(), llm: withKey).lookup(number, log: (tool, action, {sentOffDevice = false}) {
        final s = LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice);
        log.add(s);
        return s;
      });
      expect(r.status, WebStatus.reported);
      expect(r.confirmedDomains, containsAll(['forum.example.com', 'scamreports.example.my']));
      expect(r.sources.any((s) => s.evidence == WebEvidence.pageConfirmed && s.url == 'https://forum.example.com/threads/macau-scam-call.1234/'), isTrue);
      expect(r.sources.any((s) => s.url.contains('invented-by-model')), isFalse);
      expect(r.sources.any((s) => s.domain == 'news.example.com'), isFalse);
      expect(r.methods, containsAll([groundedVia, 'DuckDuckGo', 'Bing']));
      expect(r.summary, contains('pretending to be police'));
      expect(log.where((s) => s.tool.startsWith(webTool)).every((s) => s.sentOffDevice), isTrue);
      expect(log.any((s) => s.status == StepStatus.running), isFalse);
      expect(webIntelFloor([r]), RiskLevel.danger);
    });

    test('without a key the public search pages still find it', () async {
      final calls = <Uri>[];
      final r = await _web(_net(calls: calls)).lookup(number);
      expect(calls.any((u) => u.host == 'generativelanguage.googleapis.com'), isFalse);
      expect(r.reported, isTrue);
      expect(r.methods, ['DuckDuckGo', 'Bing']);
    });

    test('a search snippet alone is only a "possible" report', () async {
      final r = await _web(_net(pages: false)).lookup(number);
      expect(r.status, WebStatus.possible);
      expect(r.confirmed, isEmpty);
      expect(webIntelFloor([r]), isNull);
      final f = webIntelFindings([r]).single;
      expect(f.title, 'Possible scam reports online');
      expect(f.weight, lessThan(10));
    });

    test('one confirming site means suspicious, not danger', () async {
      final r = await _web(_net(bingPage: false, bingBody: '<ol id="b_results"></ol>')).lookup(number);
      expect(r.confirmedDomains, ['forum.example.com']);
      expect(webIntelFloor([r]), RiskLevel.suspicious);
    });

    test('nothing found is never "safe"', () async {
      final r = await _web(_net(ddgBody: '<div id="links"></div>', bingBody: '<ol id="b_results"></ol>')).lookup(number);
      expect(r.status, WebStatus.noReports);
      expect(r.headline, contains('does not prove'));
      expect(r.headline.toLowerCase(), isNot(contains('is safe')));
      expect(webIntelFindings([r]), isEmpty);
    });

    test('offline: logged, falls back, nothing cached', () async {
      final log = <LogStep>[];
      final dead = MockClient((r) async => throw const SocketException('offline'));
      final cache = WebIntelCache(persist: false);
      final r = await _web(dead, llm: withKey, cache: cache).lookup(number, log: (tool, action, {sentOffDevice = false}) {
        final s = LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice);
        log.add(s);
        return s;
      });
      expect(r.status, WebStatus.unavailable);
      expect(r.offline, isTrue);
      expect(log.firstWhere((s) => s.tool == webTool).result, startsWith('Offline'));
      expect(await cache.get(number, DateTime.now()), isNull);
    });

    test('Gemini quota: paused, logged, public search used instead', () async {
      final limiter = GroundingLimiter();
      final log = <LogStep>[];
      final r = await _web(_net(geminiReply: () => http.Response('{"error":{"code":429}}', 429)), llm: withKey, limiter: limiter).lookup(number,
          log: (tool, action, {sentOffDevice = false}) {
        final s = LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice);
        log.add(s);
        return s;
      });
      expect(log.firstWhere((s) => s.tool.contains('Gemini')).result, contains('quota'));
      expect(r.reported, isTrue);
      expect(limiter.acquire(DateTime.now()), contains('paused'));
    });

    test('rate limit on grounded calls', () {
      final l = GroundingLimiter(max: 2, window: const Duration(minutes: 10));
      final t = DateTime(2026, 10, 21, 10);
      expect(l.acquire(t), isNull);
      expect(l.acquire(t), isNull);
      expect(l.acquire(t), isNotNull);
      expect(l.acquire(t.add(const Duration(minutes: 11))), isNull);
    });

    test('results are kept for 24 hours', () async {
      var now = DateTime(2026, 10, 21, 9);
      final calls = <Uri>[];
      final cache = WebIntelCache(persist: false);
      final w = _web(_net(calls: calls), cache: cache, now: () => now);
      await w.lookup(number);
      final first = calls.length;
      final again = await w.lookup(number);
      expect(again.fromCache, isTrue);
      expect(again.reported, isTrue);
      expect(calls.length, first);
      now = now.add(const Duration(hours: 25));
      await w.lookup(number);
      expect(calls.length, greaterThan(first));
    });

    test('the cache survives a restart through shared preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final r = WebIntelResult(identifier: number, status: WebStatus.noReports, checkedAt: DateTime.now(), methods: const ['Bing']);
      await WebIntelCache().put(r);
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys().single, WebIntelCache.keyFor(number));
      expect(p.getKeys().single, isNot(contains('6789')), reason: 'the number is not stored in the clear as a key');
      final back = await WebIntelCache().get(number, DateTime.now());
      expect(back?.status, WebStatus.noReports);
    });
  });

  group('check', () {
    InvestigateOptions opts(http.Client c, {Set<String> own = const {}}) =>
        InvestigateOptions(llm: noKey, httpClient: c, webCache: WebIntelCache(persist: false), ownDetails: own);

    test('a number reported on two sites is raised to danger', () async {
      final inv = await investigate('012-345 6789', options: opts(_net()));
      expect(inv.verdict.level, RiskLevel.danger, reason: '${inv.verdict.score} ${inv.findings.map((f) => f.title)}');
      expect(inv.findings.any((f) => f.title == 'Reported online as a scam'), isTrue);
      expect(inv.verdict.headline, contains('reported online as a scam'));
      expect(webIntelOf(inv).single.reported, isTrue);
      final web = inv.log.where((s) => s.tool.startsWith(webTool) && s.status != StepStatus.skipped);
      expect(web, isNotEmpty);
      expect(web.every((s) => s.sentOffDevice), isTrue);
    });

    test('one confirming site raises it to at least suspicious', () async {
      final inv = await investigate('Who is this? 012-345 6789',
          options: opts(_net(bingPage: false, bingBody: '<ol id="b_results"></ol>')));
      expect(inv.verdict.level.index, greaterThanOrEqualTo(RiskLevel.suspicious.index));
    });

    test('nothing found: "No warning signs found yet", never "Looks safe"', () async {
      final inv = await investigate('012-345 6789',
          options: opts(_net(ddgBody: '<div id="links"></div>', bingBody: '<ol id="b_results"></ol>')));
      expect(inv.verdict.level, RiskLevel.safe);
      expect(verdictLabel(inv.verdict.level, inv.findings), 'No warning signs found yet');
      expect(inv.verdict.headline, startsWith('No warning signs found yet'));
      expect(inv.verdict.scamType, isNot('Legitimate message'));
      expect(inv.verdict.notChecked.join(' '), contains('does not prove'));
    });

    test('offline: the web step is logged and the verdict is not raised', () async {
      final inv = await investigate('012-345 6789', options: opts(MockClient((r) async => throw const SocketException('offline'))));
      expect(inv.log.firstWhere((s) => s.tool == webTool).result, startsWith('Offline'));
      expect(inv.verdict.notChecked.join(' '), contains('offline'));
      const off = InvestigateOptions(llm: noKey, network: false);
      final inv2 = await investigate('012-345 6789', options: off);
      expect(inv2.log.firstWhere((s) => s.tool == webTool).result, startsWith('Offline'));
    });

    test("the user's own number is never searched", () async {
      final calls = <Uri>[];
      final inv = await investigate('My number is 012-345 6789', options: opts(_net(calls: calls), own: {'0123456789'}));
      expect(calls.where((u) => u.host.contains('duckduckgo') || u.host.contains('bing')), isEmpty);
      expect(inv.log.firstWhere((s) => s.tool == webTool).status, StepStatus.skipped);
    });

    testWidgets('result screen shows the "Found online" evidence', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 3000));
      final inv = (await t.runAsync(() => investigate('012-345 6789', options: opts(_net()))))!;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ResultView(inv: inv)))));
      await t.pumpAndSettle();
      expect(find.text('Found online'), findsOneWidget);
      expect(find.text('forum.example.com'), findsWidgets);
      expect(find.textContaining('Kantoi opened this page'), findsWidgets);
    });
  });

  group('trace', () {
    test('web report nodes hang off the number, with the evidence', () async {
      final c = _net();
      final tracer = Tracer(client: c, webIntel: _web(c));
      final s = TraceState();
      await tracer.run('012-345 6789').forEach(s.apply);
      final reports = s.nodes.values.where((n) => n.kind == TraceKind.webReport).toList();
      expect(reports.map((n) => n.label), contains('Report on forum.example.com'));
      expect(reports.every((n) => n.parent == 'phone:60123456789'), isTrue);
      final f = reports.first.facts.map((f) => f.$1);
      expect(f, containsAll(['Site', 'Link', 'Found via', 'How it was checked']));
      expect(s.flags.any((f) => f.title == 'Reported online as a scam' && f.nodeId == 'phone:60123456789'), isTrue);
      expect(s.lookups.any((l) => l.step.tool == webTool && l.online), isTrue);
      expect(s.lookups.every((l) => l.step.status != StepStatus.running), isTrue);
    });

    test("the tracer skips the user's own number", () async {
      final calls = <Uri>[];
      final c = _net(calls: calls);
      final s = TraceState();
      await Tracer(client: c, webIntel: _web(c), ownDetails: {'+60123456789'}).run('012-345 6789').forEach(s.apply);
      expect(calls, isEmpty);
      expect(s.lookups.firstWhere((l) => l.step.tool == webTool).step.status, StepStatus.skipped);
    });
  });
}
