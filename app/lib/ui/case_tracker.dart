import 'package:flutter/material.dart';

import '../engine/cases.dart';
import '../local_store.dart';
import 'emergency_page.dart';
import 'kit.dart';
import 'theme.dart';

String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 60) return '${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'} ago';
  if (d.inHours < 48) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
  return '${d.inDays} days ago';
}

/// The victim's "what to do right now" checklist for one case, saved on the
/// device so progress survives closing the app.
class CaseChecklist extends StatelessWidget {
  final String caseId;
  final String title;
  final bool compact;
  const CaseChecklist({super.key, required this.caseId, required this.title, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: localStore,
      builder: (context, _) {
        final c = localStore.caseFor(caseId, title: title);
        final total = caseSteps.length;
        final n = c.done.length.clamp(0, total);
        // The next step to do can unfold its explanation.
        final next = caseSteps.indexWhere((s) => !c.done.containsKey(s.id));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Title and its "i" on the left, "0 of 7 done" in blue on the right,
          // a progress bar under them.
          Row(children: [
            Expanded(
              child: Row(children: [
                Flexible(child: Text('Stop the damage', style: t.titleLarge?.copyWith(fontSize: 20))),
                const SizedBox(width: 6),
                const InfoButton(
                  title: 'Stop the damage',
                  message: 'Tick each step as you go. Your progress is saved on this phone only, so you can come back to it.',
                ),
              ]),
            ),
            Text('$n of $total done', style: t.titleSmall?.copyWith(color: n == total ? K.green : K.blue, fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 10),
          KProgressBar(value: n / total, color: n == total ? K.green : K.blue, height: 8),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              border: Border.all(color: K.outlineVariant.withValues(alpha: 0.7)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(children: [
              for (final (i, s) in caseSteps.indexed) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, color: K.surfaceHigh),
                _StepTile(
                  index: i + 1,
                  step: s,
                  done: c.done.containsKey(s.id),
                  canExplain: !compact && i == next,
                  onTap: () => localStore.setStep(c, s.id, !c.done.containsKey(s.id)),
                ),
              ],
            ]),
          ),
        ]);
      },
    );
  }
}

/// One step: a round tick on the left, the step and its "Urgent" mark, and
/// for the next step to do an "i" and a fold-out explanation.
class _StepTile extends StatefulWidget {
  final int index;
  final CaseStep step;
  final bool done;
  final bool canExplain;
  final VoidCallback onTap;
  const _StepTile({required this.index, required this.step, required this.done, required this.canExplain, required this.onTap});

  @override
  State<_StepTile> createState() => _StepTileState();
}

class _StepTileState extends State<_StepTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final done = widget.done;
    return Semantics(
      checked: done,
      button: true,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              AnimatedContainer(
                duration: K.fast,
                curve: K.curve,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? K.blue : Colors.white,
                  border: Border.all(color: done ? K.blue : K.outline, width: 1.5),
                ),
                child: done ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: widget.step.title),
                    if (widget.index <= 2 && !done)
                      TextSpan(text: '   Urgent', style: t.labelMedium?.copyWith(color: K.error, fontWeight: FontWeight.w500)),
                  ]),
                  style: t.bodyLarge?.copyWith(fontSize: 15, color: done ? K.outline : K.onSurface, height: 1.35),
                ),
              ),
              if (widget.canExplain) ...[
                InfoButton(title: widget.step.title, message: widget.step.help),
                IconButton(
                  tooltip: _open ? 'Hide' : 'Why',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: K.outline),
                  onPressed: () => setState(() => _open = !_open),
                ),
              ],
            ]),
            AnimatedSize(
              duration: K.medium,
              curve: K.curve,
              alignment: Alignment.topCenter,
              child: widget.canExplain && _open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(38, 6, 8, 0),
                      child: Text(widget.step.help, style: t.bodySmall?.copyWith(color: K.outline)),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Shown at the top of the app for open cases older than a few hours.
class CaseReminderBanner extends StatelessWidget {
  const CaseReminderBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: localStore,
      builder: (context, _) {
        final due = localStore.reminders();
        if (due.isEmpty) return const SizedBox.shrink();
        final c = due.first;
        final t = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: KCard(
            color: K.errorContainer.withValues(alpha: 0.5),
            borderColor: K.red.withValues(alpha: 0.3),
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.notifications_active_outlined, color: K.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: 'Still to do for your case (${c.title}, ${timeAgo(c.createdAt)}): ',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: '${c.pending.map((s) => s.pendingLabel).join(', ')}.'),
                  ]), style: t.bodySmall?.copyWith(color: K.onSurface)),
                ),
              ]),
              Wrap(alignment: WrapAlignment.end, spacing: 0, children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EmergencyPage(caseId: c.id))),
                  child: const Text('Open checklist'),
                ),
                TextButton(onPressed: () => localStore.snooze(c), child: const Text('Remind me later')),
                TextButton(onPressed: () => localStore.closeCase(c), child: const Text('All done')),
              ]),
            ]),
          ),
        );
      },
    );
  }
}
