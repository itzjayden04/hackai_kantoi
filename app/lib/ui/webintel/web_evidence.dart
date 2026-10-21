import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../engine/attribution/graph.dart' show shortDate;
import '../../engine/webintel/web_intel.dart';
import '../check/result_parts.dart';
import '../kit.dart';
import '../theme.dart';

/// "Found online": what public web pages say about the numbers, accounts and
/// emails in the item, with each source the user can open. Nothing found is
/// shown as "no public reports", never as safe.
class WebEvidenceSection extends StatelessWidget {
  final List<WebIntelResult> results;
  const WebEvidenceSection({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    final reported = results.where((r) => r.reported).toList();
    final possible = results.any((r) => r.status == WebStatus.possible);
    final color = reported.isNotEmpty ? K.red : possible ? K.amber : K.primary;
    final sites = {for (final r in reported) ...r.confirmedDomains};
    return ResultSection(
      icon: Icons.travel_explore_rounded,
      color: color,
      title: reported.isNotEmpty ? 'Found online' : 'Searched online',
      subtitle: reported.isNotEmpty
          ? 'Reported as a scam on ${sites.length} public site${sites.length == 1 ? '' : 's'}'
          : 'Public web pages about the numbers, accounts and emails in it',
      trailing: reported.isNotEmpty ? Pill('${sites.length} source${sites.length == 1 ? '' : 's'}', color: K.red) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, r) in results.indexed) ...[
            if (i > 0) const Divider(height: 24),
            _ResultBlock(r),
          ],
        ],
      ),
    );
  }
}

class _ResultBlock extends StatelessWidget {
  final WebIntelResult r;
  const _ResultBlock(this.r);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (color, icon) = switch (r.status) {
      WebStatus.reported => (K.red, Icons.report_rounded),
      WebStatus.possible => (K.amber, Icons.help_outline_rounded),
      WebStatus.noReports => (K.onSurfaceVariant, Icons.search_off_rounded),
      WebStatus.unavailable => (K.outline, Icons.cloud_off_outlined),
      WebStatus.skipped => (K.outline, Icons.lock_outline_rounded),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(r.identifier.display, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          ],
        ),
        const SizedBox(height: 4),
        Text(r.headline, style: t.bodyMedium?.copyWith(color: r.reported ? K.onErrorContainer : K.onSurface)),
        if (r.summary != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: K.surfaceLow, borderRadius: BorderRadius.circular(10)),
            child: Text('AI summary of the search results: ${r.summary}', style: t.bodySmall?.copyWith(color: K.onSurface)),
          ),
        ],
        for (final s in r.sources) ...[const SizedBox(height: 8), WebSourceTile(s)],
        const SizedBox(height: 8),
        Text(
          [
            if (r.methods.isNotEmpty) 'Searched with ${r.methods.join(', ')}',
            'on ${shortDate(r.checkedAt)}${r.fromCache ? ' (saved result, kept 24 h)' : ''}',
          ].join(' '),
          style: t.labelSmall?.copyWith(color: K.outline),
        ),
      ],
    );
  }
}

/// One page as evidence: title, site, what it says, how it was checked.
/// Tapping opens it in the browser.
class WebSourceTile extends StatelessWidget {
  final WebSource s;
  const WebSourceTile(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = s.confirmed ? K.red : K.amber;
    return KCard(
      padding: const EdgeInsets.all(12),
      color: K.surfaceLow.withValues(alpha: 0.6),
      borderColor: c.withValues(alpha: 0.25),
      onTap: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public_rounded, size: 16, color: c),
              const SizedBox(width: 6),
              Expanded(
                child: Text(s.domain, style: t.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.open_in_new_rounded, size: 16, color: K.outline),
            ],
          ),
          const SizedBox(height: 4),
          Text(s.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (s.snippet.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('"${s.snippet}"', style: t.bodySmall?.copyWith(color: K.onSurfaceVariant), maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 6),
          Text('${s.evidenceLabel} · via ${s.foundVia}', style: t.labelSmall?.copyWith(color: K.outline)),
        ],
      ),
    );
  }
}
