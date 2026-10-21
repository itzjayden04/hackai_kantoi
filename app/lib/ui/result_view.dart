import 'package:flutter/material.dart';

import '../engine/investigator.dart' show verdictLabel;
import '../engine/models.dart';
import '../engine/sitecheck/site_check.dart' show sitesOf;
import '../engine/webintel/web_intel.dart' show webIntelOf;
import '../engine/redaction.dart';
import '../state.dart';
import 'check/check_format.dart';
import 'check/result_parts.dart';
import 'trace/site_summary.dart';
import 'emergency_page.dart';
import 'explainer_card.dart';
import 'feedback_bar.dart';
import 'forensics_widgets.dart';
import 'guardian_ui.dart';
import 'intel_page.dart' show DemoBadge;
import 'kit.dart';
import 'limits_page.dart';
import 'report_page.dart';
import 'review_page.dart';
import 'theme.dart';
import 'warning_image.dart';
import 'webintel/web_evidence.dart';
import 'who_behind.dart';

/// The full result of one check: verdict, why, the scam script, where links
/// go, then the deeper details folded away. [inlineActions] puts the
/// Trace / Report / Warn family row in the page; screens that pin it to the
/// bottom instead pass false and show [ResultActionBar] themselves.
class ResultView extends StatelessWidget {
  final Investigation inv;
  final bool inlineActions;
  const ResultView({super.key, required this.inv, this.inlineActions = true});

  @override
  Widget build(BuildContext context) {
    final v = inv.verdict;
    final safe = v.level == RiskLevel.safe;
    final risky = v.level.index >= RiskLevel.suspicious.index;
    final web = webIntelOf(inv);
    final parts = <Widget>[
      VerdictCard(verdict: v, label: verdictLabel(v.level, inv.findings)),
      if (risky) _HelpRow(inv: inv),
      if (inlineActions) ResultActionBar(inv: inv),
      // What each linked website is for and how the internet rates it.
      for (final site in sitesOf(inv).take(2)) SiteSummaryCard(site: site),
      if (web.any((r) => r.reported)) WebEvidenceSection(results: web),
      _WhySection(inv: inv),
      if (web.isNotEmpty && !web.any((r) => r.reported)) WebEvidenceSection(results: web),
      if (safe) _FeedbackCard(inv: inv, calm: true),
      if (inv.script != null) ScriptStepper(inv.script!),
      for (final u in inv.urls) _LinkChain(u),
      ExplainerTile(inv: inv),
      if (inv.attribution != null)
        ExpandableSection(
          icon: Icons.hub_outlined,
          color: inv.attribution!.found ? K.red : K.primary,
          title: "Who's behind it",
          subtitle: inv.attribution!.found ? inv.attribution!.campaign?.label ?? 'Linked to known scam activity' : 'No known campaign matched',
          badge: inv.attribution!.demo ? const DemoBadge() : null,
          children: [WhoBehindBody(result: inv.attribution!)],
        ),
      _PrivacySection(inv: inv),
      ExpandableSection(
        icon: Icons.account_tree_outlined,
        title: 'How Kantoi checked this',
        subtitle: '${inv.log.length} steps, each marked on this phone or online',
        children: [PipelineView(steps: inv.log, finished: true)],
      ),
      ExpandableSection(
        icon: Icons.balance_outlined,
        title: 'Honest limits',
        subtitle: 'Best judgement, not a guarantee',
        children: [
          _Limits(v),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.info_outline_rounded),
                label: const Text("What Kantoi can't do"),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LimitsPage())),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Your feedback'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReviewQueuePage())),
              ),
            ],
          ),
        ],
      ),
      if (!safe) _FeedbackCard(inv: inv, calm: false),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, w) in parts.indexed)
          Reveal(
            index: i,
            child: Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
          ),
      ],
    );
  }
}

/// Big verdict card in the risk colour, with how sure Kantoi is and the one
/// thing to do now.
class VerdictCard extends StatelessWidget {
  final Verdict verdict;
  /// Overrides the level's name, e.g. "No warning signs found yet".
  final String? label;
  const VerdictCard({super.key, required this.verdict, this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = riskColor(verdict.level);
    // Warnings are loud (solid colour); safe and "be careful" stay calm.
    final loud = verdict.level.index >= RiskLevel.suspicious.index;
    final fg = loud ? Colors.white : c;
    final sub = loud ? Colors.white.withValues(alpha: 0.85) : K.onSurfaceVariant;
    final dark = Color.lerp(c, Colors.black, 0.22)!;
    return Container(
      decoration: BoxDecoration(
        gradient: loud ? LinearGradient(colors: [c, dark], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
        color: loud ? null : c.withValues(alpha: 0.07),
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: loud ? null : Border.all(color: c.withValues(alpha: 0.35)),
        boxShadow: loud ? [BoxShadow(color: c.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 6))] : null,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (loud ? Colors.white : c).withValues(alpha: loud ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'RISK SCORE ${verdict.score}/100',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: fg),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: (loud ? Colors.white : c).withValues(alpha: loud ? 0.18 : 0.12),
                  borderRadius: K.r16,
                ),
                child: Icon(riskIcon(verdict.level), color: fg, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label ?? riskLabel(verdict.level),
                      style: t.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w800, fontSize: 24),
                    ),
                    Text(
                      verdict.scamType,
                      style: t.bodyMedium?.copyWith(color: sub, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(verdict.headline, style: t.bodyLarge?.copyWith(color: loud ? Colors.white : K.onSurface, height: 1.4)),
          const SizedBox(height: 14),
          _ConfidenceBar(confidence: verdict.confidence, loud: loud, color: c),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(loud ? Icons.back_hand_outlined : Icons.arrow_forward_rounded, color: c, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    verdict.nextStep,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.35, color: K.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  final int confidence;
  final bool loud;
  final Color color;
  const _ConfidenceBar({required this.confidence, required this.loud, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = loud ? Colors.white : K.onSurface;
    final sub = loud ? Colors.white.withValues(alpha: 0.85) : K.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: loud ? Colors.black.withValues(alpha: 0.16) : Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, size: 16, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text('How sure Kantoi is', style: t.labelLarge?.copyWith(color: fg)),
              ),
              Text(
                '${confidenceWords(confidence)} · $confidence%',
                style: t.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: confidence / 100),
            duration: const Duration(milliseconds: 900),
            curve: K.curve,
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: loud ? Colors.white : color,
                backgroundColor: (loud ? Colors.white : color).withValues(alpha: 0.2),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            confidence >= 80
                ? 'Based on the evidence below. Kantoi can still be wrong.'
                : 'Kantoi found mixed or limited evidence, so treat this as a hint, not proof.',
            style: t.bodySmall?.copyWith(color: sub),
          ),
        ],
      ),
    );
  }
}

/// "Already paid or shared details?" straight under a warning verdict.
class _HelpRow extends StatelessWidget {
  final Investigation inv;
  const _HelpRow({required this.inv});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KCard(
          color: K.errorContainer.withValues(alpha: 0.45),
          borderColor: K.red.withValues(alpha: 0.25),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EmergencyPage(inv: inv))),
          child: Row(
            children: [
              const Icon(Icons.emergency_outlined, color: K.red),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'I already paid or shared details',
                  style: t.titleSmall?.copyWith(color: K.onErrorContainer, fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: K.red),
            ],
          ),
        ),
        if (inv.verdict.level == RiskLevel.danger)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: GuardianAlertButton(inv: inv),
            ),
          ),
      ],
    );
  }
}

/// Trace / Report / Warn family. Trace hands the best target to the Trace
/// tab and returns to the main screen if this result was opened on top.
class ResultActionBar extends StatelessWidget {
  final Investigation inv;

  /// Shown for safe results in place of Report and Warn family.
  final VoidCallback? onNew;
  const ResultActionBar({super.key, required this.inv, this.onNew});

  void _trace(BuildContext context) {
    final nav = Navigator.of(context);
    appState.openTrace(traceTarget(inv));
    if (nav.canPop()) nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final safe = inv.verdict.level == RiskLevel.safe;
    const pad = EdgeInsets.symmetric(horizontal: 8);
    const text = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600);
    Widget label(String s) => FittedBox(fit: BoxFit.scaleDown, child: Text(s, maxLines: 1));
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(padding: pad, textStyle: text),
            icon: const Icon(Icons.hub_outlined, size: 20),
            label: label('Trace'),
            onPressed: () => _trace(context),
          ),
        ),
        if (!safe) ...[
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(padding: pad, textStyle: text, foregroundColor: K.onErrorContainer, backgroundColor: K.errorContainer),
              icon: const Icon(Icons.flag_outlined, size: 20),
              label: label('Report'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportPage(inv: inv))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(padding: pad, textStyle: text),
              icon: const Icon(Icons.share_outlined, size: 20),
              label: label('Warn family'),
              onPressed: () => showWarnFamily(context, inv, shareWarning(inv)),
            ),
          ),
        ] else if (onNew != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), padding: pad, textStyle: text),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: label('New check'),
              onPressed: onNew,
            ),
          ),
        ],
      ],
    );
  }
}

/// [ResultActionBar] pinned to the bottom of a screen on a frosted strip.
class StickyActions extends StatelessWidget {
  final Investigation inv;
  final VoidCallback? onNew;
  final double bottomInset;
  const StickyActions({super.key, required this.inv, this.onNew, this.bottomInset = 0});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.96),
      border: Border(top: BorderSide(color: K.outlineVariant.withValues(alpha: 0.5))),
      boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2))],
    ),
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ResultActionBar(inv: inv, onNew: onNew),
      ),
    ),
  );
}

String shareWarning(Investigation inv) {
  final v = inv.verdict;
  final cues = inv.findings.where((f) => f.isRisk).map((f) => f.title).toSet().take(3).join(', ');
  return 'Scam alert from Kantoi: ${riskLabel(v.level)} (${v.scamType}).\n'
      '${v.headline}\n'
      '${cues.isEmpty ? '' : 'Warning signs: $cues.\n'}'
      'What to do: ${v.nextStep}';
}

/// "Why Kantoi flagged this": the message with the telling words marked,
/// then each cue numbered.
class _WhySection extends StatelessWidget {
  final Investigation inv;
  const _WhySection({required this.inv});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final safe = inv.verdict.level == RiskLevel.safe;
    // "Genuine" only when there is a real sign of it, not just no warnings.
    final genuine = safe && inv.findings.any((f) => !f.isRisk);
    final risks = inv.findings.where((f) => f.isRisk).toList()..sort((a, b) => b.weight.compareTo(a.weight));
    final legit = inv.findings.where((f) => !f.isRisk).toList()..sort((a, b) => a.weight.compareTo(b.weight));
    // One entry per cue type keeps the list short; the strongest example wins.
    final seen = <String>{};
    final topRisks = risks.where((f) => seen.add(f.title)).take(6).toList();
    final topLegit = legit.where((f) => seen.add(f.title)).take(3).toList();
    final main = safe ? topLegit : topRisks;
    final other = safe ? topRisks : topLegit;
    final detail = sourceDetail(inv);
    final c = riskColor(inv.verdict.level);
    return ResultSection(
      icon: genuine ? Icons.verified_outlined : Icons.policy_outlined,
      color: genuine ? K.green : K.primary,
      title: genuine ? 'Why Kantoi thinks it is genuine' : safe ? 'What Kantoi found' : 'Why Kantoi flagged this',
      trailing: safe || topRisks.isEmpty ? null : Pill('${topRisks.length} red flag${topRisks.length == 1 ? '' : 's'}', color: K.red),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: K.surfaceLow, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(sourceIcon(inv.artefact), size: 16, color: K.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [sourceLabel(inv.artefact), ?detail].join(' · '),
                        style: t.labelMedium?.copyWith(color: K.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(riskIcon(inv.verdict.level), size: 14, color: c),
                    const SizedBox(width: 4),
                    Text(verdictLabel(inv.verdict.level, inv.findings), style: t.labelMedium?.copyWith(color: c)),
                  ],
                ),
                const SizedBox(height: 10),
                HighlightedText(text: inv.artefact.text, findings: inv.findings, boxed: false),
              ],
            ),
          ),
          if (main.isEmpty && other.isEmpty) ...[
            const SizedBox(height: 12),
            Text("Kantoi found no warning signs yet and no clear signs it is genuine. That does not prove it's safe.", style: t.bodyMedium),
          ],
          for (final (i, f) in main.indexed) ...[const SizedBox(height: 10), CueTile(f, number: i + 1)],
          if (other.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(safe ? 'Small things to keep in mind' : 'Signs in its favour', style: t.labelLarge?.copyWith(color: K.onSurfaceVariant)),
            for (final f in other) ...[const SizedBox(height: 8), CueTile(f)],
          ],
        ],
      ),
    );
  }
}

/// One explainable cue: number, title, its kind, the reason, and the tool
/// that found it.
class CueTile extends StatelessWidget {
  final Finding f;
  final int? number;
  const CueTile(this.f, {super.key, this.number});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = f.isRisk ? K.red : K.green;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: K.surfaceLow.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: number == null ? c.withValues(alpha: 0.12) : c),
            child: number == null
                ? Icon(f.isRisk ? Icons.priority_high_rounded : Icons.check_rounded, size: 14, color: c)
                : Text(
                    '$number',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(f.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(cueLabel(f.category), style: t.labelSmall?.copyWith(color: c)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(f.explanation, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text('Found by: ${f.tool}', style: t.labelSmall?.copyWith(color: K.outline)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The original message with the words behind each cue highlighted.
class HighlightedText extends StatelessWidget {
  final String text;
  final List<Finding> findings;
  final bool boxed;
  const HighlightedText({super.key, required this.text, required this.findings, this.boxed = true});

  @override
  Widget build(BuildContext context) {
    final spans = findings.where((f) => f.start != null && f.end != null && f.end! > f.start! && f.end! <= text.length).toList()
      ..sort((a, b) => a.start!.compareTo(b.start!));
    final out = <InlineSpan>[];
    var pos = 0;
    for (final f in spans) {
      if (f.start! < pos) continue;
      out.add(TextSpan(text: text.substring(pos, f.start!)));
      final c = f.isRisk ? K.red : K.green;
      out.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Tooltip(
            message: '${cueLabel(f.category)}: ${f.explanation}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
                border: Border(bottom: BorderSide(color: c, width: 2)),
              ),
              child: Text(
                text.substring(f.start!, f.end!),
                style: TextStyle(fontSize: 15, height: 1.5, color: f.isRisk ? K.onErrorContainer : K.green, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      );
      pos = f.end!;
    }
    out.add(TextSpan(text: text.substring(pos)));
    final body = SelectableText.rich(
      TextSpan(
        style: const TextStyle(fontSize: 15, height: 1.5, color: K.onSurface),
        children: out,
      ),
    );
    if (!boxed) return body;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: K.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: body,
    );
  }
}

/// Where a link really goes: each hop in order, then what Kantoi learned.
class _LinkChain extends StatelessWidget {
  final UrlReport u;
  const _LinkChain(this.u);
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final bad = u.imitates != null || u.reputationHits.isNotEmpty || u.cloaked == true;
    return ResultSection(
      icon: Icons.alt_route_rounded,
      title: 'Where the link really goes',
      subtitle: u.hops.length > 1 ? '${u.hops.length} stops, checked without opening it on your phone' : 'Checked without opening it on your phone',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < u.hops.length; i++) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: K.surfaceLow,
                borderRadius: BorderRadius.circular(12),
                border: i == u.hops.length - 1 && bad ? Border.all(color: K.red.withValues(alpha: 0.4)) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (i == u.hops.length - 1 && bad ? K.red : K.primary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'H${i + 1}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: i == u.hops.length - 1 && bad ? K.red : K.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          u.hops[i].url,
                          style: t.bodySmall?.copyWith(fontFamily: 'monospace', color: K.onSurface),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (u.hops[i].status != null) ...[const SizedBox(width: 6), Text('${u.hops[i].status}', style: t.labelSmall)],
                    ],
                  ),
                  HopFacts(u.hops[i]),
                ],
              ),
            ),
            if (i < u.hops.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Icon(Icons.arrow_downward_rounded, size: 18, color: K.outline),
              ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (u.official)
                const Tag('Official website', color: K.green, icon: Icons.verified_outlined)
              else if (u.imitates != null)
                Tag('Imitates ${u.imitates}', color: K.red, icon: Icons.content_copy_rounded)
              else
                Tag(u.host, color: K.onSurfaceVariant),
              if (u.domainAgeDays != null)
                Tag('Registered ${u.domainAgeDays} days ago', color: u.domainAgeDays! < 30 ? K.red : K.onSurfaceVariant, icon: Icons.event_outlined),
              if (u.registrar != null) Tag('Registrar: ${u.registrar}', color: K.onSurfaceVariant),
            ],
          ),
          LinkForensicsPanel(u),
        ],
      ),
    );
  }
}

/// What left the phone during this check, and the masked copy the AI saw.
class _PrivacySection extends StatelessWidget {
  final Investigation inv;
  const _PrivacySection({required this.inv});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final online = inv.log.where((s) => s.sentOffDevice && s.status != StepStatus.skipped).toList();
    final aiSaw = online.any((s) => s.tool.toLowerCase().startsWith('ai '));
    // Same masking the investigation used before asking the AI.
    final pii = findPii(
      inv.artefact.text,
      ownValues: appState.ownDetails,
    ).where((p) => p.type == PiiType.ic || p.type == PiiType.card || p.type == PiiType.address || p.type == PiiType.name).toList();
    return ExpandableSection(
      icon: online.isEmpty ? Icons.lock_outline_rounded : Icons.cloud_outlined,
      color: K.green,
      title: 'Your privacy',
      subtitle: online.isEmpty
          ? 'Everything ran on this phone'
          : '${online.length} step${online.length == 1 ? '' : 's'} went online, personal details hidden',
      children: [
        if (online.isEmpty)
          Text('Nothing from this check left your phone.', style: t.bodyMedium)
        else ...[
          Text('These steps contacted an online service:', style: t.bodyMedium),
          const SizedBox(height: 6),
          for (final s in online)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.cloud_outlined, size: 16, color: K.outline),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${s.tool}: ${s.action}', style: t.bodySmall)),
                ],
              ),
            ),
        ],
        if (aiSaw) ...[
          const SizedBox(height: 10),
          Text(
            pii.isEmpty ? 'The AI saw the message as is (no IC, card, address or name found).' : 'What the AI saw, with your details masked:',
            style: t.labelLarge,
          ),
          if (pii.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: K.surfaceLow, borderRadius: BorderRadius.circular(12)),
              child: Text(redact(inv.artefact.text, pii), style: t.bodySmall?.copyWith(color: K.onSurface)),
            ),
          ],
        ],
        const SizedBox(height: 8),
        Text('When you report, you choose what to mask before anything is shared.', style: t.bodySmall),
      ],
    );
  }
}

/// "Was this wrong?" feedback. Calm and up front for a safe result, so a
/// missed scam is easy to flag.
class _FeedbackCard extends StatelessWidget {
  final Investigation inv;
  final bool calm;
  const _FeedbackCard({required this.inv, required this.calm});
  @override
  Widget build(BuildContext context) => KCard(
    color: calm ? K.green.withValues(alpha: 0.05) : K.surfaceLow,
    borderColor: calm ? K.green.withValues(alpha: 0.25) : Colors.transparent,
    child: FeedbackBar(key: ObjectKey(inv), inv: inv, prompt: calm ? 'Was this wrong?' : 'Was Kantoi wrong?'),
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
        if (v.whatWouldChange.isNotEmpty) 'What would change this: ${v.whatWouldChange.join('; ')}.',
      ].join(' '),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}
