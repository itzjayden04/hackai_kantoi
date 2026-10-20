import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/engine/attribution/attribution.dart';
import 'package:kantoi/engine/attribution/crawler.dart';
import 'package:kantoi/engine/attribution/fingerprint.dart';
import 'package:kantoi/engine/attribution/graph.dart';
import 'package:kantoi/engine/attribution/intel_models.dart';
import 'package:kantoi/engine/attribution/intel_store.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';
import 'package:flutter/material.dart';
import 'package:kantoi/ui/intel_graph_view.dart';
import 'package:kantoi/ui/who_behind.dart';
import 'package:shared_preferences/shared_preferences.dart';

const offline = InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false);
final seed = File('assets/intel_seed.json').readAsStringSync();

Future<IntelService> demo() async {
  final s = IntelService(seedJson: seed, persist: false);
  await s.ensureLoaded();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('campaigns from demo data', () {
    test('seed clusters into six labelled campaigns', () async {
      final s = await demo();
      final labels = s.graph.campaigns.map((c) => c.label).toList();
      expect(labels.length, 6, reason: '$labels');
      expect(labels.any((l) => l.startsWith('Fake Pos Laju fee SMS, ')), isTrue, reason: '$labels');
      expect(labels.any((l) => l.startsWith('Fake PDRM officer calls')), isTrue, reason: '$labels');
      expect(s.graph.campaigns.every((c) => c.synthetic), isTrue);
      final pos = s.graph.campaigns.firstWhere((c) => c.brand == 'Pos Malaysia');
      expect(pos.domains, greaterThanOrEqualTo(5));
      expect(pos.reports.length, 4);
      expect(pos.channels.first, 'SMS');
      expect(pos.targets, contains('Online shoppers'));
    });

    test('every edge carries a reason and evidence', () async {
      final s = await demo();
      final kinds = s.graph.edges.map((e) => e.kind).toSet();
      expect(kinds, containsAll([EdgeKind.nameserver, EdgeKind.hosting, EdgeKind.pageTemplate, EdgeKind.payout, EdgeKind.contact, EdgeKind.script]));
      expect(s.graph.edges.every((e) => e.evidence.isNotEmpty && e.strength > 0), isTrue);
    });

    test('account holders are never named, accounts are shortened', () async {
      final s = await demo();
      final acct = s.graph.nodes['bankAccount:512345678901']!;
      expect(acct.display, 'Account ending 8901');
    });
  });

  group('attribution in an investigation', () {
    test('parcel SMS example links to the Pos Laju campaign', () async {
      await intel.ensureLoaded();
      final r = await investigate(
          'POS MALAYSIA: Your parcel is held due to an unpaid fee of RM2.50. Pay within 24 hours or it will be returned: https://poslaju-my-redelivery.top/pay',
          options: offline);
      final a = r.attribution!;
      expect(a.campaign?.brand, 'Pos Malaysia');
      expect(a.confidence, greaterThan(0.6));
      expect(a.linkedDomains, greaterThanOrEqualTo(5));
      expect(a.sentence, contains('known scam campaign'));
      expect(r.findings.any((f) => f.category == CueCategory.knownScam), isTrue);
      expect(r.log.any((s) => s.tool == 'Threat intel'), isTrue);
      expect(a.graph.nodes.length, greaterThan(3));
    });

    test('fake police call and README demo account match their campaigns', () async {
      await intel.ensureLoaded();
      final police = await investigate(
          'This is Inspector Lim from PDRM. Transfer your savings to this safe account 5123 4567 8901 immediately and do not tell anyone.',
          options: offline);
      expect(police.attribution!.campaign?.scamType, 'Fake officer (Macau) scam');
      final love = await investigate(
          'Dear, transfer RM5000 to this account 5123456789012 Maybank today only.',
          options: offline);
      expect(love.attribution!.campaign?.scamType, 'Love and investment scam');
      final job = await investigate('Add me on Telegram t.me/hr_lisa_job to start earning RM300 daily.', options: offline);
      expect(job.attribution!.campaign?.scamType, 'Job task scam');
    });

    test('ordinary message finds nothing', () async {
      await intel.ensureLoaded();
      final r = await investigate('Hey are we still on for dinner at 7? I booked a table at the mamak near your place.', options: offline);
      expect(r.attribution!.found, isFalse);
      expect(r.findings.any((f) => f.category == CueCategory.knownScam), isFalse);
    });

    test('a new domain is linked by shared nameserver alone', () async {
      final s = await demo();
      final probe = IntelEntity(
          type: NodeType.domain,
          key: 'poslaju-bayar-cepat.top',
          source: IntelSource.seen,
          firstSeen: DateTime.now(),
          nameservers: ['ns1.kirimdns.example', 'ns2.kirimdns.example']);
      final r = matchProbes(s.graph, [(probe, probe.key, null, null)]);
      expect(r.campaign?.brand, 'Pos Malaysia');
      expect(r.matches.first.via, EdgeKind.nameserver);
      expect(r.confidence, greaterThan(0.4));
    });

    test('popular DNS providers do not link unrelated sites', () async {
      final s = await demo();
      final probe = IntelEntity(
          type: NodeType.domain, key: 'kedai-roti.my', source: IntelSource.seen, firstSeen: DateTime.now(), nameservers: ['amy.ns.cloudflare.com']);
      expect(matchProbes(s.graph, [(probe, probe.key, null, null)]).found, isFalse);
    });
  });

  group('community reports', () {
    test('strong report is stored with its scammer details, weak one is refused', () async {
      final s = await demo();
      final strong = await investigate(
          'URGENT: Your Maybank account is blocked. Login now at https://maybank-unblock-now.xyz and enter your TAC. Pay RM50 fee to account 7012 3456 7890 today.',
          options: offline);
      final rep = s.addCommunityReport(strong, exclude: {'7012 3456 7890'})!;
      expect(rep.evidence, greaterThan(0.3));
      expect(rep.entityIds, contains('domain:maybank-unblock-now.xyz'));
      expect(rep.entityIds.any((e) => e.contains('701234567890')), isFalse, reason: 'hidden by the user');
      expect(s.hasReport(strong), isTrue);
      s.removeReport(strong);
      expect(s.hasReport(strong), isFalse);
      expect(s.db.entities.containsKey('domain:maybank-unblock-now.xyz'), isFalse);

      final weak = await investigate('Hey are we still on for dinner at 7?', options: offline);
      expect(s.addCommunityReport(weak), isNull);
    });

    test('many weak fake reports do not merge campaigns or raise evidence', () async {
      final s = await demo();
      final before = s.graph.campaigns.length;
      for (var i = 0; i < 20; i++) {
        s.db.reports.add(IntelReport(
            id: 'fake$i',
            at: DateTime.now(),
            scamType: 'Spam',
            channel: 'SMS',
            evidence: 0.15,
            entityIds: ['domain:poslaju-my-redelivery.top', 'bankAccount:512345678901']));
      }
      s.db.recomputeEvidence();
      final g = IntelGraph(s.db.entities.values, s.db.reports);
      expect(g.campaigns.length, before);
      expect(g.campaignOf['domain:poslaju-my-redelivery.top']!.id, isNot(g.campaignOf['bankAccount:512345678901']!.id));
    });
  });

  group('before you pay', () {
    test('known account and phone match, unknown does not', () async {
      final s = await demo();
      final a = s.quickCheck('5123 4567 8901');
      expect(a.found, isTrue);
      expect(a.kind, 'bank account');
      expect(a.campaign, isNotNull);
      expect(a.reports, 2);
      expect(s.quickCheck('011-2004 7731').kind, 'phone number');
      expect(s.quickCheck('011-2004 7731').found, isTrue);
      expect(s.quickCheck('1234 5678 0000').found, isFalse);
      expect(s.quickCheck('@hr_amy_task88').found, isTrue);
    });

    test('trend board has types, look-alikes, campaigns and news', () async {
      final s = await demo();
      final t = s.trends();
      expect(t.topTypes, isNotEmpty);
      expect(t.lookalikes.first.firstSeen.isAfter(DateTime.now().subtract(const Duration(days: 3))), isTrue);
      expect(t.campaigns.length, greaterThanOrEqualTo(5));
      expect(t.news, isNotEmpty);
    });
  });

  group('fingerprints', () {
    test('script sketches match reworded copies, not other scams', () {
      final a = scriptSketch('POS MALAYSIA: Your parcel is held due to an unpaid fee of RM2.50. Pay within 24 hours or it will be returned: https://a.top/pay');
      final b = scriptSketch('POS MALAYSIA: Your parcel is held due to an unpaid fee of RM9.90. Pay within 12 hours or it will be returned: https://b.xyz');
      final c = scriptSketch('Hi! We are hiring part-time. Simple tasks: like and follow YouTube videos, earn RM300 daily.');
      expect(scriptSimilarity(a, b), greaterThan(0.6));
      expect(scriptSimilarity(a, c), lessThan(0.1));
    });

    test('normalising keys', () {
      expect(phoneKey('012-345 6789'), '60123456789');
      expect(phoneKey('+60 12 345 6789'), '60123456789');
      expect(handleKey('t.me/HR_Lisa_Job'), 'hr_lisa_job');
      expect(domainKey('https://www.maybank2u.com.my/home'), isNull);
      expect(domainKey('http://login.m2u-secure.xyz/a'), 'm2u-secure.xyz');
      expect(domainKey('https://maybank-login.web.app'), 'maybank-login.web.app');
      expect(lookalikeBrand('poslaju-my-redelivery.top'), 'Pos Malaysia');
      expect(malaysianRelevant('https://secure-update.com/akaun/bayar'), isTrue);
      expect(malaysianRelevant('https://paypa1-login.com/'), isFalse);
      expect(fnv32('a'), 0xe40c292c);
    });

    test('labels are plain words', () {
      expect(campaignLabel('Parcel fee scam', 'Pos Malaysia', 'SMS', 'October'), 'Fake Pos Laju fee SMS, October wave');
      expect(campaignLabel('Job task scam', null, 'Telegram', 'September'), 'Fake part-time job on Telegram, September wave');
    });
  });

  group('crawler parsers (recorded replies)', () {
    test('crt.sh', () {
      const body = '''[
        {"issuer_name":"C=US, O=Let's Encrypt, CN=R11","common_name":"poslaju-bayar.top","name_value":"poslaju-bayar.top\\nwww.poslaju-bayar.top","not_before":"2026-10-18T03:00:00","id":1},
        {"issuer_name":"C=US, O=DigiCert Inc","common_name":"www.poslaju.com.my","name_value":"www.poslaju.com.my","not_before":"2026-10-17T00:00:00","id":2},
        {"issuer_name":"C=US, O=Let's Encrypt","common_name":"poslaju-old.top","name_value":"poslaju-old.top","not_before":"2026-01-01T00:00:00","id":3}
      ]''';
      final hits = parseCrtSh(body, since: DateTime(2026, 10, 1));
      expect(hits.map((h) => h.domain), ['poslaju-bayar.top']);
      expect(hits.single.brand, 'Pos Malaysia');
      expect(hits.single.issuer, "Let's Encrypt");
      expect(parseCrtSh('<html>busy</html>', since: DateTime(2026)), isEmpty);
    });

    test('OpenPhish and URLhaus are filtered to Malaysia', () {
      expect(parseOpenPhish('https://paypal-verify.com/x\nhttps://maybank2u-login.top/a\nhttps://x.com.my/\n'),
          ['https://maybank2u-login.top/a', 'https://x.com.my/']);
      const uh = '{"query_status":"ok","urls":[{"url":"http://cimbclicks-secure.xyz/bin","date_added":"2026-10-19 08:00:00 UTC"},{"url":"http://1.2.3.4/mozi","date_added":"2026-10-19 08:00:00 UTC"}]}';
      final l = parseUrlhaus(uh);
      expect(l.single.$1, 'http://cimbclicks-secure.xyz/bin');
      expect(l.single.$2, DateTime.utc(2026, 10, 19, 8));
    });

    test('RDAP, DNS over HTTPS and IP RDAP', () {
      const rdap = '''{"events":[{"eventAction":"registration","eventDate":"2026-10-10T01:02:03Z"}],
        "entities":[{"roles":["registrar"],"vcardArray":["vcard",[["version",{},"text","4.0"],["fn",{},"text","Demo Registrar Ltd"]]]}],
        "nameservers":[{"ldhName":"NS1.KIRIMDNS.EXAMPLE"},{"ldhName":"ns2.kirimdns.example."}]}''';
      final d = parseRdapDomain(rdap)!;
      expect(d.registrar, 'Demo Registrar Ltd');
      expect(d.created, DateTime.utc(2026, 10, 10, 1, 2, 3));
      expect(d.nameservers, ['ns1.kirimdns.example', 'ns2.kirimdns.example']);
      const doh = '{"Status":0,"Answer":[{"name":"x.top.","type":5,"data":"y.top."},{"name":"y.top.","type":1,"data":"203.0.113.24"}]}';
      expect(parseDoh(doh, 1), ['203.0.113.24']);
      expect(parseRdapIp('{"name":"DEMO-NET","country":"SC"}'), ('DEMO-NET', 'SC'));
    });

    test('robots.txt is respected', () {
      const robots = 'User-agent: Googlebot\nDisallow:\n\nUser-agent: *\nDisallow: /private\nAllow: /private/ok\n';
      final r = parseRobots(robots);
      expect(robotsAllows(r, '/'), isTrue);
      expect(robotsAllows(r, '/private/x'), isFalse);
      expect(robotsAllows(r, '/private/ok/1'), isTrue);
      expect(robotsAllows(parseRobots('User-agent: KantoiBot\nDisallow: /\n'), '/'), isFalse);
      expect(crawlAllowed(Uri.parse('https://semakmule.rmp.gov.my/')), isFalse);
      expect(crawlAllowed(Uri.parse('https://crt.sh/?q=x')), isTrue);
    });

    test('page title, favicon and RSS news', () {
      const html = '<html><head><title> Maybank2u &amp; You </title><link rel="shortcut icon" href="/img/fav.png"></head><body><form></form></body></html>';
      expect(parseTitle(html), 'Maybank2u & You');
      expect(faviconUri(html, Uri.parse('https://x.top/')).toString(), 'https://x.top/img/fav.png');
      expect(pageShape(html), pageShape(html.replaceAll('Maybank2u', 'CIMB')));
      const rss = '''<rss><channel>
        <item><title><![CDATA[Retiree loses RM300,000 to Macau scam syndicate]]></title><link>https://news.example/1</link><pubDate>Mon, 19 Oct 2026 08:30:00 +0800</pubDate></item>
        <item><title>Football: Harimau Malaya win</title><link>https://news.example/2</link></item>
      </channel></rss>''';
      final n = parseRss(rss, 'Test News');
      expect(n.single.scamType, 'Fake officer (Macau) scam');
      expect(n.single.at, DateTime.utc(2026, 10, 19, 0, 30));
    });
  });

  group('screens', () {
    testWidgets('who is behind it and the network graph', (tester) async {
      final s = await demo();
      final probe = IntelEntity(
          type: NodeType.domain, key: 'poslaju-x.top', source: IntelSource.seen, firstSeen: DateTime.now(), nameservers: ['ns1.kirimdns.example']);
      final r = matchProbes(s.graph, [(probe, probe.key, null, null)]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WhoBehindSection(result: r)))));
      expect(find.textContaining('known scam campaign'), findsOneWidget);
      expect(find.text('Demo data'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(home: IntelGraphPage(graph: r.graph)));
      expect(find.text('Linked because'), findsOneWidget);
      expect(find.textContaining('Same nameserver'), findsWidgets);
    });
  });
}
