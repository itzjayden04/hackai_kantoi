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
          const SizedBox(height: 8),
          const PageTitle('Learn'),
          const SizedBox(height: 24),
          const KSection(
            'Practice',
            first: true,
            info: 'Spot the scam: five made-up messages. Tap the suspicious words, then say Scam or Genuine. '
                'Your score and level go up as you improve.\n\n'
                'Safety check-up: quick questions about your bank, phone and accounts, with what to fix.',
            children: [
              Reveal(child: _ScoreCard()),
              Reveal(index: 1, child: _PracticeCard()),
              Reveal(index: 2, child: _CheckupCard()),
            ],
          ),
          KSection(
            'Lessons',
            info: 'How each scam works step by step, a made-up example, the warning signs and what to do.',
            children: [
              Reveal(
                index: 3,
                child: KGroup(
                  title: 'Common scams',
                  badge: '${scams.length}',
                  badgeColor: K.red,
                  note: 'Malaysia',
                  children: [
                    for (final e in shown) _ScamRow(e: e),
                    if (scams.length > 5) KGroupMore(open: _all, total: scams.length, onTap: () => setState(() => _all = !_all)),
                  ],
                ),
              ),
              KGroup(children: [for (final e in genuine) _ScamRow(e: e)]),
            ],
          ),
          const KSection(
            'Family',
            info: 'A guardian is someone you trust. When a message is very likely a scam, you can tell them in one tap.',
            children: [GuardianStatusTile()],
          ),
          const SizedBox(height: 32),
          KCard(
            color: K.surfaceLow,
            borderColor: Colors.transparent,
            child: Row(children: [
              const Icon(Icons.support_agent_rounded, color: K.red),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('In doubt? Call NSRC 997', style: t.titleMedium),
                ]),
              ),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: K.error, minimumSize: const Size(0, 40)), onPressed: () => dial(nsrcNumber), child: const Text('Call')),
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Title and small capitals on the left, the score itself big on the right.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your practice score', style: t.titleMedium),
              const SizedBox(height: 4),
              Text(
                (done == 0 ? 'No practice yet' : '${coach.passed} of $done spotted · ${drillLevelLabel(coach.level)}').toUpperCase(),
                style: monoCaps(),
              ),
              if (coach.streak > 1) ...[
                const SizedBox(height: 8),
                Pill('${coach.streak} in a row', color: K.green, icon: Icons.bolt_rounded),
              ],
            ]),
          ),
          BigNumber(
            done == 0 ? '–' : '${(score * 100).round()}',
            unit: done == 0 ? null : '/100',
            size: 44,
            color: done == 0 ? K.outline : (score >= 0.7 ? K.green : score >= 0.4 ? K.amber : K.red),
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
    // Like the sample's "Invite friends" card: navy glow, a big faint shield,
    // a light title over small capitals and a full-width white pill.
    return NavyGlowCard(
      watermark: Icons.verified_user_outlined,
      onTap: start,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Spot the scam', style: t.headlineSmall?.copyWith(color: Colors.white)),
        const SizedBox(height: 4),
        Text(
          (review.isEmpty ? '${DrillPage.defaultRounds} questions · made-up messages' : 'Next: ${review.join(' and ')}').toUpperCase(),
          style: monoCaps(color: const Color(0xB3FFFFFF)),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: K.navy,
            minimumSize: const Size(0, 50),
            textStyle: monoCaps(size: 13).copyWith(fontWeight: FontWeight.w600),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text((coach.done == 0 ? 'Start practice' : 'Continue practice').toUpperCase()),
          onPressed: start,
        ),
      ]),
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
      sub = '$n quick questions';
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
            Text(title, style: t.titleMedium),
            const SizedBox(height: 2),
            Text(sub, style: t.bodySmall),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: K.outline),
      ]),
    );
  }
}

class _ScamRow extends StatelessWidget {
  final Explainer e;
  const _ScamRow({required this.e});
  @override
  Widget build(BuildContext context) => KGroupRow(
        icon: explainerIcon(e.id),
        color: e.genuine ? K.green : K.red,
        label: e.genuine ? 'How to tell a genuine message' : e.name,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScamStoryPage(e: e))),
      );
}
