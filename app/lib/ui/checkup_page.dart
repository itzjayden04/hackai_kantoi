import 'package:flutter/material.dart';

import '../awareness/checkup.dart';
import 'theme.dart';

const _green = Color(0xFF15803D);

/// Eight quick questions, then a to-do list the user can tick off over time.
class CheckupPage extends StatefulWidget {
  const CheckupPage({super.key});
  @override
  State<CheckupPage> createState() => _CheckupPageState();
}

class _CheckupPageState extends State<CheckupPage> {
  bool _retake = false;

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
            if (_retake || next != null) return _question(_retake ? null : next);
            return _results();
          },
        ),
      );

  int _step = 0;

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

    return PageBody(children: [
      Text('Question ${i + 1} of ${checkItems.length}', style: t.labelLarge),
      const SizedBox(height: 8),
      LinearProgressIndicator(value: i / checkItems.length, minHeight: 6, borderRadius: BorderRadius.circular(4)),
      const SizedBox(height: 24),
      Text(q.question, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
      const SizedBox(height: 24),
      FilledButton(style: FilledButton.styleFrom(backgroundColor: _green), onPressed: () => pick(Answer.yes), child: const Text('Yes')),
      const SizedBox(height: 10),
      FilledButton.tonal(onPressed: () => pick(Answer.no), child: const Text('No')),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: () => pick(Answer.unsure), child: const Text('Not sure')),
      const SizedBox(height: 16),
      Text('Your answers stay on this device.', style: t.bodySmall, textAlign: TextAlign.center),
    ]);
  }

  Widget _results() {
    final t = Theme.of(context).textTheme;
    final fix = checkup.toFix;
    final safe = checkItems.where((i) => checkup.answers[i.id] == Answer.yes).toList();
    final c = checkup.score >= 63 ? _green : checkup.score >= 38 ? const Color(0xFFB45309) : const Color(0xFFDC2626);
    return PageBody(children: [
      Card(
        color: c.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(value: checkup.score / 100, strokeWidth: 7, color: c, backgroundColor: c.withValues(alpha: 0.15)),
                ),
                Text('${checkup.safeCount}/${checkItems.length}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(checkup.grade, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: c)),
                const SizedBox(height: 4),
                Text(fix.isEmpty ? 'Everything on the list is done. Great work.' : '${fix.length} thing(s) to fix. Each takes a few minutes.'),
              ]),
            ),
          ]),
        ),
      ),
      if (fix.isNotEmpty) ...[
        const SectionTitle('Your to-do list'),
        for (final i in fix)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: CheckboxListTile(
                value: false,
                onChanged: (_) => checkup.answer(i.id, Answer.yes),
                title: Text(i.fix, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(i.how)),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ),
        Text('Tick an item when you have done it.', style: t.bodySmall),
      ],
      if (safe.isNotEmpty) ...[
        const SectionTitle('Already done'),
        Card(
          child: Column(children: [
            for (final i in safe)
              CheckboxListTile(
                value: true,
                onChanged: (_) => checkup.answer(i.id, Answer.no),
                title: Text(i.fix),
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
