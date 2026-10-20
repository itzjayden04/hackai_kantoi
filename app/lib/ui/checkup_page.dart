import 'package:flutter/material.dart';

import '../awareness/checkup.dart';
import 'kit.dart';
import 'learn/learn_widgets.dart';
import 'theme.dart';

/// Eight quick questions, then a to-do list the user can tick off over time.
class CheckupPage extends StatefulWidget {
  const CheckupPage({super.key});
  @override
  State<CheckupPage> createState() => _CheckupPageState();
}

class _CheckupPageState extends State<CheckupPage> {
  bool _retake = false;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    checkup.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Safety check-up')),
        body: ListenableBuilder(
          listenable: checkup,
          builder: (context, _) {
            final next = checkItems.where((i) => !checkup.answers.containsKey(i.id)).firstOrNull;
            return AnimatedSwitcher(
              duration: K.medium,
              switchInCurve: K.curve,
              transitionBuilder: (w, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a), child: w),
              ),
              child: _retake || next != null ? _question(_retake ? null : next) : _results(),
            );
          },
        ),
      );

  Widget _question(CheckItem? item) {
    final t = Theme.of(context).textTheme;
    final i = item == null ? _step : checkItems.indexOf(item);
    final q = checkItems[i];
    void pick(Answer a) {
      checkup.answer(q.id, a);
      setState(() {
        if (_retake) {
          _step++;
          if (_step >= checkItems.length) {
            _retake = false;
            _step = 0;
          }
        }
      });
    }

    Widget option(String label, IconData icon, Color c, Answer a) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: KCard(
            onTap: () => pick(a),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(icon, color: c),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: t.titleMedium)),
              const Icon(Icons.chevron_right_rounded, color: K.outline),
            ]),
          ),
        );

    return PageBody(key: ValueKey('q${q.id}$_retake'), children: [
      Text('Question ${i + 1} of ${checkItems.length}', style: t.labelLarge),
      const SizedBox(height: 8),
      KProgressBar(value: i / checkItems.length, height: 6),
      const SizedBox(height: 24),
      const IconBadge(Icons.health_and_safety_outlined, size: 52),
      const SizedBox(height: 16),
      Text(q.question, style: t.headlineSmall?.copyWith(height: 1.3)),
      const SizedBox(height: 24),
      option('Yes', Icons.check_circle_outline_rounded, K.green, Answer.yes),
      option('No', Icons.cancel_outlined, K.red, Answer.no),
      option('Not sure', Icons.help_outline_rounded, K.outline, Answer.unsure),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.lock_outline_rounded, size: 14, color: K.outline),
        const SizedBox(width: 4),
        Flexible(child: Text('Your answers stay on this phone.', style: t.labelSmall?.copyWith(color: K.outline))),
      ]),
    ]);
  }

  Widget _results() {
    final t = Theme.of(context).textTheme;
    final fix = checkup.toFix;
    final safe = checkItems.where((i) => checkup.answers[i.id] == Answer.yes).toList();
    final c = checkup.score >= 63 ? K.green : checkup.score >= 38 ? K.amber : K.red;
    return PageBody(key: const ValueKey('results'), children: [
      KCard(
        child: Row(children: [
          ScoreRing(value: checkup.score / 100, label: '${checkup.safeCount}/${checkItems.length}', color: c),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(checkup.grade, style: t.titleLarge?.copyWith(color: c)),
              const SizedBox(height: 4),
              Text(fix.isEmpty ? 'Everything on the list is done. Great work.' : '${fix.length} thing(s) to fix. Each takes a few minutes.',
                  style: t.bodyMedium),
            ]),
          ),
        ]),
      ),
      if (fix.isNotEmpty) ...[
        const SectionTitle('Your to-do list'),
        for (final (n, i) in fix.indexed)
          Reveal(
            index: n,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: KCard(
                padding: EdgeInsets.zero,
                child: CheckboxListTile(
                  value: false,
                  onChanged: (_) => checkup.answer(i.id, Answer.yes),
                  title: Text(i.fix, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(i.how)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            ),
          ),
        Text('Tick an item when you have done it.', style: t.bodySmall),
      ],
      if (safe.isNotEmpty) ...[
        const SectionTitle('Already done'),
        KCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final i in safe)
              CheckboxListTile(
                value: true,
                onChanged: (_) => checkup.answer(i.id, Answer.no),
                title: Text(i.fix, style: t.bodyMedium?.copyWith(color: K.onSurface)),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Take the check-up again'),
        onPressed: () => setState(() {
          _retake = true;
          _step = 0;
        }),
      ),
    ]);
  }
}
