import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/engine/sitecheck/site_check.dart';
import 'package:kantoi/engine/trace/trace_models.dart';
import 'package:kantoi/engine/trace/trace_pdf.dart';
import 'package:kantoi/engine/trace/tracer.dart';
import 'package:kantoi/engine/webintel/grounding.dart' show groundedVia;
import 'package:kantoi/engine/webintel/web_intel.dart';
import 'package:kantoi/ui/theme.dart';
import 'package:kantoi/ui/trace/site_summary.dart';
import 'package:kantoi/ui/trace/trace_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _page(String name) => File('test/data/sitecheck/$name.html').readAsStringSync();
final gambling = _page('gambling');
final investment = _page('investment');
final phishing = _page('phishing');
final wikipedia = _page('wikipedia');
final blog = _page('blog');

const noKey = LlmConfig(kind: LlmKind.none);

http.Response _html(String body) => http.Response(body, 200, headers: {'content-type': 'text/html; charset=utf-8'});

String _iso(int days) => DateTime.now().subtract(Duration(days: days)).toUtc().toIso8601String();

/// A fake internet: five websites, the Tranco list and the domain registry.
MockClient _net({List<Uri>? calls}) => MockClient((r) async => _site(r, calls));

http.Response _site(http.Request r, [List<Uri>? calls]) {
  calls?.add(r.url);
  final u = r.url;
  switch (u.host) {
    case 'ongong99.com':
      return _html(gambling);
    case 'profitmax-asia.com':
      return _html(investment);
    case 'secure-m2u-verify.com':
      return _html(phishing);
    case 'wikipedia.org':
    case 'www.wikipedia.org':
      return _html(wikipedia);
    case 'makcikbakes.my':
      return _html(blog);
    case 'tranco-list.eu':
      final d = u.pathSegments.last;
      final rank = const {'wikipedia.org': 9, 'ongong99.com': 412000}[d];
      return http.Response(
        jsonEncode({
          'domain': d,
          'ranks': rank == null
              ? []
              : [
                  {'date': '2026-10-19', 'rank': rank + 2},
                  {'date': '2026-10-20', 'rank': rank},
                ],
        }),
        200,
      );
    case 'rdap.org':
      final d = u.pathSegments.last;
      final age = const {'ongong99.com': 70, 'profitmax-asia.com': 12, 'secure-m2u-verify.com': 2, 'wikipedia.org': 9000, 'makcikbakes.my': 1500}[d];
      if (age == null) return http.Response('', 404);
      return http.Response(
        jsonEncode({
          'events': [
            {'eventAction': 'registration', 'eventDate': _iso(age)},
          ],
        }),
        200,
      );
  }
  return http.Response('not found', 404);
}

MockClient _offline() => MockClient((r) async => throw const SocketException('offline'));

PurposeResult _rules(String html, String url) => classifyPurpose(PageSample.fromHtml(html, Uri.parse(url)));

SiteChecker _checker(http.Client c) => SiteChecker(client: c, cache: SiteCache(persist: false));

Future<TraceState> _trace(String input, http.Client c) async {
  final s = TraceState();
  await Tracer(client: c, siteChecker: _checker(c)).run(input).forEach(s.apply);
  return s;
}

LogStep _log(String tool, String action, {bool sentOffDevice = false}) => LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('purpose rules (on the phone)', () {
    test('a mega888-style gambling page in English, Malay and Chinese', () {
      final p = _rules(gambling, 'https://ongong99.com/');
      expect(p.purpose, SitePurpose.gambling);
      expect(p.level, RiskLevel.danger);
      expect(p.headline, 'Online gambling site – illegal in Malaysia');
      expect(p.basis, PurposeBasis.page);
      expect(p.confidenceLabel, 'High');
      expect(p.reasons.join(' '), contains('mega888'));
      expect(p.reasons.join(' '), contains('APK'));
    });

    test('an investment page promising guaranteed returns', () {
      final p = _rules(investment, 'https://profitmax-asia.com/');
      expect(p.purpose, SitePurpose.investment);
      expect(p.severe, isTrue);
      expect(p.level, RiskLevel.danger);
      expect(p.headline, contains('guaranteed returns'));
    });

    test('a copied bank login page', () {
      final p = _rules(phishing, 'https://secure-m2u-verify.com/login');
      expect(p.purpose, SitePurpose.phishing);
      expect(p.brand, 'Maybank');
      expect(p.level, RiskLevel.danger);
    });

    test('ordinary pages are not given a risky purpose', () {
      for (final (html, url) in [(wikipedia, 'https://www.wikipedia.org/'), (blog, 'https://makcikbakes.my/')]) {
        final p = _rules(html, url);
        expect(p.purpose, SitePurpose.general, reason: url);
        expect(p.level, RiskLevel.safe, reason: url);
      }
    });

    test('news about a gambling raid is not a gambling site', () {
      const news =
          '<html><head><title>Police raid online gambling den in Johor Bahru</title></head><body>'
          '<p>Polis menyerbu sebuah premis judi online dan casino haram. 30 orang ditahan. The syndicate used mega888 and 918kiss accounts. '
          'Police warn the public to beware. Berita penuh di sini.</p></body></html>';
      final p = _rules(news, 'https://news.example.my/johor-raid');
      expect(p.purpose, isNot(SitePurpose.gambling));
      expect(p.reasons.join(' '), contains('news or a warning'));
    });

    test('licensed 4D results sites are not illegal gambling', () {
      final p = _rules('<html><title>Magnum 4D results</title><body>4D toto jackpot results, buy tickets at outlets</body></html>', 'https://www.magnum4d.my/');
      expect(p.purpose, SitePurpose.general);
      expect(p.reasons.single, contains('licensed'));
    });

    test('offline, the web address alone still gives a purpose', () {
      expect(classifyPurpose(PageSample.address(Uri.parse('https://mega888-my.com/'))).purpose, SitePurpose.gambling);
      expect(classifyPurpose(PageSample.address(Uri.parse('https://judi4d-online.net'))).purpose, SitePurpose.gambling);
      final p = classifyPurpose(PageSample.address(Uri.parse('https://mega888-my.com/')));
      expect(p.basis, PurposeBasis.address);
      expect(p.level, RiskLevel.danger);
      final plain = classifyPurpose(PageSample.address(Uri.parse('https://makcikbakes.my/')));
      expect(plain.purpose, SitePurpose.unknown);
      expect(plain.level, RiskLevel.safe);
      // Words inside other words are not matched.
      expect(classifyPurpose(PageSample.address(Uri.parse('https://alphabet.com'))).risky, isFalse);
      expect(classifyPurpose(PageSample.address(Uri.parse('https://judiciary.gov.my'))).risky, isFalse);
    });

    test('official websites are recognised without reading the page', () {
      final p = classifyPurpose(PageSample.address(Uri.parse('https://www.maybank2u.com.my/home')));
      expect(p.purpose, SitePurpose.legitBrand);
      expect(p.headline, 'Official website of Maybank');
    });

    test('the AI can raise an unmatched page but never clear a rule match', () {
      final plain = _rules(blog, 'https://makcikbakes.my/');
      final raised = mergeAi(plain, (SitePurpose.gambling, 0.9, false, ['"slot" in a hidden menu']));
      expect(raised.purpose, SitePurpose.gambling);
      expect(raised.level, RiskLevel.suspicious, reason: 'AI alone is capped at suspicious');
      expect(raised.basis, PurposeBasis.ai);
      final unsure = mergeAi(plain, (SitePurpose.gambling, 0.5, false, const <String>[]));
      expect(unsure.risky, isFalse);
      final kept = mergeAi(_rules(gambling, 'https://ongong99.com/'), (SitePurpose.general, 0.99, false, ['looks fine']));
      expect(kept.purpose, SitePurpose.gambling);
      expect(kept.level, RiskLevel.danger);
      expect(kept.aiPurpose, SitePurpose.general);
      expect(
        parsePurposeAi({
          'category': 'money_lending',
          'confidence': 0.8,
          'reasons': ['"no CTOS"'],
        })?.$1,
        SitePurpose.moneyLending,
      );
      expect(parsePurposeAi({'category': 'weather'}), isNull);
    });

    test('search results raise a site only when two sites describe it the same way', () {
      final url = Uri.parse('https://lucky-ong.com/');
      final base = classifyPurpose(PageSample.address(url));
      WebSource hit(String domain) => WebSource(
          title: 'lucky-ong.com Mega888 Malaysia',
          url: 'https://$domain/x',
          domain: domain,
          snippet: 'lucky-ong.com: download Mega888 APK, free credit RM10, deposit and withdraw fast',
          foundVia: 'Bing',
          evidence: WebEvidence.snippet);
      WebIntelResult web(List<WebSource> about) =>
          WebIntelResult(identifier: WebIdentifier.domain('lucky-ong.com'), status: WebStatus.noReports, checkedAt: DateTime.now(), about: about);
      expect(withWebPurpose(base, web([hit('a.example'), hit('a.example')]), url).risky, isFalse);
      final raised = withWebPurpose(base, web([hit('a.example'), hit('b.example')]), url);
      expect(raised.purpose, SitePurpose.gambling);
      expect(raised.level, RiskLevel.suspicious);
      expect(raised.basis, PurposeBasis.web);
    });

    test('the MCMC block notice is recognised', () {
      final s = PageSample.fromHtml(
        '<html><body>This website is not available in Malaysia as it violates the National law(s).</body></html>',
        Uri.parse('http://blocked.example/'),
      );
      expect(s.mcmcBlocked, isTrue);
    });

    test('Tranco answers', () {
      expect(parseTranco('{"domain":"google.com","ranks":[{"date":"2026-10-19","rank":2},{"date":"2026-10-20","rank":1}]}'), 1);
      expect(parseTranco('{"domain":"x.com","ranks":[]}'), isNull);
    });
  });

  group('site checker', () {
    test('gambling site: danger, poor reputation, cached for the next check', () async {
      final calls = <Uri>[];
      final c = _net(calls: calls);
      final checker = _checker(c);
      final r = await checker.check(Uri.parse('https://ongong99.com/'), ageDays: 70, log: _log);
      expect(r.purpose.purpose, SitePurpose.gambling);
      expect(r.level, RiskLevel.danger);
      expect(r.levelLabel, 'High risk');
      expect(r.trancoRank, 412000);
      expect(siteFindings(r).first.title, 'Online gambling site – illegal in Malaysia');
      expect(siteFloor([r]), RiskLevel.danger);
      expect(r.reasons().any((x) => x.weight < 0), isFalse, reason: 'popularity never offsets gambling');
      final n = calls.length;
      final again = await checker.check(Uri.parse('https://ongong99.com/'), log: _log);
      expect(again.fromCache, isTrue);
      expect(calls.length, n, reason: 'reused within 24 h');
    });

    test('well-known site: low risk, web search skipped', () async {
      final r = await _checker(_net()).check(Uri.parse('https://www.wikipedia.org/'), ageDays: 9000, log: _log);
      expect(r.purpose.purpose, SitePurpose.general);
      expect(r.wellKnown, isTrue);
      expect(r.level, RiskLevel.safe);
      expect(r.levelLabel, 'Low risk');
      expect(r.reputationLabel, 'Good');
      expect(r.reasons().map((x) => x.title), contains('Well-known website'));
      expect(r.sources.map((s) => s.label), contains('Tranco top-sites list'));
    });

    test('unknown harmless blog: no warning signs found yet', () async {
      final r = await _checker(_net()).check(Uri.parse('https://makcikbakes.my/'), ageDays: 1500, log: _log);
      expect(r.level, RiskLevel.safe);
      expect(r.levelLabel, 'No warning signs found yet');
      expect(r.trancoChecked, isTrue);
      expect(r.trancoRank, isNull);
      expect(r.reputationSummary, contains('Not in the top 1 million'));
    });

    test('offline: never throws and still reads the address', () async {
      final r = await _checker(_offline()).check(Uri.parse('https://mega888-my.com/'), log: _log);
      expect(r.purpose.purpose, SitePurpose.gambling);
      expect(r.purpose.basis, PurposeBasis.address);
      expect(r.level, RiskLevel.danger);
      expect(r.trancoChecked, isFalse);
      expect(r.reputationScore, isNull);
    });

    test('with a Gemini key: the AI reads the page text and Google Search describes the site', () async {
      final sent = <String>[];
      final c = MockClient((r) async {
        if (r.url.host != 'generativelanguage.googleapis.com') return _site(r);
        sent.add(r.body);
        if (r.body.contains('google_search')) {
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text':
                            '{"reported_as_scam": "no", "site_type": "gambling", "reputation": "bad", '
                            '"reputation_summary": "Forums describe it as an online casino that delays withdrawals."}',
                      },
                    ],
                  },
                  'groundingMetadata': {
                    'webSearchQueries': ['makcikbakes.my review'],
                    'groundingChunks': [
                      {
                        'web': {'uri': 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/ZZZ', 'title': 'forum.example.com'},
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"category": "legit_business", "confidence": 0.8, "reasons": ["recipes for kuih"]}'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });
      const key = LlmConfig(kind: LlmKind.gemini, apiKey: 'test-key', model: 'gemini-flash-latest');
      final checker = SiteChecker(
        client: c,
        llm: key,
        cache: SiteCache(persist: false),
        webIntel: WebIntel(client: c, llm: key, cache: WebIntelCache(persist: false), limiter: GroundingLimiter()),
      );
      final r = await checker.check(Uri.parse('https://makcikbakes.my/'), log: _log);
      // The page text went to the AI, nothing about the user.
      expect(sent.first, contains('Kuih Seri Muka'));
      expect(r.purpose.aiPurpose, SitePurpose.general);
      // Google results say it is a casino: raised, but only to suspicious.
      expect(r.purpose.purpose, SitePurpose.gambling);
      expect(r.purpose.basis, PurposeBasis.web);
      expect(r.level, RiskLevel.suspicious);
      expect(r.reasons().map((x) => x.title), contains('Bad reputation online'));
      expect(r.sources.map((s) => s.label), contains(groundedVia));
    });

    test('report survives a round trip through the cache format', () async {
      final r = await _checker(_net()).check(Uri.parse('https://profitmax-asia.com/'), ageDays: 12, log: _log);
      final back = SiteReport.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>)!;
      expect(back.purpose.purpose, SitePurpose.investment);
      expect(back.purpose.severe, isTrue);
      expect(back.level, r.level);
    });
  });

  group('trace', () {
    test('gambling site: Purpose and Reputation nodes, high risk', () async {
      final s = await _trace('https://ongong99.com/', _net());
      expect(s.nodes['purpose:ongong99.com']?.label, 'Purpose: Online gambling');
      expect(s.nodes['purpose:ongong99.com']?.flagged, isTrue);
      expect(s.nodes['reputation:ongong99.com']?.parent, 'domain:ongong99.com');
      expect(s.level, RiskLevel.danger);
      expect(s.riskLabel, 'High');
      expect(s.mainSite?.purpose.purpose, SitePurpose.gambling);
      expect(s.lookups.map((l) => l.step.tool), containsAll([purposeTool, popularityTool]));
      final text = traceSummaryText(s);
      expect(text, contains('Online gambling site – illegal in Malaysia'));
      expect(text, contains('Reputation'));
      final pdf = await buildTracePdf(s, now: DateTime(2026, 10, 21));
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    });

    test('investment scam and phishing pages are high risk', () async {
      for (final url in ['https://profitmax-asia.com/', 'https://secure-m2u-verify.com/login']) {
        final s = await _trace(url, _net());
        expect(s.level, RiskLevel.danger, reason: url);
        expect(s.mainSite?.purpose.risky, isTrue, reason: url);
      }
    });

    test('well-known site is low risk; unknown blog has no signs yet', () async {
      final w = await _trace('https://www.wikipedia.org/', _net());
      expect(w.level, RiskLevel.safe);
      expect(w.riskLabel, 'Low risk');
      expect(w.nodes['reputation:wikipedia.org']?.label, 'Reputation: Good');
      final b = await _trace('https://makcikbakes.my/', _net());
      expect(b.level, RiskLevel.safe);
      expect(b.riskLabel, 'No signs yet');
      expect(b.nodes['purpose:makcikbakes.my']?.label, 'Purpose: Ordinary website');
    });

    test('official site needs no page read and is low risk', () async {
      final s = await _trace('https://www.maybank2u.com.my/', _net());
      expect(s.mainSite?.purpose.purpose, SitePurpose.legitBrand);
      expect(s.riskLabel, 'Low risk');
    });

    test('offline: the purpose still comes from the address', () async {
      final s = await _trace('mega888-my.com', _offline());
      expect(s.finished, isTrue);
      expect(s.nodes['purpose:mega888-my.com']?.flagged, isTrue);
      expect(s.level, RiskLevel.danger);
      expect(s.lookups.every((l) => l.step.status != StepStatus.running), isTrue);
    });
  });

  testWidgets('findings page shows the purpose badge, reputation and sources', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 4000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final s = (await t.runAsync(() => _trace('https://ongong99.com/', _net())))!;
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: TraceFindingsPage(state: s)));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(SiteSummaryCard), findsOneWidget);
    expect(find.text('Online gambling site – illegal in Malaysia'), findsWidgets);
    expect(find.text('HIGH RISK'), findsOneWidget);
    expect(find.text('Tranco top-sites list'), findsOneWidget);
  });

  group('check tab', () {
    InvestigateOptions opts(http.Client c) => InvestigateOptions(llm: noKey, httpClient: c, webLookup: false, siteCache: SiteCache(persist: false));

    test('a gambling link pasted in Check is flagged', () async {
      final inv = await investigate('Jom main! Free credit RM10 untuk ahli baru https://ongong99.com/register', options: opts(_net()));
      expect(inv.verdict.level, RiskLevel.danger);
      expect(inv.verdict.scamType, 'Illegal online gambling site');
      expect(inv.verdict.headline, contains('illegal in Malaysia'));
      expect(inv.findings.map((f) => f.title), contains('Online gambling site – illegal in Malaysia'));
      expect(inv.log.map((s) => s.tool), contains(purposeTool));
      expect(sitesOf(inv).single.domain, 'ongong99.com');
    });

    test('offline, a gambling address is still flagged', () async {
      const offline = InvestigateOptions(llm: noKey, network: false);
      final inv = await investigate('Main sekarang di mega888-my.com', options: offline);
      expect(inv.verdict.level, RiskLevel.danger);
    });

    test('a well-known site is not raised', () async {
      final inv = await investigate('Read this https://www.wikipedia.org/', options: opts(_net()));
      expect(inv.verdict.level, RiskLevel.safe);
      expect(inv.findings.map((f) => f.title), contains('Well-known website'));
    });
  });

  group('Unfamiliar websites', () {
    const plain = PurposeResult(purpose: SitePurpose.general, level: RiskLevel.safe, confidence: 0.5, basis: PurposeBasis.page);
    SiteReport site(String d, {bool checked = true, int? rank, int? age}) =>
        SiteReport(domain: d, url: 'https://$d', purpose: plain, trancoChecked: checked, trancoRank: rank, ageDays: age, checkedAt: DateTime(2026));

    test('a young site nobody ranks is flagged as unfamiliar', () {
      final s = site('cheap-iphone-deal.shop', age: 20);
      expect(s.reasons().map((r) => r.title), contains('Unfamiliar website'));
      expect(s.level, RiskLevel.caution);
    });
    test('a ranked, old or unchecked site is not', () {
      expect(site('example.com', rank: 5000).reasons().map((r) => r.title), isNot(contains('Unfamiliar website')));
      expect(site('oldbakery.my', age: 365 * 6).reasons().map((r) => r.title), isNot(contains('Unfamiliar website')));
      expect(site('offline.my', checked: false).reasons(), isEmpty);
      expect(site('maybank2u.com.my').reasons().map((r) => r.title), isNot(contains('Unfamiliar website')));
    });
  });
}
