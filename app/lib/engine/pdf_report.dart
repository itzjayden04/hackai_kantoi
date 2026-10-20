/// A clean PDF report to bring to the police station or attach to a bank
/// dispute. Pure Dart, so it needs no platform code.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'cases.dart';
import 'models.dart';
import 'report.dart';

class EvidenceImage {
  final String name;
  final Uint8List bytes;
  const EvidenceImage(this.name, this.bytes);
}

/// The built-in PDF fonts only cover Western European letters, so anything
/// else (emoji, Chinese, Tamil) is replaced rather than breaking the file.
String pdfSafe(String s) {
  const map = {
    '‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-', '…': '...', '•': '-', '✓': '(done)', '⋯': '...',
    '→': '->', ' ': ' ',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (map.containsKey(ch)) {
      b.write(map[ch]);
    } else if (r == 0x0A || (r >= 0x20 && r <= 0x7E) || (r >= 0xA0 && r <= 0xFF)) {
      b.write(ch);
    } else if (r == 0x09) {
      b.write(' ');
    } else if (r > 0x20 && !(r >= 0x7F && r < 0xA0)) {
      b.write('?');
    }
  }
  return b.toString();
}

String _fmt(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}

Future<Uint8List> buildPdfReport({
  required Investigation? inv,
  required String scamText,
  required ReportDetails details,
  required Situation situation,
  ScamCase? scamCase,
  List<EvidenceImage> images = const [],
  DateTime? now,
}) async {
  final generated = now ?? DateTime.now();
  final v = inv?.verdict;
  final doc = pw.Document(title: 'Scam report', author: 'Kantoi', creator: 'Kantoi');
  const accent = PdfColor.fromInt(0xFF1E3A8A);
  final h = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: accent);
  const body = pw.TextStyle(fontSize: 10.5, lineSpacing: 2);
  final muted = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);

  pw.Widget section(String title, List<pw.Widget> children) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 14),
          pw.Text(pdfSafe(title), style: h),
          pw.Divider(color: PdfColors.grey400, thickness: 0.5),
          ...children,
        ],
      );
  pw.Widget p(String s, {pw.TextStyle? style}) => pw.Text(pdfSafe(s), style: style ?? body);
  pw.Widget table(List<(String, String)> rows) => pw.Table(
        columnWidths: {0: const pw.FixedColumnWidth(150), 1: const pw.FlexColumnWidth()},
        children: [
          for (final (k, val) in rows)
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text(pdfSafe(k), style: body.copyWith(fontWeight: pw.FontWeight.bold))),
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text(pdfSafe(val), style: body)),
            ]),
        ],
      );

  final ents = inv?.artefact.entities ?? const <Entity>[];
  String list(EntityType t) => ents.where((e) => e.type == t).map((e) => e.value).toSet().join(', ');
  final account = details.paidTo.isNotEmpty ? details.paidTo : list(EntityType.bankAccount);

  final timeline = <(String, String)>[
    if (inv != null) (_fmt(inv.artefact.receivedAt), 'Message checked with Kantoi'),
    if (details.when.isNotEmpty) (details.when, situation == Situation.lostMoney ? 'Money transferred (as I recall)' : 'Incident (as I recall)'),
    if (scamCase != null)
      for (final s in caseSteps)
        if (scamCase.done.containsKey(s.id)) (_fmt(scamCase.done[s.id]!), s.doneLabel),
  ];

  final transaction = <(String, String)>[
    if (details.amount.isNotEmpty) ('Amount', details.amount),
    if (details.when.isNotEmpty) ('Date and time', details.when),
    if (details.paidFromBank.isNotEmpty) ('Paid from (my bank)', details.paidFromBank),
    if (account.isNotEmpty) ('Paid to (scammer account)', account),
    if (details.scammerBank.isNotEmpty) ("Scammer's bank", details.scammerBank),
    if (details.transactionRef.isNotEmpty) ('Transaction reference', details.transactionRef),
  ];

  final identifiers = <(String, String)>[
    for (final (label, t) in [
      ('Phone numbers', EntityType.phone),
      ('Bank accounts', EntityType.bankAccount),
      ('Links', EntityType.url),
      ('Crypto wallets', EntityType.cryptoWallet),
      ('Social handles', EntityType.handle),
      ('Emails', EntityType.email),
    ])
      if (list(t).isNotEmpty) (label, list(t)),
    if (details.scammerContact.trim().isNotEmpty) ('Their number, profile or link', details.scammerContact.trim()),
    if (details.contactMethod.isNotEmpty) ('How they contacted me', details.contactMethod),
  ];

  final images0 = <(String, pw.MemoryImage)>[];
  final unreadable = <String>[];
  for (final img in images) {
    try {
      images0.add((img.name, pw.MemoryImage(img.bytes)));
    } catch (_) {
      unreadable.add(img.name);
    }
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
    header: (ctx) => ctx.pageNumber == 1
        ? pw.SizedBox()
        : pw.Text('Scam report (continued)', style: muted),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Prepared with Kantoi on ${_fmt(generated)}. Personal details of the victim are masked.', style: muted),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: muted),
    ]),
    build: (ctx) => [
      pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: const pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.all(pw.Radius.circular(6))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('SCAM REPORT', style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.Text('For the police, my bank and the National Scam Response Centre (997)',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
          ]),
          pw.Text(_fmt(generated), style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
        ]),
      ),
      section('Situation', [
        p(situationLabels[situation]!),
        pw.SizedBox(height: 4),
        p(incidentDescription(inv, details, situation)),
      ]),
      if (timeline.isNotEmpty) section('Timeline', [table(timeline)]),
      if (transaction.isNotEmpty) section('Transaction details', [table(transaction)]),
      section('Scammer identifiers', [identifiers.isEmpty ? p(inv == null ? 'None given.' : 'None found in the message.') : table(identifiers)]),
      if (scamText.trim().isNotEmpty)
        section('The message (my personal details masked)', [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
          child: p(scamText),
        ),
      ]),
      if (v != null)
        section('Kantoi verdict', [
          table([
            ('Result', '${riskLabel(v.level)} (risk ${v.score}/100, confidence ${v.confidence}%)'),
            ('Type', v.scamType),
            ('Summary', v.headline),
          ]),
        ]),
      section('Evidence summary', [
        if (inv == null && images.isEmpty) p('- No message was checked with Kantoi for this report.'),
        for (final f in (inv?.findings ?? const <Finding>[]).where((f) => f.isRisk)) p('- ${f.title}: ${f.explanation}'),
        for (final u in inv?.urls ?? const <UrlReport>[])
          p('- Link ${u.input} leads to ${u.finalUrl}${u.imitates != null ? ' (imitates ${u.imitates})' : ''}'
              '${u.domainAgeDays != null ? ', website registered ${u.domainAgeDays} days ago' : ''}.'),
        if (images.isNotEmpty) p('- ${images.length} screenshot(s) attached on the following page(s).'),
        if (unreadable.isNotEmpty) p('- Could not include: ${unreadable.join(', ')} (not a PNG or JPEG image).'),
        pw.SizedBox(height: 6),
        p('Kantoi is a scam-checking app. Its verdict is a guide, not proof; the evidence above is what it is based on.', style: muted),
      ]),
    ],
  ));

  for (final (name, img) in images0) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(pdfSafe('Evidence screenshot: $name'), style: h),
        pw.SizedBox(height: 10),
        pw.Expanded(child: pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain))),
      ]),
    ));
  }
  return doc.save();
}
