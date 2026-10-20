import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kantoi/engine/cues.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/engine/relationship.dart';
import 'package:kantoi/intake/apk.dart';
import 'package:kantoi/intake/chat_export.dart';
import 'package:kantoi/intake/docx.dart';
import 'package:kantoi/intake/email.dart';
import 'package:kantoi/intake/fake_document.dart';
import 'package:kantoi/intake/fingerprint.dart';
import 'package:kantoi/intake/image_scan.dart';
import 'package:kantoi/intake/language.dart';
import 'package:kantoi/intake/normalise.dart';
import 'package:kantoi/intake/pdf.dart';
import 'package:kantoi/intake/router.dart';
import 'package:zxing2/qrcode.dart';

const offline = InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false);

// ---- Tiny fixture builders ----

/// A minimal Android binary manifest (AXML) with a UTF-16 string pool.
Uint8List buildManifest(String pkg, List<String> permissions, {String? servicePermission}) {
  final strings = <String>['manifest', 'package', pkg, 'uses-permission', 'name', 'service', 'permission', '.Svc', ...permissions];
  if (servicePermission != null) strings.add(servicePermission);
  int idx(String s) => strings.indexOf(s);
  final out = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  final data = BytesBuilder();
  final offsets = <int>[];
  for (final s in strings) {
    offsets.add(data.length);
    u16(data, s.length);
    for (final c in s.codeUnits) {
      u16(data, c);
    }
    u16(data, 0);
  }
  while (data.length % 4 != 0) {
    data.addByte(0);
  }
  final pool = BytesBuilder();
  final poolHeader = 28;
  u16(pool, 0x0001);
  u16(pool, poolHeader);
  u32(pool, poolHeader + strings.length * 4 + data.length);
  u32(pool, strings.length);
  u32(pool, 0);
  u32(pool, 0);
  u32(pool, poolHeader + strings.length * 4);
  u32(pool, 0);
  for (final o in offsets) {
    u32(pool, o);
  }
  pool.add(data.toBytes());

  final body = BytesBuilder();
  void start(String name, Map<String, String> attrs) {
    u16(body, 0x0102);
    u16(body, 16);
    u32(body, 36 + 20 * attrs.length);
    u32(body, 1);
    u32(body, 0xFFFFFFFF);
    u32(body, 0xFFFFFFFF);
    u32(body, idx(name));
    u16(body, 20);
    u16(body, 20);
    u16(body, attrs.length);
    u16(body, 0);
    u16(body, 0);
    u16(body, 0);
    attrs.forEach((k, v) {
      u32(body, 0xFFFFFFFF);
      u32(body, idx(k));
      u32(body, idx(v));
      u16(body, 8);
      body.addByte(0);
      body.addByte(0x03);
      u32(body, idx(v));
    });
  }

  void end(String name) {
    u16(body, 0x0103);
    u16(body, 16);
    u32(body, 24);
    u32(body, 1);
    u32(body, 0xFFFFFFFF);
    u32(body, 0xFFFFFFFF);
    u32(body, idx(name));
  }

  start('manifest', {'package': pkg});
  for (final p in permissions) {
    start('uses-permission', {'name': p});
    end('uses-permission');
  }
  if (servicePermission != null) {
    start('service', {'name': '.Svc', 'permission': servicePermission});
    end('service');
  }
  end('manifest');

  final poolBytes = pool.toBytes(), bodyBytes = body.toBytes();
  u16(out, 0x0003);
  u16(out, 8);
  u32(out, 8 + poolBytes.length + bodyBytes.length);
  out.add(poolBytes);
  out.add(bodyBytes);
  return out.toBytes();
}

Uint8List zip(Map<String, String> files, {Map<String, List<int>> binary = const {}}) {
  final a = Archive();
  files.forEach((k, v) => a.addFile(ArchiveFile.string(k, v)));
  binary.forEach((k, v) => a.addFile(ArchiveFile.bytes(k, v)));
  return ZipEncoder().encodeBytes(a);
}

Uint8List buildPdf() {
  final content = utf8.encode('BT /F2 12 Tf 72 700 Td (LEMBAGA HASIL DALAM NEGERI MALAYSIA) Tj 0 -20 Td (Date: 01/01/2025) Tj '
      '0 -20 Td [(Please transfer RM1,500 to ) -300 (account no 5123 4567 8901 Maybank today.)] TJ '
      '0 -20 Td (Account name: Tan Ah Kow) Tj /F1 12 Tf 0 -20 Td <0001000200030003> Tj ET');
  final compressed = ZLibEncoder().encodeBytes(content);
  const cmap = '/CIDInit /ProcSet findresource begin begincmap 1 begincodespacerange <0000> <FFFF> endcodespacerange '
      '2 beginbfchar <0001> <0048> <0002> <0069> endbfchar 1 beginbfrange <0003> <0003> <0021> endbfrange endcmap';
  final b = BytesBuilder();
  void w(String s) => b.add(latin1.encode(s));
  w('%PDF-1.7\n');
  w('1 0 obj << /Type /Catalog /Pages 2 0 R /OpenAction 7 0 R >> endobj\n');
  w('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n');
  w('3 0 obj << /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R /F2 8 0 R >> >> /Contents 5 0 R /Annots [6 0 R] >> endobj\n');
  w('4 0 obj << /Type /Font /Subtype /Type0 /BaseFont /ABC /Encoding /Identity-H /ToUnicode 9 0 R >> endobj\n');
  w('5 0 obj << /Length ${compressed.length} /Filter /FlateDecode >>\nstream\n');
  b.add(compressed);
  w('\nendstream\nendobj\n');
  w('6 0 obj << /Type /Annot /Subtype /Link /A << /S /URI /URI (http://lhdn-bayaran.xyz/pay) >> >> endobj\n');
  w("7 0 obj << /S /JavaScript /JS (app.alert\\('hi'\\)) >> endobj\n");
  w('8 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n');
  w('9 0 obj << /Length ${cmap.length} >>\nstream\n$cmap\nendstream\nendobj\n');
  w("10 0 obj << /Producer (Canva) /CreationDate (D:20261001120000+08'00') /ModDate (D:20261001120000) >> endobj\n");
  w('trailer << /Root 1 0 R /Info 10 0 R >>\n%%EOF\n');
  return b.toBytes();
}

Uint8List qrPicture(String content) {
  final qr = Encoder.encode(content, ErrorCorrectionLevel.m);
  final m = qr.matrix!;
  const scale = 6, margin = 60;
  final image = img.Image(width: m.width * scale + margin * 2 + 200, height: m.height * scale + margin * 2);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var x = 0; x < m.width; x++) {
    for (var y = 0; y < m.height; y++) {
      if (m.get(x, y) == 1) {
        img.fillRect(image, x1: margin + x * scale, y1: margin + y * scale, x2: margin + (x + 1) * scale - 1, y2: margin + (y + 1) * scale - 1, color: img.ColorRgb8(0, 0, 0));
      }
    }
  }
  return img.encodePng(image);
}

void main() {
  test('languages are detected on the device', () {
    expect(detectLanguages('Sila klik pautan ini untuk mengemas kini akaun anda dengan segera'), ['Malay']);
    expect(detectLanguages('Please click the link to update your account today'), ['English']);
    expect(detectLanguages('您的账户涉嫌洗钱，请立即转账到安全账户'), contains('Chinese'));
    expect(detectLanguages('உடனடியாக பணம் அனுப்பவும்'), contains('Tamil'));
    final mixed = detectLanguages('Boss, you need to bayar the yuran untuk parcel anda today, the link is here');
    expect(mixed, containsAll(['English', 'Malay']));
  });

  test('Chinese safe-account script is flagged', () async {
    final r = await investigate('我是警察。您的身份证涉嫌洗钱，请立即把存款转账到安全账户，不要告诉家人。', options: offline);
    expect(r.verdict.level, RiskLevel.danger, reason: '${r.verdict.score}');
    expect(r.artefact.languages, contains('Chinese'));
  });

  test('fake officer script rules fire', () {
    final f = detectCues('Your IC has been used for money laundering. Do not hang up, your call will be transferred to PDRM.');
    expect(f.map((x) => x.title), contains('Fake officer script'));
  });

  test('disguised brand spelling is caught', () {
    final f = disguisedSpellingFindings('Your m4yb4nk account is bl0cked. Pay via p0s laju now');
    expect(f.where((x) => x.title == 'Disguised brand name').length, 2);
    expect(f.map((x) => x.title), contains('Threat or penalty'));
    expect(deLeet('RM50 today'), 'RM50 today');
  });

  test('e-wallet ids and brands become entities', () {
    final e = extraEntities('Send to TNG eWallet 012-345 6789 now, Maybank is down');
    expect(e.any((x) => x.type == EntityType.ewallet), isTrue);
    expect(e.any((x) => x.type == EntityType.brand && x.value == 'Maybank'), isTrue);
  });

  test('email headers: reply-to mismatch, failed SPF and spoofed display name', () async {
    const raw = 'From: "Maybank Security" <alert@secure-mbb.xyz>\n'
        'Reply-To: helpdesk@gmail.com\n'
        'Subject: Your account is suspended\n'
        'Authentication-Results: mx.google.com; spf=fail smtp.mailfrom=secure-mbb.xyz; dkim=none\n'
        '\n'
        'Dear customer, verify your account at http://mbb-verify.top/login within 24 hours.';
    expect(detectKind(text: raw), IntakeKind.email);
    final e = parseEmail(raw)!;
    final titles = checkEmailHeaders(e).map((f) => f.title).toList();
    expect(titles, containsAll(['Replies go to a different address', 'Failed sender checks', 'Name does not match the sender']));
    final r = await routeInput(text: raw, network: false);
    expect(r.source, Source.email);
    expect(r.text, isNot(contains('Authentication-Results')));
    final inv = await investigate(r.text, source: r.source, options: offline, extras: r.extras);
    expect(inv.verdict.level, RiskLevel.danger);
  });

  test('plain text is not mistaken for an email', () {
    expect(parseEmail('From: your boss\nPlease transfer the money today'), isNull);
  });

  test('APK manifest: package and risky permissions', () async {
    final manifest = buildManifest('com.fake.bank', ['android.permission.READ_SMS', 'android.permission.INTERNET'],
        servicePermission: 'android.permission.BIND_ACCESSIBILITY_SERVICE');
    final info = parseManifest(manifest);
    expect(info.packageName, 'com.fake.bank');
    expect(info.permissions, containsAll(['android.permission.READ_SMS', 'android.permission.BIND_ACCESSIBILITY_SERVICE']));

    final apk = zip({'classes.dex': 'x'}, binary: {'AndroidManifest.xml': manifest});
    expect(detectKind(bytes: apk, name: 'PDRM_Semakan.apk'), IntakeKind.apk);
    final r = await routeInput(bytes: apk, name: 'PDRM_Semakan.apk', network: false);
    expect(r.extras.meta['SHA-256'], hasLength(64));
    expect(r.extras.steps.any((s) => s.tool == 'VirusTotal' && s.status == StepStatus.skipped), isTrue);
    final inv = await investigate(r.text, source: r.source, options: offline, extras: r.extras);
    expect(inv.verdict.level, RiskLevel.danger, reason: '${inv.verdict.score}');
    expect(inv.verdict.nextStep, apkWarning);
    expect(inv.artefact.kind, 'apk');
  });

  test('DOCX: text, links, macros, remote template and metadata', () {
    final docx = zip({
      'word/document.xml': '<w:document><w:body><w:p><w:r><w:t>Notis Mahkamah Majistret</w:t></w:r></w:p>'
          '<w:p><w:r><w:t xml:space="preserve">Bayar denda &amp; kos </w:t></w:r><w:r><w:t>segera.</w:t></w:r></w:p></w:body></w:document>',
      'word/_rels/document.xml.rels': '<Relationships><Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="http://mahkamah-bayar.top/?a=1&amp;b=2" TargetMode="External"/></Relationships>',
      'word/_rels/settings.xml.rels': '<Relationships><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/attachedTemplate" Target="http://evil.example/t.dotm" TargetMode="External"/></Relationships>',
      'docProps/core.xml': '<cp:coreProperties><dc:creator>Admin</dc:creator><dcterms:created xsi:type="dcterms:W3CDTF">2026-10-10T01:00:00Z</dcterms:created></cp:coreProperties>',
    }, binary: {
      'word/vbaProject.bin': [1, 2, 3]
    });
    final d = readDocx(docx);
    expect(d.text, contains('Bayar denda & kos segera.'));
    expect(d.links.single, 'http://mahkamah-bayar.top/?a=1&b=2');
    expect(d.hasMacros, isTrue);
    expect(d.externalTemplates.single, 'http://evil.example/t.dotm');
    expect(d.meta['Author'], 'Admin');
    expect(docxFindings(d).map((f) => f.title), containsAll(['Contains macros', 'Loads content from the internet']));
    expect(detectKind(bytes: docx, name: 'notice.docx'), IntakeKind.docx);
  });

  test('PDF: text with ToUnicode fonts, links, script and fake letter cues', () async {
    final pdf = buildPdf();
    final p = readPdf(pdf);
    expect(p.text, contains('LEMBAGA HASIL DALAM NEGERI'));
    expect(p.text, contains('Please transfer RM1,500 to account no'));
    expect(p.text, contains('Hi!!'));
    expect(p.textReliable, isTrue);
    expect(p.links.single, 'http://lhdn-bayaran.xyz/pay');
    expect(p.javascript, isTrue);
    expect(p.autoRun, isTrue);
    expect(p.meta['Producer'], 'Canva');
    expect(p.meta['Created'], startsWith('2026-10-01'));

    final fake = fakeDocumentFindings(p.text, p.meta).map((f) => f.title).toList();
    expect(fake, containsAll(['Official letter asks for payment', 'Payment to a personal account', 'Letter date does not match the file']));

    final r = await routeInput(bytes: pdf, name: 'notis_lhdn.pdf', network: false);
    expect(r.kind, IntakeKind.pdf);
    expect(r.text, contains('http://lhdn-bayaran.xyz/pay'));
    final inv = await investigate(r.text, source: r.source, options: offline, extras: r.extras);
    expect(inv.verdict.level, RiskLevel.danger);
    expect(inv.findings.any((f) => f.title == 'Runs a script when opened'), isTrue);
  });

  test('QR code is found in a picture and its link is checked', () async {
    final png = qrPicture('https://poslaju-redelivery.top/pay');
    final scan = scanImage(png);
    expect(scan.qr, 'https://poslaju-redelivery.top/pay');
    final r = await routeInput(bytes: png, name: 'qr.png', llm: const LlmConfig(kind: LlmKind.none), network: false);
    expect(r.kind, IntakeKind.image);
    expect(r.text, contains('QR code: https://poslaju-redelivery.top/pay'));
    expect(r.extras.steps.map((s) => s.tool), containsAll(['QR reader', 'Screenshot reader', 'Fingerprint']));
  });

  test('payment QR is described', () {
    String tlv(String id, String v) => '$id${v.length.toString().padLeft(2, '0')}$v';
    final duitnow = tlv('00', '01') + tlv('01', '12') + tlv('26', tlv('00', 'A000000615000101')) + tlv('52', '0000') +
        tlv('53', '458') + tlv('54', '150.00') + tlv('58', 'MY') + tlv('59', 'TAN AH KOW SB') + tlv('60', 'KUALA LUMPUR') + tlv('63', 'ABCD');
    expect(describeQr(duitnow), contains('TAN AH KOW SB'));
    expect(describeQr(duitnow), contains('RM150.00'));
  });

  test('picture metadata: editing software is a minor signal', () {
    final f = imageMetaFindings({'Software': 'Adobe Photoshop 25.0'});
    expect(f.single.weight, lessThan(10));
  });

  test('VirusTotal reply parsing', () {
    final bad = parseVirusTotal(200, jsonEncode({
      'data': {
        'attributes': {
          'meaningful_name': 'bank.apk',
          'last_analysis_stats': {'malicious': 30, 'suspicious': 2, 'harmless': 0, 'undetected': 40},
          'popular_threat_classification': {'suggested_threat_label': 'trojan.smsthief'}
        }
      }
    }));
    expect(bad.malicious, 30);
    expect(bad.total, 72);
    expect(hashFinding(bad)!.weight, greaterThan(30));
    expect(hashSummary(bad), contains("Only the file's fingerprint was checked online"));
    expect(parseVirusTotal(404, '').known, isFalse);
    expect(hashFinding(parseVirusTotal(404, '')), isNull);
    expect(sha256Of(utf8.encode('abc')), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('Telegram export becomes chat messages and WhatsApp-style lines', () {
    final json = jsonEncode({
      'name': 'Amanda',
      'type': 'personal_chat',
      'messages': [
        {'id': 1, 'type': 'service', 'date': '2026-10-01T10:00:00', 'actor': 'Amanda'},
        {'id': 2, 'type': 'message', 'date': '2026-10-01T10:01:00', 'from': 'Amanda', 'text': 'Hi dear, wrong number?'},
        {
          'id': 3,
          'type': 'message',
          'date': '2026-10-02T21:15:00',
          'from': 'Amanda',
          'text': [
            'My uncle trades crypto, ',
            {'type': 'link', 'text': 'https://usdt-profit.vip'},
            ' guaranteed 30% profit'
          ]
        },
        {'id': 4, 'type': 'message', 'date': '2026-10-02T21:16:00', 'from': 'Kevin', 'text': 'Really?'},
      ]
    });
    final msgs = parseTelegramExport(json);
    expect(msgs, hasLength(3));
    expect(msgs[1].text, 'My uncle trades crypto, https://usdt-profit.vip guaranteed 30% profit');
    final lines = chatExportText(Uint8List.fromList(utf8.encode(json)));
    final back = parseChatExport(lines);
    expect(back.map((m) => m.sender).toSet(), {'Amanda', 'Kevin'});
    expect(back[1].time, DateTime(2026, 10, 2, 21, 15));
    expect(parseAnyChatExport(json), hasLength(3));
  });

  test('router detects kinds from bytes and text', () {
    expect(detectKind(text: 'https://bit.ly/abc'), IntakeKind.url);
    expect(detectKind(text: 'hello there'), IntakeKind.text);
    expect(detectKind(bytes: Uint8List.fromList([0x4F, 0x67, 0x67, 0x53, 0, 0, 0, 0]), name: 'PTT-2026.opus'), IntakeKind.audio);
    expect(detectKind(bytes: Uint8List.fromList([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D]), name: 'v.mp4'), IntakeKind.video);
  });

  test('voice note without Gemini fails softly with a way forward', () async {
    expect(
        () => routeInput(bytes: Uint8List.fromList([0x4F, 0x67, 0x67, 0x53, 1, 2, 3, 4]), name: 'a.opus', llm: const LlmConfig(kind: LlmKind.none), network: false),
        throwsA(isA<IntakeError>().having((e) => e.message, 'message', contains('Type what was said'))));
  });
}
