/// The trace written up for the police or a bank: a PDF and a plain-text
/// version to share.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models.dart';
import '../pdf_report.dart' show pdfSafe;
import '../sitecheck/site_check.dart';
import 'trace_models.dart';
import 'tracer.dart' show semakMuleUrl;

String _fmt(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String _status(LogStep s) => switch (s.status) {
      StepStatus.done => 'done',
      StepStatus.failed => 'failed',
      StepStatus.skipped => 'skipped',
      StepStatus.running => 'running',
    };

/// Purpose and reputation of one website, as label/value rows.
List<(String, String)> siteRows(SiteReport r) => [
      ('Website', r.domain),
      ('Purpose', '${r.purpose.headline} (${r.purpose.confidenceLabel.toLowerCase()} confidence, from ${basisLabel(r.purpose.basis).toLowerCase()})'),
      ('Why it matters', r.purpose.explanation),
      if (r.purpose.reasons.isNotEmpty) ('Evidence', r.purpose.reasons.join('; ')),
      if (r.purpose.aiPurpose != null) ('AI reading', '${purposeLabel(r.purpose.aiPurpose!)} (${((r.purpose.aiConfidence ?? 0) * 100).round()}% sure)'),
      ('Risk from the site', r.levelLabel),
      ('Reputation', r.reputationScore == null ? 'Not checked' : '${r.reputationLabel} (${r.reputationScore}/100)'),
      ('Reputation summary', r.reputationSummary),
      for (final x in r.sources) ('Source: ${x.label}', '${x.detail}${x.url == null ? '' : ' - ${x.url}'}'),
    ];

/// Nodes grouped by kind, origin first.
List<(TraceKind, List<TraceNode>)> traceGroups(TraceState s) {
  final out = <(TraceKind, List<TraceNode>)>[];
  for (final k in TraceKind.values) {
    final ns = s.nodes.values.where((n) => n.kind == k).toList();
    if (ns.isNotEmpty) out.add((k, ns));
  }
  return out;
}

String traceSummaryText(TraceState s) {
  final b = StringBuffer()
    ..writeln('Kantoi trace: ${s.target}')
    ..writeln('Started ${s.startedAt == null ? '-' : _fmt(s.startedAt!)}${s.finished ? '' : ' (still running)'}')
    ..writeln('Warning level: ${s.riskLabel} (${s.score}/100 from the signs below)')
    ..writeln('Countries: ${s.countries.isEmpty ? 'none found' : s.countries.map(countryName).join(', ')}')
    ..writeln();
  for (final site in s.sites) {
    b.writeln('Website purpose and reputation:');
    for (final (k, v) in siteRows(site)) {
      b.writeln('  $k: $v');
    }
    b.writeln();
  }
  final risks = s.flags.where((f) => f.isRisk).toList();
  if (risks.isNotEmpty) {
    b.writeln('Warning signs:');
    for (final f in risks) {
      b.writeln('- ${f.title}: ${f.why}');
    }
    b.writeln();
  }
  final good = s.flags.where((f) => !f.isRisk).toList();
  if (good.isNotEmpty) {
    b.writeln('Reassuring signs:');
    for (final f in good) {
      b.writeln('- ${f.title}: ${f.why}');
    }
    b.writeln();
  }
  b.writeln('What was found:');
  for (final (k, ns) in traceGroups(s)) {
    for (final n in ns) {
      b.writeln('- ${traceKindLabel(k)}: ${n.label}${n.demo ? ' (demo data)' : ''}');
      for (final (fk, fv) in n.facts) {
        b.writeln('    $fk: $fv');
      }
    }
  }
  b
    ..writeln()
    ..writeln('Lookups (lock = on the phone, cloud = online):');
  for (final l in s.lookups) {
    b.writeln('${_fmt(l.step.at)} [${l.online ? 'online' : 'on phone'}] ${l.step.tool}: ${l.step.action} -> ${l.step.result} (${_status(l.step)})');
  }
  b
    ..writeln()
    ..writeln('Kantoi used public, passive lookups only. Check bank accounts and numbers yourself on Semak Mule: $semakMuleUrl')
    ..writeln('If you lost money, call the National Scam Response Centre at 997 now.');
  if (s.hasDemo) b.writeln('Items marked "demo data" are made-up examples, not real reports.');
  return b.toString();
}

Future<Uint8List> buildTracePdf(TraceState s, {DateTime? now}) async {
  final doc = pw.Document(title: 'Scam trace', author: 'Kantoi', creator: 'Kantoi');
  const accent = PdfColor.fromInt(0xFF1E3A8A);
  final h = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: accent);
  const body = pw.TextStyle(fontSize: 10, lineSpacing: 2);
  final muted = pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700);
  pw.Widget p(String x, {pw.TextStyle? style}) => pw.Text(pdfSafe(x), style: style ?? body);
  pw.Widget section(String title, List<pw.Widget> children) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(height: 12),
        pw.Text(pdfSafe(title), style: h),
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
        ...children,
      ]);
  pw.Widget table(List<(String, String)> rows) => pw.Table(columnWidths: {0: const pw.FixedColumnWidth(150), 1: const pw.FlexColumnWidth()}, children: [
        for (final (k, v) in rows)
          pw.TableRow(children: [
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Text(pdfSafe(k), style: body.copyWith(fontWeight: pw.FontWeight.bold))),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: p(v)),
          ]),
      ]);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight, child: pw.Text('Kantoi trace - page ${c.pageNumber} of ${c.pagesCount}', style: muted)),
    build: (c) => [
      pw.Text('Scam trace report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: accent)),
      pw.SizedBox(height: 4),
      p('Prepared with Kantoi on ${_fmt(now ?? DateTime.now())}. Attach it to your police report or bank dispute.', style: muted),
      section('What was traced', [
        table([
          ('Target', s.target),
          ('Type', s.kind),
          ('Started', s.startedAt == null ? '-' : _fmt(s.startedAt!)),
          ('Status', s.finished ? (s.cancelled ? 'Stopped early' : 'Finished') : 'Still running when exported'),
          ('Warning level', '${s.riskLabel} (${s.score}/100 from the signs below)'),
          ('Items found', '${s.entityCount}'),
          ('Countries', s.countries.isEmpty ? 'None found' : s.countries.map(countryName).join(', ')),
        ]),
      ]),
      for (final site in s.sites) section('Website purpose and reputation: ${site.domain}', [table(siteRows(site))]),
      if (s.flags.isNotEmpty)
        section('Signs found', [
          for (final f in s.flags) p('${f.isRisk ? '[!]' : '[ok]'} ${f.title}: ${f.why}'),
        ]),
      section('What was found', [
        for (final (k, ns) in traceGroups(s))
          for (final n in ns) ...[
            pw.SizedBox(height: 4),
            p('${traceKindLabel(k)}: ${n.label}${n.demo ? ' (demo data, not a real report)' : ''}', style: body.copyWith(fontWeight: pw.FontWeight.bold)),
            if (n.facts.isNotEmpty) table(n.facts),
          ],
      ]),
      section('Lookup log', [
        for (final l in s.lookups)
          p('${_fmt(l.step.at)}  ${l.online ? 'ONLINE' : 'ON PHONE'}  ${l.step.tool}: ${l.step.action}. Result: ${l.step.result} (${_status(l.step)})',
              style: muted),
      ]),
      section('Notes', [
        p('Kantoi used public, passive lookups only (domain registry, DNS, certificate logs, IP registries). It did not scan, log in to or attack any system.'),
        p('Bank accounts and phone numbers can be checked on the police Semak Mule service: $semakMuleUrl'),
        p('If you lost money, call the National Scam Response Centre at 997 as soon as possible.'),
        if (s.hasDemo) p('Items marked "demo data" are made-up examples bundled with the app, not real reports.'),
      ]),
    ],
  ));
  return doc.save();
}
