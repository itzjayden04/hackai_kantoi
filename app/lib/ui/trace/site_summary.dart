import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../engine/models.dart';
import '../../engine/sitecheck/site_check.dart';
import '../kit.dart';
import '../theme.dart';

IconData purposeIcon(SitePurpose p) => switch (p) {
      SitePurpose.gambling => Icons.casino_outlined,
      SitePurpose.investment => Icons.trending_up_rounded,
      SitePurpose.moneyLending => Icons.request_quote_outlined,
      SitePurpose.fakeShop => Icons.shopping_bag_outlined,
      SitePurpose.phishing => Icons.phishing_rounded,
      SitePurpose.adult => Icons.no_adult_content_outlined,
      SitePurpose.piracy => Icons.movie_outlined,
      SitePurpose.jobScam => Icons.work_outline_rounded,
      SitePurpose.legitBrand => Icons.verified_outlined,
      SitePurpose.general => Icons.public_rounded,
      SitePurpose.unknown => Icons.help_outline_rounded,
    };

Color reputationColor(int? score) => score == null
    ? K.outline
    : score >= 60
        ? K.green
        : score >= 40
            ? K.amber
            : K.red;

/// The website's purpose badge and reputation, with the sources behind it.
/// [compact] keeps only the verdict, the warning signs and the reputation
/// score; the rest is one tap away behind the "i".
class SiteSummaryCard extends StatelessWidget {
  final SiteReport site;
  final bool compact;
  const SiteSummaryCard({super.key, required this.site, this.compact = false});

  /// Everything the compact card leaves out, as plain text for its "i".
  String _detail() => [
        site.purpose.explanation,
        '${basisLabel(site.purpose.basis)}, ${site.purpose.confidenceLabel.toLowerCase()} confidence.',
        site.reputationSummary,
        for (final s in site.sources) '${s.label}: ${s.detail}',
        if (site.fromCache) 'Saved result from the last 24 hours.',
        if (site.level == RiskLevel.safe && site.levelLabel != 'Low risk') "No warning signs found yet. That does not prove it's safe.",
      ].join('\n\n');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = site.purpose;
    final lvl = site.level;
    final c = riskColor(lvl);
    final score = site.reputationScore;
    final rc = reputationColor(score);
    final sources = site.sources;
    Widget label(String s) => Text(s.toUpperCase(), style: t.labelSmall?.copyWith(color: K.onSurfaceVariant, letterSpacing: 0.6, fontWeight: FontWeight.w700));
    return KCard(
      key: ValueKey('site-${site.domain}'),
      borderColor: p.risky ? c.withValues(alpha: 0.5) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: K.r16),
            child: Icon(purposeIcon(p.purpose), color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: label(compact ? site.domain : 'Purpose · ${site.domain}')),
                if (compact) InfoButton(title: site.domain, message: _detail()),
              ]),
              const SizedBox(height: 2),
              Text(p.headline, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: p.risky ? c : K.onSurface)),
              const SizedBox(height: 6),
              Pill(lvl == RiskLevel.safe && site.levelLabel != 'Low risk' ? 'No signs yet' : site.levelLabel, color: c, icon: riskIcon(lvl)),
            ]),
          ),
        ]),
        if (!compact) ...[const SizedBox(height: 10), Text(p.explanation, style: t.bodyMedium)],
        if (p.reasons.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final r in p.reasons.take(compact ? 2 : 3))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 6, right: 8), child: Icon(Icons.circle, size: 5, color: c)),
                Expanded(child: Text(r, style: t.bodySmall)),
              ]),
            ),
        ],
        if (!compact) ...[
        const SizedBox(height: 6),
        Row(children: [
          Icon(p.basis == PurposeBasis.ai || p.basis == PurposeBasis.web ? Icons.cloud_outlined : Icons.lock_outline_rounded, size: 14, color: K.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text('${basisLabel(p.basis)} · ${p.confidenceLabel.toLowerCase()} confidence', style: t.labelSmall?.copyWith(color: K.onSurfaceVariant))),
        ]),
        if (p.aiPurpose != null && p.aiPurpose != p.purpose) ...[
          const SizedBox(height: 4),
          Text('AI reading of the page: ${purposeLabel(p.aiPurpose!).toLowerCase()} (${((p.aiConfidence ?? 0) * 100).round()}% sure).',
              style: t.labelSmall?.copyWith(color: K.onSurfaceVariant)),
        ],
        ],
        Divider(height: compact ? 20 : 24),
        Row(children: [
          Expanded(child: label(compact ? 'Reputation' : 'Reputation across the internet')),
          Text(score == null ? 'Not checked' : '${site.reputationLabel} · $score/100', style: t.labelLarge?.copyWith(color: rc, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        KProgressBar(value: score == null ? 0 : score / 100, color: rc, height: 6),
        if (compact) const SizedBox(height: 4),
        if (!compact) ...[const SizedBox(height: 8), Text(site.reputationSummary, style: t.bodyMedium)],
        if (!compact && sources.isNotEmpty) ...[
          const SizedBox(height: 8),
          label('Sources'),
          for (final s in sources)
            InkWell(
              onTap: s.url == null ? null : () => launchUrl(Uri.parse(s.url!), mode: LaunchMode.externalApplication),
              borderRadius: K.r8,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                      s.tone > 0
                          ? Icons.thumb_up_alt_outlined
                          : s.tone < 0
                              ? Icons.report_gmailerrorred_outlined
                              : Icons.info_outline_rounded,
                      size: 16,
                      color: s.tone > 0 ? K.green : (s.tone < 0 ? K.red : K.outline)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.label, style: t.labelLarge),
                      Text(s.detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                    ]),
                  ),
                  if (s.url != null) const Icon(Icons.open_in_new_rounded, size: 16, color: K.primaryContainer),
                ]),
              ),
            ),
        ],
        if (!compact && site.fromCache) ...[
          const SizedBox(height: 4),
          Text('Saved result from the last 24 hours.', style: t.labelSmall?.copyWith(color: K.onSurfaceVariant)),
        ],
        if (!compact && lvl == RiskLevel.safe && site.levelLabel != 'Low risk') ...[
          const SizedBox(height: 4),
          Text("No warning signs found yet. That does not prove it's safe.", style: t.labelSmall?.copyWith(color: K.onSurfaceVariant)),
        ],
      ]),
    );
  }
}
