import 'package:flutter/material.dart';

import '../engine/attribution/graph.dart' show shortDate;
import '../engine/attribution/intel_models.dart';
import 'intel_graph_view.dart';
import 'intel_page.dart' show CampaignPage, DemoBadge;
import 'theme.dart';

/// "Who's behind it": the campaign this check is linked to, how sure Kantoi
/// is, and a way into the network.
class WhoBehindSection extends StatelessWidget {
  final AttributionResult result;
  const WhoBehindSection({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = result;
    if (!r.found) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle("Who's behind it"),
        Text('Nothing here matches a known scam campaign in Kantoi\'s database yet. That does not prove it is safe.', style: t.bodyMedium),
      ]);
    }
    final c = r.campaign;
    const red = Color(0xFFDC2626);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle("Who's behind it", trailing: r.demo ? const DemoBadge() : null),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.hub_rounded, color: red),
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
                    child: LinearProgressIndicator(value: r.confidence, minHeight: 8, color: red, backgroundColor: red.withValues(alpha: 0.12)),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${(r.confidence * 100).round()}%', style: t.labelLarge),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _chip(context, '${c.domains} websites'),
                _chip(context, '${c.reports.length} reports'),
                _chip(context, 'First seen ${shortDate(c.firstSeen)}'),
                for (final x in c.targets.take(2)) _chip(context, 'Targets: $x'),
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
          ]),
        ),
      ),
    ]);
  }

  Widget _chip(BuildContext context, String s) => Chip(label: Text(s), visualDensity: VisualDensity.compact);
}
