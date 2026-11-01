import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/cloud/detection.dart';
import 'package:kantoi/cloud/outbox.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/engine/report.dart';
import 'package:kantoi/report/report_store.dart';
import 'package:kantoi/report/scam_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _offline = InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false);

class _MemSink implements CloudSink {
  final written = <String, Map<String, dynamic>>{};
  bool fail = false;
  @override
  Future<void> write(String collection, String id, Map<String, dynamic> data) async {
    if (fail) throw StateError('offline');
    written['$collection/$id'] = data;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('identifiers mask and normalise', () {
    const p = AttackerId(IdentifierType.phone, '+60 12-345 6789');
    expect(p.normalised, '0123456789');
    expect(p.masked, '012-***-6789');
    expect(identifierCode(p), identifierCode(const AttackerId(IdentifierType.phone, '012 345 6789')));
    expect(const AttackerId(IdentifierType.email, 'jayden@gmail.com').masked, 'j***@gmail.com');
    expect(const AttackerId(IdentifierType.handle, '@scammer99').masked, '@sc***');
  });

  test('amounts parse and print in the smallest unit', () {
    expect(ScamReport.parseAmount('3,500.5', 'MYR'), 350050);
    expect(ScamReport.parseAmount('0.05', 'BTC'), 5000000);
    expect((ScamReport(id: 'a', currency: 'MYR', amountMinor: 350050)).amountText, 'RM 3,500.50');
    expect((ScamReport(id: 'a', currency: 'USDT', amountMinor: 12000)).amountText, '120.00 USDT');
    expect(ScamReport.parseAmount('', 'MYR'), isNull);
  });

  test('a report pre-fills from a check and shares only masked details', () async {
    final inv = await investigate(
        'Tahniah! Kerja part time, like videos dapat komisen RM300 sehari. Bayar deposit RM50 ke akaun Maybank 5123 4567 8901. '
        'WhatsApp 012-345 6789 atau klik http://kerja-mudah.top/daftar',
        source: Source.whatsappWeb,
        options: _offline);
    final r = ScamReport.fromCheck(inv, id: 'r1');
    expect(r.kind, isNotNull);
    expect(r.channel, ContactChannel.whatsapp);
    expect(r.attackers.map((a) => a.type), contains(IdentifierType.phone));
    expect(r.links.single, contains('kerja-mudah.top'));
    expect(r.description, isNot(contains('012-345 6789')), reason: 'description is redacted');

    r
      ..lostMoney = true
      ..amountMinor = 5000
      ..transactionRef = 'TXN123456'
      ..description = 'My name is Ali and I paid';
    final p = r.sharedPayload();
    final s = jsonEncode(p);
    expect(s, isNot(contains('6789 ')));
    expect(s, isNot(contains('0123456789')));
    expect(s, isNot(contains('TXN123456')));
    expect(s, isNot(contains('Ali')));
    expect(p['domains'], ['kerja-mudah.top']);
    expect(p['amountMinor'], 5000);
    expect(r.situation, Situation.lostMoney);
    expect(r.toDetails().amount, 'RM 50.00');
  });

  test('missing fields are listed until the report is ready', () {
    final r = ScamReport(id: 'x');
    expect(r.ready, isFalse);
    r
      ..kind = 'cyber.phishing'
      ..channel = ContactChannel.sms
      ..links = ['http://a.top']
      ..lostMoney = false;
    expect(r.ready, isTrue);
  });

  test('submitting queues the masked payload, and the outbox waits until a sink exists', () async {
    final box = Outbox();
    await box.load();
    final store = ReportStore();
    final r = ScamReport(id: 'r2', kind: 'cyber.phishing', channel: ContactChannel.sms, links: ['http://pos-laju.top/x'], lostMoney: false);
    expect(await store.submit(r, outbox: box), isTrue);
    expect(r.status, ReportStatus.sent);
    expect(box.items.single.collection, 'reports');

    final sink = _MemSink()..fail = true;
    box.sink = sink;
    expect(await box.flush(), 0);
    expect(box.items.single.tries, 1);
    sink.fail = false;
    expect(await box.flush(), 1);
    expect(sink.written.keys, ['reports/r2']);
    expect(box.items, isEmpty);

    final off = ScamReport(id: 'r3', shareWithKantoi: false);
    expect(await store.submit(off, outbox: box), isFalse);

    final again = ReportStore();
    await again.load();
    expect(again.reports.map((r) => r.id), containsAll(['r2', 'r3']));
  });

  test('only confident scam detections are shared, without message text', () async {
    final scam = await investigate(
        'URGENT: PDRM officer here. Your bank account is linked to money laundering. A warrant will be issued today. '
        'Transfer your savings to safe account 5123 4567 8901 now and tell no one. Give me the TAC code you receive.',
        options: _offline);
    final p = detectionPayload(scam, app: 'com.whatsapp');
    if (scam.verdict.confidence >= shareMinConfidence && scam.verdict.level == RiskLevel.danger) {
      expect(p, isNotNull);
      final s = jsonEncode(p);
      expect(s, isNot(contains('laundering')));
      expect(s, isNot(contains('5123 4567 8901')));
      expect(p!['app'], 'com.whatsapp');
    }
    final clean = await investigate('Hi, lunch at 1pm tomorrow?', options: _offline);
    expect(detectionPayload(clean), isNull);
    final box = Outbox();
    expect(await shareDetection(scam, sharingOn: false, outbox: box), isFalse);
    expect(box.items, isEmpty);
  });
}
