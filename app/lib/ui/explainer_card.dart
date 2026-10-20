import 'package:flutter/material.dart';

import '../awareness/coach.dart';
import '../awareness/drills.dart';
import '../awareness/explainers.dart';
import '../engine/models.dart';
import 'check/result_parts.dart';
import 'drill_page.dart';
import 'theme.dart';
import 'warning_image.dart';

IconData explainerIcon(String id) => switch (id) {
      'parcel' => Icons.local_shipping_outlined,
      'lhdn' => Icons.receipt_long_outlined,
      'officer' => Icons.local_police_outlined,
      'job' => Icons.work_outline_rounded,
      'investment' => Icons.trending_up_rounded,
      'love' => Icons.favorite_border_rounded,
      'love_investment' => Icons.heart_broken_outlined,
      'prize' => Icons.card_giftcard_rounded,
      'otp' => Icons.password_rounded,
      'ecommerce' => Icons.shopping_bag_outlined,
      'friend' => Icons.person_search_outlined,
      'phishing' => Icons.account_balance_outlined,
      'legit' => Icons.verified_outlined,
      _ => Icons.lightbulb_outline_rounded,
    };

/// A 30-second lesson on one scam type.
class ExplainerCard extends StatelessWidget {
  final Explainer e;
  final bool showTitle;
  const ExplainerCard({super.key, required this.e, this.showTitle = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final accent = e.genuine ? K.green : K.red;
    Widget head(String s) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(s, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        );
    Widget bullet(IconData i, Color c, String s) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(i, size: 18, color: c)),
            const SizedBox(width: 8),
            Expanded(child: Text(s, style: t.bodyMedium?.copyWith(height: 1.4))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showTitle) ...[
        Row(children: [
          Icon(explainerIcon(e.id), color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(e.title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
      ],
      Text(e.summary, style: t.bodyLarge?.copyWith(height: 1.4)),
      head(e.genuine ? 'What real messages do' : 'How it works'),
      for (var i = 0; i < e.steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: scheme.primaryContainer,
              child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(e.steps[i], style: t.bodyMedium?.copyWith(height: 1.4))),
          ]),
        ),
      head(e.genuine ? 'Signs it is real' : 'Tell-tale signs'),
      for (final s in e.signs) bullet(e.genuine ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, accent, s),
      head('What to do'),
      for (final s in e.todo) bullet(Icons.arrow_forward_rounded, scheme.primary, s),
      head('Example'),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.example, style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic, height: 1.4)),
          const SizedBox(height: 4),
          Text('Made-up example for learning.', style: t.labelSmall?.copyWith(color: scheme.outline)),
        ]),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.fitness_center_rounded),
          label: const Text('Practise spotting this'),
          onPressed: () {
            final own = drills.where((d) => d.explainerId == e.id && !coach.recentIds.contains(d.id)).toList()..shuffle();
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => DrillPage(focus: e.cues, first: own.firstOrNull)));
          },
        ),
        if (!e.genuine)
          OutlinedButton.icon(
            icon: const Icon(Icons.image_outlined),
            label: const Text('Warn family'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => WarningImagePage(content: WarningContent.fromExplainer(e)))),
          ),
      ]),
    ]);
  }
}

/// Collapsed "How this scam works" tile shown under a verdict, so it does
/// not push the evidence down.
class ExplainerTile extends StatelessWidget {
  final Investigation inv;
  const ExplainerTile({super.key, required this.inv});

  @override
  Widget build(BuildContext context) {
    final e = explainerForInvestigation(inv);
    return ExpandableSection(
      icon: explainerIcon(e.id),
      color: e.genuine ? K.green : K.primary,
      title: e.genuine ? 'How to tell a genuine message' : 'How this scam works',
      subtitle: '${e.name}. 30-second read.',
      children: [ExplainerCard(e: e, showTitle: false)],
    );
  }
}

class ExplainerPage extends StatelessWidget {
  final Explainer e;
  const ExplainerPage({super.key, required this.e});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(e.name)),
        body: PageBody(children: [ExplainerCard(e: e)]),
      );
}
