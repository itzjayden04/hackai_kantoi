import 'package:flutter/material.dart';

import '../../awareness/coach.dart';
import '../../awareness/drills.dart';
import '../../awareness/explainers.dart';
import '../../engine/models.dart';
import '../drill_page.dart';
import '../explainer_card.dart' show explainerIcon;
import '../kit.dart';
import '../theme.dart';
import '../warning_image.dart';
import 'learn_widgets.dart';

/// One scam explained as a short illustrated story: how it unfolds step by
/// step, a made-up example, the signs and what to do.
class ScamStoryPage extends StatelessWidget {
  final Explainer e;
  const ScamStoryPage({super.key, required this.e});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final accent = e.genuine ? K.green : K.red;
    return Scaffold(
      appBar: AppBar(title: Text(e.name)),
      body: PageBody(children: [
        Reveal(
          child: KCard(
            color: accent.withValues(alpha: 0.06),
            borderColor: accent.withValues(alpha: 0.25),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconBadge(explainerIcon(e.id), color: accent, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title, style: t.titleLarge),
                  const SizedBox(height: 6),
                  Text(e.summary, style: t.bodyMedium?.copyWith(color: K.onSurface, height: 1.45)),
                ]),
              ),
            ]),
          ),
        ),
        SectionTitle(e.genuine ? 'What real messages do' : 'How it happens'),
        for (final (i, s) in e.steps.indexed)
          Reveal(index: i + 1, child: _TimelineStep(n: i + 1, text: s, last: i == e.steps.length - 1, color: e.genuine ? K.green : K.primary)),
        const SectionTitle('What it looks like'),
        Reveal(index: 2, child: _Bubble(text: e.example)),
        SectionTitle(e.genuine ? 'Signs it is real' : 'Warning signs'),
        for (final s in e.signs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KCard(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(e.genuine ? Icons.verified_outlined : Icons.warning_amber_rounded, color: accent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(s, style: t.bodyMedium?.copyWith(color: K.onSurface))),
              ]),
            ),
          ),
        const SectionTitle('What to do'),
        KCard(
          child: Column(children: [
            for (final s in e.todo)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_outline_rounded, color: K.green, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s, style: t.bodyMedium?.copyWith(color: K.onSurface))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.sports_esports_outlined),
          label: Text(e.genuine ? 'Practise telling real from fake' : 'Practise spotting this'),
          onPressed: () {
            final own = drills.where((d) => d.explainerId == e.id && !coach.recentIds.contains(d.id)).toList()..shuffle();
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => DrillPage(focus: e.cues, first: own.firstOrNull)));
          },
        ),
        if (!e.genuine) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.image_outlined),
            label: const Text('Warn family with a picture'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => WarningImagePage(content: WarningContent.fromExplainer(e)))),
          ),
        ],
      ]),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final int n;
  final String text;
  final bool last;
  final Color color;
  const _TimelineStep({required this.n, required this.text, required this.last, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 32,
          child: Column(children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            if (!last) Expanded(child: Container(width: 2, color: color.withValues(alpha: 0.25))),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 18),
            child: Text(text, style: t.bodyMedium?.copyWith(color: K.onSurface, height: 1.45)),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  const _Bubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(
          color: K.surfaceMid,
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
        ),
        child: Text(text, style: t.bodyMedium?.copyWith(color: K.onSurface, height: 1.45)),
      ),
      const SizedBox(height: 6),
      Row(children: [
        const Icon(Icons.school_outlined, size: 14, color: K.outline),
        const SizedBox(width: 4),
        Flexible(child: Text('Made-up example for learning', style: t.labelSmall?.copyWith(color: K.outline))),
      ]),
    ]);
  }
}

/// Labels for the cues a scam type uses, as small chips on its card.
List<String> cueTags(Explainer e) => e.cues.where((c) => c != CueCategory.legitimacy).take(2).map(cueLabel).toList();
