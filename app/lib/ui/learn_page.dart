import 'package:flutter/material.dart';

import '../awareness/checkup.dart';
import '../awareness/coach.dart';
import '../awareness/drills.dart';
import '../awareness/explainers.dart';
import '../engine/models.dart';
import 'checkup_page.dart';
import 'drill_page.dart';
import 'emergency/hotlines.dart';
import 'emergency/widgets.dart' show dial;
import 'explainer_card.dart' show explainerIcon;
import 'guardian_ui.dart';
import 'kit.dart';
import 'learn/learn_widgets.dart';
import 'learn/scam_story.dart';
import 'theme.dart';

/// The Learn tab: a personal practice score, a quick quiz, the safety
/// check-up and short illustrated explainers of common scams.
class LearnPage extends StatefulWidget {
  const LearnPage({super.key});
  @override
  State<LearnPage> createState() => _LearnPageState();
}

class _LearnPageState extends State<LearnPage> {
  bool _all = false;

  @override
  void initState() {
    super.initState();
    coach.load();
    checkup.load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scams = explainers.where((e) => !e.genuine).toList();
    final genuine = explainers.where((e) => e.genuine).toList();
    final shown = _all ? scams : scams.take(5).toList();
    return ListenableBuilder(
      listenable: Listenable.merge([coach, checkup]),
      builder: (context, _) => PageBody(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Text('Learn', style: t.headlineMedium),
          const SizedBox(height: 4),
          Text('Short lessons and practice with made-up messages. Safe to tap anything.', style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
          const SizedBox(height: 16),
          const Reveal(child: _ScoreCard()),
          const SizedBox(height: 12),
          const Reveal(index: 1, child: _PracticeCard()),
          const SizedBox(height: 12),
          const Reveal(index: 2, child: _CheckupCard()),
          SectionTitle('Common scams in Malaysia', trailing: Text('${scams.length} types', style: t.labelMedium?.copyWith(color: K.outline))),
          for (final (i, e) in shown.indexed) Reveal(index: i, child: _ScamCard(e: e)),
          if (!_all && scams.length > shown.length)
            TextButton.icon(
              icon: const Icon(Icons.expand_more_rounded),
              label: Text('Show all ${scams.length}'),
              onPressed: () => setState(() => _all = true),
            ),
          for (final e in genuine) _ScamCard(e: e),
          const SectionTitle('Family'),
          const GuardianStatusTile(),
          const SizedBox(height: 12),
          KCard(
            color: K.surfaceLow,
            borderColor: Colors.transparent,
            child: Row(children: [
              const Icon(Icons.support_agent_rounded, color: K.red),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('In doubt? Call NSRC 997', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text('National Scam Response Centre. $nsrcHours.', style: t.bodySmall),
                ]),
              ),
              TextButton(onPressed: () => dial(nsrcNumber), child: const Text('Call')),
            ]),
          ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final done = coach.done;
    final score = done == 0 ? 0.0 : coach.passed / done;
    final skills = Coach.practised.where((c) => (coach.skills[c]?.seen ?? 0) > 0).toList()
      ..sort((a, b) => coach.skills[b]!.seen.compareTo(coach.skills[a]!.seen));
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ScoreRing(
            value: score,
            label: done == 0 ? '–' : '${(score * 100).round()}',
            sub: done == 0 ? 'no score' : '/100',
            color: done == 0 ? K.outline : (score >= 0.7 ? K.green : score >= 0.4 ? K.amber : K.red),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your practice score', style: t.titleMedium),
              const SizedBox(height: 4),
              Text(
                  done == 0
                      ? 'Answer a few practice messages to get your score.'
                      : '${coach.passed} of $done practice messages spotted correctly.',
                  style: t.bodySmall),
              if (done > 0) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Pill('Level: ${drillLevelLabel(coach.level)}', color: K.primary),
                  if (coach.streak > 1) Pill('${coach.streak} in a row', color: K.green, icon: Icons.bolt_rounded),
                ]),
              ],
            ]),
          ),
        ]),
        if (skills.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final c in skills.take(3)) _SkillBar(c),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => showKSheet(context, title: 'My skills', icon: Icons.insights_outlined, body: const _SkillsList(), primary: 'Close'),
              child: const Text('See all my skills'),
            ),
          ),
        ],
      ]),
    );
  }
}

String _skillName(CueCategory c) => c == CueCategory.legitimacy ? 'Trusting genuine messages' : cueLabel(c);

class _SkillBar extends StatelessWidget {
  final CueCategory c;
  const _SkillBar(this.c);
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = coach.skills[c];
    final seen = s?.seen ?? 0;
    final rate = seen == 0 ? 0.0 : s!.hits / seen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(_skillName(c), style: t.labelMedium?.copyWith(color: K.onSurface))),
          if (s?.mastered == true) const Icon(Icons.workspace_premium_outlined, size: 16, color: K.amber),
          const SizedBox(width: 4),
          Text(seen == 0 ? 'Not yet' : '${s!.hits}/$seen', style: t.labelMedium?.copyWith(color: K.outline)),
        ]),
        const SizedBox(height: 4),
        KProgressBar(value: rate, height: 6, color: rate >= 0.7 ? K.green : (rate >= 0.4 ? K.primary : K.amber)),
      ]),
    );
  }
}

class _SkillsList extends StatelessWidget {
  const _SkillsList();
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final c in Coach.practised) _SkillBar(c)]),
      );
}

class _PracticeCard extends StatelessWidget {
  const _PracticeCard();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final review = coach.review.where((c) => c != CueCategory.legitimacy).take(2).map(cueLabel).toList();
    void start() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DrillPage()));
    return Material(
      color: K.primaryContainer,
      borderRadius: K.r16,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: start,
        child: Stack(children: [
          const Positioned(
            right: -18,
            bottom: -24,
            child: Icon(Icons.shield_outlined, size: 140, color: Color(0x14FFFFFF)),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('QUICK PRACTICE · ${DrillPage.defaultRounds} QUESTIONS',
                  style: t.labelSmall?.copyWith(color: const Color(0xFFB6C4FF), letterSpacing: 1)),
              const SizedBox(height: 6),
              Text('Spot the scam', style: t.headlineSmall?.copyWith(color: Colors.white)),
              const SizedBox(height: 6),
              Text(
                coach.done == 0
                    ? 'Tap the suspicious words in a made-up message, then decide: scam or genuine?'
                    : review.isNotEmpty
                        ? 'Next up: more practice on ${review.join(' and ').toLowerCase()}.'
                        : 'Next up: ${drillLevelLabel(coach.level).toLowerCase()} messages.',
                style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.88)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: K.primary, minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(coach.done == 0 ? 'Start practice' : 'Continue practice'),
                onPressed: start,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CheckupCard extends StatelessWidget {
  const _CheckupCard();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final answered = checkup.answers.length;
    final n = checkItems.length;
    final String title, sub;
    if (!checkup.started) {
      title = 'Safety check-up';
      sub = '$n quick questions to see how well your accounts are protected.';
    } else if (!checkup.finished) {
      title = 'Safety check-up: $answered of $n answered';
      sub = 'Carry on where you left off.';
    } else {
      title = 'Safety check-up: ${checkup.safeCount} of $n done';
      sub = checkup.toFix.isEmpty ? 'All done. Well protected.' : '${checkup.toFix.length} thing(s) left to fix.';
    }
    final v = checkup.finished ? checkup.safeCount / n : answered / n;
    return KCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckupPage())),
      child: Row(children: [
        ScoreRing(value: v, label: '${(v * 100).round()}%', size: 52, color: checkup.finished && v == 1 ? K.green : K.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(sub, style: t.bodySmall),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: K.outline),
      ]),
    );
  }
}

class _ScamCard extends StatelessWidget {
  final Explainer e;
  const _ScamCard({required this.e});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = e.genuine ? K.green : K.red;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScamStoryPage(e: e))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconBadge(explainerIcon(e.id), color: c),
            const SizedBox(width: 12),
            Expanded(child: Text(e.genuine ? 'How to tell a genuine message' : e.name, style: t.titleMedium)),
          ]),
          const SizedBox(height: 8),
          Text(e.summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: K.onSurfaceVariant)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final tag in cueTags(e))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: K.surfaceLow, borderRadius: BorderRadius.circular(6)),
                    child: Text(tag, style: t.labelSmall?.copyWith(color: K.onSurfaceVariant)),
                  ),
              ]),
            ),
            Text('How it works', style: t.labelMedium?.copyWith(color: K.primary)),
            const Icon(Icons.chevron_right_rounded, size: 18, color: K.primary),
          ]),
        ]),
      ),
    );
  }
}
