import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/engine/community/community.dart';
import 'package:kantoi/engine/entities.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';

/// An in-memory community store.
class FakeCommunity implements CommunityIntel {
  final Map<String, List<CommunityReport>> byKey;
  final bool reportable;
  final List<(List<Indicator>, bool)> sent = [];
  List<Indicator>? looked;
  FakeCommunity([this.byKey = const {}, this.reportable = true]);

  @override
  String get name => 'fake';
  @override
  bool get canReport => reportable;
  @override
  String get whyNot => reportable ? '' : 'Sign in first';

  @override
  Future<List<CommunityTally>> lookup(List<Indicator> indicators) async {
    looked = indicators;
    return [for (final i in indicators) CommunityTally(i, byKey[i.key] ?? const [])];
  }

  @override
  Future<int> report(List<Indicator> indicators, {required bool scam, String? scamType}) async {
    sent.add((indicators, scam));
    return indicators.length;
  }
}

List<CommunityReport> reports(int scam, int legit, {int daysAgo = 3}) {
  final at = DateTime.now().subtract(Duration(days: daysAgo));
  return [
    for (var i = 0; i < scam; i++) CommunityReport(scam: true, at: at, scamType: 'Parcel scam'),
    for (var i = 0; i < legit; i++) CommunityReport(scam: false, at: at),
  ];
}

const offlineAi = LlmConfig(kind: LlmKind.none);

void main() {
  group('indicators', () {
    test('masks numbers and accounts, keeps websites, hashes keys', () {
      final ids = indicatorsIn(extractEntities(
          'Pay RM50 at https://pos-my.delivery-fee.xyz/pay or call 011-2345 6789. Bank in to Maybank 1640 2233 9081.'));
      final kinds = {for (final i in ids) i.kind: i};
      expect(kinds[IndicatorKind.domain]!.value, 'delivery-fee.xyz');
      expect(kinds[IndicatorKind.phone]!.value, '601123456789');
      expect(kinds[IndicatorKind.phone]!.display, '011-****6789');
      expect(kinds[IndicatorKind.bankAccount]!.display, '******9081');
      for (final i in ids) {
        expect(i.key, matches(RegExp(r'^(domain|phone|bankAccount|wallet|email)_[0-9a-f]{40}$')));
        expect(i.key, isNot(contains(i.value)), reason: 'raw values never appear in the store path');
      }
    });

    test('skips official sites and chat hosts, but reports the number in a wa.me link', () {
      final ids = indicatorsIn(extractEntities('Log in at https://www.maybank2u.com.my or chat wa.me/60112345678'));
      expect(ids.where((i) => i.kind == IndicatorKind.domain), isEmpty);
      expect(ids.single.kind, IndicatorKind.phone);
      expect(ids.single.value, '60112345678');
    });

    test('a shortener is keyed by its code, free hosting by its subdomain', () {
      expect(domainIndicator('https://bit.ly/3abcD')!.value, 'bit.ly/3abcD');
      expect(domainIndicator('https://bit.ly/'), isNull);
      expect(domainIndicator('https://claim-prize.web.app/x')!.value, 'claim-prize.web.app');
    });

    test('never reports your own details', () {
      final ids = indicatorsIn(extractEntities('Call me at 011-2345 6789'), ownDetails: {'0112345 6789'});
      expect(ids, isEmpty);
    });

    test('loose identifiers from the relationship check', () {
      final ids = indicatorsFromIdentifiers(['0123456789', '5642 1234 5678', 'scam@mail.com', 'https://bit.ly/abc']);
      expect(ids.map((i) => i.kind), [IndicatorKind.phone, IndicatorKind.bankAccount, IndicatorKind.email, IndicatorKind.domain]);
    });
  });

  group('reputation score', () {
    final i = indicatorsIn(extractEntities('call 011-2345 6789')).single;

    test('one report is never "strong"; three independent ones are', () {
      expect(scoreTally(CommunityTally(i, reports(1, 0))).level, CommunityLevel.some);
      expect(scoreTally(CommunityTally(i, reports(2, 0))).level, CommunityLevel.some);
      expect(scoreTally(CommunityTally(i, reports(3, 0))).level, CommunityLevel.strong);
    });

    test('genuine reports pull it back to disputed', () {
      expect(scoreTally(CommunityTally(i, reports(3, 4))).level, CommunityLevel.disputed);
      expect(scoreTally(CommunityTally(i, reports(0, 5))).level, CommunityLevel.none);
    });

    test('old reports fade', () {
      expect(scoreTally(CommunityTally(i, reports(3, 0, daysAgo: 400))).level, CommunityLevel.some);
      expect(reportWeight(DateTime.now(), DateTime.now()), 1.0);
      expect(reportWeight(DateTime.now().subtract(const Duration(days: 120)), DateTime.now()), 0.6);
    });

    test('findings and floors', () {
      expect(communityFindings([CommunityTally(i, reports(0, 0))]), isEmpty);
      final strong = communityFindings([CommunityTally(i, reports(3, 0))]).single;
      expect(strong.category, CueCategory.knownScam);
      expect(strong.weight, 30);
      expect(strong.explanation, contains('Parcel scam'));
      expect(communityFloor([CommunityTally(i, reports(3, 0))]), RiskLevel.suspicious);
      expect(communityFloor([CommunityTally(i, reports(6, 0))]), RiskLevel.danger);
      expect(communityFloor([CommunityTally(i, reports(1, 0))]), isNull);
    });
  });

  group('in a check', () {
    const msg = 'Hi, can you call me back at 011-2345 6789 when free?';
    final phone = indicatorsIn(extractEntities(msg)).single;

    test('many reports on the number raise a harmless-looking message to Very likely a scam', () async {
      final store = FakeCommunity({phone.key: reports(6, 0)});
      final r = await investigate(msg,
          options: InvestigateOptions(llm: offlineAi, network: true, webLookup: false, community: store));
      expect(store.looked, [phone]);
      expect(r.verdict.level, RiskLevel.danger);
      expect(r.findings.any((f) => f.tool == communityTool), isTrue);
      final s = r.log.firstWhere((l) => l.tool == communityTool);
      expect(s.sentOffDevice, isTrue);
      expect(s.status, StepStatus.done);
    });

    test('no reports change nothing', () async {
      final store = FakeCommunity();
      final r = await investigate(msg,
          options: InvestigateOptions(llm: offlineAi, network: true, webLookup: false, community: store));
      expect(r.findings.any((f) => f.tool == communityTool), isFalse);
      expect(r.log.firstWhere((l) => l.tool == communityTool).result, contains('No reports'));
    });

    test('offline: the store is not asked', () async {
      final store = FakeCommunity({phone.key: reports(6, 0)});
      final r = await investigate(msg, options: InvestigateOptions(llm: offlineAi, network: false, community: store));
      expect(store.looked, isNull);
      expect(r.log.firstWhere((l) => l.tool == communityTool).status, StepStatus.skipped);
    });
  });
}
