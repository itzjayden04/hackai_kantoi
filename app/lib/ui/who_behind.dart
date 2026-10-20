import 'package:flutter/material.dart';

import '../engine/attribution/graph.dart' show shortDate;
import '../engine/attribution/intel_models.dart';
import 'check/result_parts.dart';
import 'intel_graph_view.dart';
import 'intel_page.dart' show CampaignPage, DemoBadge;
import 'theme.dart';

/// "Who's behind it" with its own title, for screens that show it open.
class WhoBehindSection extends StatelessWidget {
  final AttributionResult result;
  const WhoBehindSection({super.key, required this.result});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle("Who's behind it", trailing: result.found && result.demo ? const DemoBadge() : null),
        if (result.found) Card(child: Padding(padding: const EdgeInsets.all(16), child: WhoBehindBody(result: result))) else WhoBehindBody(result: result),
      ]);
}

/// The campaign this check is linked to, how sure Kantoi is, and a way
/// into the network.
class WhoBehindBody extends StatelessWidget {
  final AttributionResult result;
  const WhoBehindBody({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = result;
    if (!r.found) {
      return Text('Nothing here matches a known scam campaign in Kantoi\'s database yet. That does not prove it is safe.', style: t.bodyMedium);
    }
    final c = r.campaign;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.hub_rounded, color: K.red),
        const SizedBox(width: 10),
        Expanded(child: Text(r.sentence, style: t.titleSmall?.copyWith(height: 1.35))),
      ]),
      if (c != null) ...[
        const SizedBox(height: 12),
        Row(children: [
          Text('How sure', style: t.labelMedium),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: r.confidence, minHeight: 8, color: K.red, backgroundColor: K.red.withValues(alpha: 0.12)),
            ),
          ),
          const SizedBox(width: 10),
          Text('${(r.confidence * 100).round()}%', style: t.labelLarge),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Tag('${c.domains} websites', color: K.onSurfaceVariant),
          Tag('${c.reports.length} reports', color: K.onSurfaceVariant),
          Tag('First seen ${shortDate(c.firstSeen)}', color: K.onSurfaceVariant),
          for (final x in c.targets.take(2)) Tag('Targets: $x', color: K.onSurfaceVariant),
        ]),
      ],
      const SizedBox(height: 12),
      Text('Why Kantoi links them', style: t.labelLarge),
      for (final m in r.matches.take(3))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('• ${m.via == null ? '' : '${edgeLabel(m.via!)}: '}${m.why}', style: t.bodySmall),
        ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('Show the network'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IntelGraphPage(graph: r.graph, title: c?.label ?? 'Scam network'))),
        ),
        if (c != null)
          OutlinedButton.icon(
            icon: const Icon(Icons.info_outline_rounded),
            label: const Text('Campaign details'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CampaignPage(campaign: c))),
          ),
      ]),
      const SizedBox(height: 8),
      Text('Kantoi links websites, numbers and accounts, never people. Account owners are not shown.', style: t.bodySmall),
    ]);
  }
}
