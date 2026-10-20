import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/models.dart';
import 'activity_log.dart';
import 'emergency_page.dart';
import 'forensics_widgets.dart';
import 'report_page.dart';
import 'theme.dart';

class ResultView extends StatelessWidget {
  final Investigation inv;
  const ResultView({super.key, required this.inv});

  @override
  Widget build(BuildContext context) {
    final v = inv.verdict;
    final risks = inv.findings.where((f) => f.isRisk).toList()..sort((a, b) => b.weight.compareTo(a.weight));
    final legit = inv.findings.where((f) => !f.isRisk).toList();
    // One card per cue type keeps the list short; the strongest example wins.
    final seen = <String>{};
    final topRisks = risks.where((f) => seen.add(f.title)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      VerdictCard(verdict: v),
      const SizedBox(height: 12),
      _Actions(inv: inv),
      if (topRisks.isNotEmpty || legit.isNotEmpty) ...[
        const SectionTitle('Why'),
        HighlightedText(text: inv.artefact.text, findings: inv.findings),
        const SizedBox(height: 12),
        for (final f in topRisks.take(6)) _CueTile(f),
        for (final f in legit.take(3)) _CueTile(f),
      ],
      if (inv.script != null) ...[
        const SectionTitle('Where this is in the scam script'),
        ScriptStepper(inv.script!),
      ],
      if (inv.urls.isNotEmpty) ...[
        const SectionTitle('Where the link really goes'),
        for (final u in inv.urls) _LinkChain(u),
      ],
      SectionTitle('How Kantoi checked', trailing: Text('${inv.log.length} steps', style: Theme.of(context).textTheme.bodySmall)),
      ActivityLog(steps: inv.log),
      const SectionTitle('Honest limits'),
      _Limits(v),
    ]);
  }
}

class VerdictCard extends StatelessWidget {
  final Verdict verdict;
  const VerdictCard({super.key, required this.verdict});

  @override
  Widget build(BuildContext context) {
    final c = riskColor(verdict.level);
    final t = Theme.of(context).textTheme;
    return Card(
      color: c.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: c.withValues(alpha: 0.5), width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(riskIcon(verdict.level), color: c, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(riskLabel(verdict.level), style: t.headlineSmall?.copyWith(color: c, fontWeight: FontWeight.w800)),
                Text(verdict.scamType, style: t.bodyMedium?.copyWith(color: c)),
              ]),
            ),
            _ScoreRing(score: verdict.score, color: c),
          ]),
          const SizedBox(height: 14),
          Text(verdict.headline, style: t.titleMedium?.copyWith(height: 1.35)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.arrow_forward_rounded, color: c),
              const SizedBox(width: 10),
              Expanded(child: Text(verdict.nextStep, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.35))),
            ]),
          ),
          const SizedBox(height: 10),
          Text('Confidence ${verdict.confidence}%${verdict.whatWouldChange.isNotEmpty ? '. ${verdict.whatWouldChange.first}' : ''}',
              style: t.bodySmall),
        ]),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final int score;
  final Color color;
  const _ScoreRing({required this.score, required this.color});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 62,
        height: 62,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 6,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$score', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text('risk', style: TextStyle(fontSize: 10, color: color)),
          ]),
        ]),
      );
}

class _Actions extends StatelessWidget {
  final Investigation inv;
  const _Actions({required this.inv});
  @override
  Widget build(BuildContext context) {
    final risky = inv.verdict.level.index >= RiskLevel.suspicious.index;
    return Wrap(spacing: 10, runSpacing: 10, children: [
      if (risky)
        FilledButton.icon(
          icon: const Icon(Icons.flag_rounded),
          label: const Text('Report it'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportPage(inv: inv))),
        ),
      FilledButton.tonalIcon(
        style: FilledButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
        icon: const Icon(Icons.emergency_rounded),
        label: const Text('I already paid or shared details'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EmergencyPage(inv: inv))),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.share_rounded),
        label: const Text('Warn family'),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: shareWarning(inv)));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Warning copied. Paste it into your family chat.')));
        },
      ),
    ]);
  }
}

String shareWarning(Investigation inv) {
  final v = inv.verdict;
  final cues = inv.findings.where((f) => f.isRisk).map((f) => f.title).toSet().take(3).join(', ');
  return 'Scam alert from Kantoi: ${riskLabel(v.level)} (${v.scamType}).\n'
      '${v.headline}\n'
      '${cues.isEmpty ? '' : 'Warning signs: $cues.\n'}'
      'What to do: ${v.nextStep}';
}

/// The original message with the words behind each cue highlighted.
class HighlightedText extends StatelessWidget {
  final String text;
  final List<Finding> findings;
  const HighlightedText({super.key, required this.text, required this.findings});

  @override
  Widget build(BuildContext context) {
    final spans = findings.where((f) => f.start != null && f.end != null && f.end! > f.start! && f.end! <= text.length).toList()
      ..sort((a, b) => a.start!.compareTo(b.start!));
    final out = <InlineSpan>[];
    var pos = 0;
    for (final f in spans) {
      if (f.start! < pos) continue;
      out.add(TextSpan(text: text.substring(pos, f.start!)));
      final c = f.isRisk ? const Color(0xFFDC2626) : const Color(0xFF15803D);
      out.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Tooltip(
          message: '${cueLabel(f.category)}: ${f.explanation}',
          child: Container(
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              border: Border(bottom: BorderSide(color: c, width: 2)),
            ),
            child: Text(text.substring(f.start!, f.end!), style: const TextStyle(fontSize: 15, height: 1.5)),
          ),
        ),
      ));
      pos = f.end!;
    }
    out.add(TextSpan(text: text.substring(pos)));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText.rich(TextSpan(style: const TextStyle(fontSize: 15, height: 1.5), children: out)),
      ),
    );
  }
}

class _CueTile extends StatelessWidget {
  final Finding f;
  const _CueTile(this.f);
  @override
  Widget build(BuildContext context) {
    final c = f.isRisk ? const Color(0xFFDC2626) : const Color(0xFF15803D);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(f.isRisk ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: c, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(f.explanation, style: Theme.of(context).textTheme.bodyMedium),
            Text('Found by: ${f.tool}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
      ]),
    );
  }
}

class _LinkChain extends StatelessWidget {
  final UrlReport u;
  const _LinkChain(this.u);
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < u.hops.length; i++) ...[
            Row(children: [
              Icon(i == u.hops.length - 1 ? Icons.flag_rounded : Icons.subdirectory_arrow_right_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(u.hops[i].url, style: t.bodyMedium?.copyWith(fontFamily: 'monospace'), maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (u.hops[i].status != null) Text('${u.hops[i].status}', style: t.labelSmall),
            ]),
            HopFacts(u.hops[i]),
            if (i < u.hops.length - 1) const SizedBox(height: 6),
          ],
          const Divider(height: 20),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(context, u.official ? 'Official website' : u.imitates != null ? 'Imitates ${u.imitates}' : u.host,
                u.official ? const Color(0xFF15803D) : u.imitates != null ? const Color(0xFFDC2626) : null),
            if (u.domainAgeDays != null)
              _chip(context, 'Registered ${u.domainAgeDays} days ago', u.domainAgeDays! < 30 ? const Color(0xFFDC2626) : null),
            if (u.registrar != null) _chip(context, 'Registrar: ${u.registrar}', null),
          ]),
          LinkForensicsPanel(u),
        ]),
      ),
    );
  }

  Widget _chip(BuildContext context, String s, Color? c) => Chip(
        label: Text(s),
        labelStyle: TextStyle(color: c, fontWeight: c == null ? null : FontWeight.w600),
        side: BorderSide(color: c ?? Theme.of(context).colorScheme.outlineVariant),
        visualDensity: VisualDensity.compact,
      );
}

class _Limits extends StatelessWidget {
  final Verdict v;
  const _Limits(this.v);
  @override
  Widget build(BuildContext context) {
    return Text(
      [
        'Kantoi gives its best judgement, not a guarantee.',
        if (v.notChecked.isNotEmpty) 'Not checked: ${v.notChecked.join('; ')}.',
        if (v.whatWouldChange.length > 1) 'What would change this: ${v.whatWouldChange.skip(1).join('; ')}.',
      ].join(' '),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
