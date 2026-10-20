import 'package:flutter/material.dart';

import '../engine/forensics/hop_facts.dart' show flagFor;
import '../engine/models.dart';
import 'check/result_parts.dart';
import 'theme.dart';

const _red = K.red;
const _amber = Color(0xFFB45309);

/// Small lines under one hop of the link chain: where it is hosted and its
/// security certificate.
class HopFacts extends StatelessWidget {
  final UrlHop hop;
  const HopFacts(this.hop, {super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline);
    final lines = <(String, Color?)>[
      if (hop.via != null) ('Reached by a hidden ${hop.via}, not a normal redirect', _amber),
      if (hop.country != null || hop.network != null || hop.ip != null)
        ([
          if (hop.country != null) '${flagFor(hop.country)} ${hop.country}',
          if (hop.network != null) 'Hosted by ${hop.network}',
          if (hop.ip != null) hop.ip!,
        ].join(' · '), null),
      if (hop.tlsIssuer != null)
        (
          'Certificate from ${hop.tlsIssuer}${hop.tlsValidFrom == null ? '' : ', issued ${_ago(hop.tlsValidFrom!)}'}'
              '${hop.tlsTrusted == false ? ' (not trusted)' : ''}',
          hop.tlsTrusted == false || (hop.tlsValidFrom != null && DateTime.now().difference(hop.tlsValidFrom!).inDays <= 7) ? _red : null
        ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 26, top: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (text, color) in lines) Text(text, style: color == null ? style : style?.copyWith(color: color)),
      ]),
    );
  }
}

/// The deeper link results: page title, reputation hits, cloaking, and the
/// remote browser screenshot.
class LinkForensicsPanel extends StatelessWidget {
  final UrlReport report;
  const LinkForensicsPanel(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final u = report;
    final hasAny = u.pageTitle != null || u.reputationHits.isNotEmpty || u.cloaked == true || u.screenshotUrl != null || u.remoteVerdict != null;
    if (!hasAny) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (u.pageTitle != null) Text('Page title: "${u.pageTitle}"', style: t.bodySmall),
        for (final h in u.reputationHits)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.report_rounded, size: 16, color: _red),
              const SizedBox(width: 6),
              Expanded(child: Text(h, style: t.bodySmall?.copyWith(color: _red, fontWeight: FontWeight.w600))),
            ]),
          ),
        if (u.cloaked == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Shows different pages to phones and computers', style: t.bodySmall?.copyWith(color: _red, fontWeight: FontWeight.w600)),
          ),
        if (u.screenshotUrl != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Image.network(
                u.screenshotUrl!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => Container(
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Text('Screenshot not available yet.', style: t.bodySmall),
                ),
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Taken by a remote isolated browser (urlscan.io). The page never opened on your device.'
            '${u.remoteFinalUrl != null ? ' It ended at ${Uri.tryParse(u.remoteFinalUrl!)?.host ?? u.remoteFinalUrl}.' : ''}',
            style: t.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ] else if (u.remoteVerdict != null)
          Text(u.remoteVerdict!, style: t.bodySmall),
      ]),
    );
  }
}

/// A small stepper showing where a message sits in a known scam script.
class ScriptStepper extends StatelessWidget {
  final ScriptProgress progress;
  const ScriptStepper(this.progress, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = progress;
    const outline = K.outlineVariant;
    return ResultSection(
      icon: Icons.route_outlined,
      color: _red,
      title: 'Where this is in the scam script',
      subtitle: 'A typical ${p.script}',
      trailing: Text('Step ${p.stage + 1} of ${p.stages.length}', style: t.labelMedium?.copyWith(color: _red)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // A rail of numbered steps that fills up to this message.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: K.curve,
          builder: (_, v, _) => Row(children: [
            for (var i = 0; i < p.stages.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: i <= p.stage && v * p.stages.length >= i ? _red : outline,
                    ),
                  ),
                ),
              _StepDot(n: i + 1, state: i == p.stage ? 2 : (i < p.stage || p.matched.contains(i) ? 1 : 0)),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < p.stages.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: i == p.stage ? _red.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: i == p.stage ? Border.all(color: _red.withValues(alpha: 0.3)) : null,
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 22, child: Text('${i + 1}.', style: t.labelLarge?.copyWith(color: i <= p.stage ? _red : K.outline))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    p.stages[i],
                    style: t.bodyMedium?.copyWith(
                      fontWeight: i == p.stage ? FontWeight.w700 : null,
                      color: i > p.stage ? K.outline : K.onSurface,
                    ),
                  ),
                  if (i == p.stage) Text('This message', style: t.labelSmall?.copyWith(color: _red)),
                  if (i == p.stage + 1) Text('What usually comes next', style: t.labelSmall?.copyWith(color: K.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int n;
  final int state; // 0 ahead, 1 passed, 2 this message
  const _StepDot({required this.n, required this.state});
  @override
  Widget build(BuildContext context) => Container(
        width: state == 2 ? 30 : 24,
        height: state == 2 ? 30 : 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: state == 2 ? _red : (state == 1 ? _red.withValues(alpha: 0.15) : Colors.white),
          border: Border.all(color: state == 0 ? K.outlineVariant : _red, width: 1.5),
          boxShadow: state == 2 ? [BoxShadow(color: _red.withValues(alpha: 0.3), blurRadius: 8)] : null,
        ),
        child: Text('$n',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: state == 2 ? Colors.white : (state == 1 ? _red : K.outline))),
      );
}

String _ago(DateTime d) {
  final days = DateTime.now().difference(d).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return '1 day ago';
  if (days < 60) return '$days days ago';
  if (days < 730) return '${days ~/ 30} months ago';
  return '${days ~/ 365} years ago';
}
