import 'package:flutter/material.dart';

import '../awareness/checkup.dart';
import '../awareness/coach.dart';
import '../awareness/drills.dart';
import '../awareness/explainers.dart';
import '../engine/models.dart';
import 'checkup_page.dart';
import 'drill_page.dart';
import 'explainer_card.dart';
import 'guardian_ui.dart';
import 'theme.dart';

/// Branch 7: awareness and prevention (explainer cards, practice drills,
/// guardian mode, safety check-up).
class LearnPage extends StatefulWidget {
  const LearnPage({super.key});
  @override
  State<LearnPage> createState() => _LearnPageState();
}

class _LearnPageState extends State<LearnPage> {
  @override
  void initState() {
    super.initState();
    coach.load();
    checkup.load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([coach, checkup]),
      builder: (context, _) => PageBody(children: [
        Text('Learn', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('A few minutes of practice makes scams much easier to spot.', style: t.bodyLarge),
        const SizedBox(height: 16),
        const _PracticeCard(),
        const SizedBox(height: 12),
        const _CheckupCard(),
        const SizedBox(height: 12),
        const GuardianStatusTile(),
        const SectionTitle('How scams work'),
        Text('Tap a scam to see how it works, the signs and what to do.', style: t.bodyMedium),
        const SizedBox(height: 10),
        for (final e in [...explainers.where((e) => !e.genuine), ...explainers.where((e) => e.genuine)])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                leading: Icon(explainerIcon(e.id), color: e.genuine ? const Color(0xFF15803D) : Theme.of(context).colorScheme.primary),
                title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(e.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExplainerPage(e: e))),
              ),
            ),
          ),
      ]),
    );
  }
}

class _PracticeCard extends StatelessWidget {
  const _PracticeCard();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = Coach.practised.length;
    final review = coach.review.where((c) => c != CueCategory.legitimacy).take(2).map(cueLabel).toList();
    return Card(
      color: scheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DrillPage())),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.fitness_center_rounded, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Practice: 2 minutes',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              coach.done == 0
                  ? 'Spot the scam in safe, made-up messages. Tap the suspicious words, then decide.'
                  : review.isNotEmpty
                      ? 'Next up: more practice on ${review.join(' and ').toLowerCase()}.'
                      : 'Next up: ${drillLevelLabel(coach.level).toLowerCase()} messages.',
              style: t.bodyLarge?.copyWith(color: scheme.onPrimaryContainer),
            ),
            if (coach.done > 0) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 16, runSpacing: 6, children: [
                _stat(context, Icons.local_fire_department_rounded, 'Streak ${coach.streak} (best ${coach.bestStreak})'),
                _stat(context, Icons.emoji_events_outlined, '${coach.masteredCount} of $total signs mastered'),
                _stat(context, Icons.trending_up_rounded, 'Level: ${drillLevelLabel(coach.level)}'),
              ]),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(coach.done == 0 ? 'Start practice' : 'Continue practice'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DrillPage())),
            ),
            if (coach.done > 0) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => showDialog(context: context, builder: (_) => const _SkillsDialog()),
                child: const Text('See my skills'),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, IconData i, String s) {
    final c = Theme.of(context).colorScheme.onPrimaryContainer;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(i, size: 18, color: c),
      const SizedBox(width: 4),
      Flexible(child: Text(s, style: TextStyle(color: c, fontWeight: FontWeight.w600))),
    ]);
  }
}

class _SkillsDialog extends StatelessWidget {
  const _SkillsDialog();
  @override
  Widget build(BuildContext context) {
    final cats = Coach.practised;
    return AlertDialog(
      title: const Text('My skills'),
      content: SizedBox(
        width: 420,
        child: ListView(shrinkWrap: true, children: [
          for (final c in cats)
            Builder(builder: (context) {
              final s = coach.skills[c];
              final seen = s?.seen ?? 0;
              final rate = seen == 0 ? 0.0 : s!.hits / seen;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  s?.mastered == true ? Icons.emoji_events_rounded : seen == 0 ? Icons.radio_button_unchecked : Icons.timelapse_rounded,
                  color: s?.mastered == true ? const Color(0xFFB45309) : null,
                ),
                title: Text(c == CueCategory.legitimacy ? 'Trusting genuine messages' : cueLabel(c)),
                subtitle: LinearProgressIndicator(value: rate, minHeight: 5, borderRadius: BorderRadius.circular(3)),
                trailing: Text(seen == 0 ? 'Not yet' : '${s!.hits}/$seen'),
              );
            }),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

class _CheckupCard extends StatelessWidget {
  const _CheckupCard();
  @override
  Widget build(BuildContext context) {
    final answered = checkup.answers.length;
    final n = checkItems.length;
    final String title, sub;
    if (!checkup.started) {
      title = 'Safety check-up';
      sub = '8 quick questions to see how well your accounts are protected.';
    } else if (!checkup.finished) {
      title = 'Safety check-up: $answered of $n answered';
      sub = 'Carry on where you left off.';
    } else {
      title = 'Safety check-up: ${checkup.safeCount} of $n done';
      sub = checkup.toFix.isEmpty ? 'All done. Well protected.' : '${checkup.toFix.length} thing(s) left to fix.';
    }
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            value: checkup.finished ? checkup.safeCount / n : answered / n,
            strokeWidth: 5,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckupPage())),
      ),
    );
  }
}
