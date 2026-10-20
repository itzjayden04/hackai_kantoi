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
        final n = c.done.length.clamp(0, caseSteps.length);
        final all = n == caseSteps.length;
        return KCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('What to do right now', style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text('Tap each step when it is done.', style: t.bodySmall),
                ]),
              ),
              const SizedBox(width: 8),
              Pill('$n of ${caseSteps.length} done', color: all ? K.green : K.red),
            ]),
            const SizedBox(height: 12),
            KProgressBar(value: n / caseSteps.length, color: all ? K.green : K.red, height: 6),
            const SizedBox(height: 12),
            for (final (i, s) in caseSteps.indexed)
              _StepTile(
                index: i + 1,
                step: s,
                done: c.done.containsKey(s.id),
                compact: compact,
                onTap: () => localStore.setStep(c, s.id, !c.done.containsKey(s.id)),
              ),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.lock_outline_rounded, size: 14, color: K.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Saved on this phone only. Kantoi reminds you about steps not done yet.',
                    style: t.labelSmall?.copyWith(color: K.outline)),
              ),
            ]),
          ]),
        );
      },
    );
  }
}

class _StepTile extends StatelessWidget {
  final int index;
  final CaseStep step;
  final bool done;
  final bool compact;
  final VoidCallback onTap;
  const _StepTile({required this.index, required this.step, required this.done, required this.compact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        checked: done,
        button: true,
        child: Material(
          color: done ? K.surfaceLow : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: done ? Colors.transparent : K.outlineVariant.withValues(alpha: 0.7)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 10 : 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AnimatedContainer(
                  duration: K.fast,
                  curve: K.curve,
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? K.green : Colors.white,
                    border: Border.all(color: done ? K.green : K.outline, width: 2),
                  ),
                  child: AnimatedSwitcher(
                    duration: K.fast,
                    transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                    child: done
                        ? const Icon(Icons.check_rounded, key: ValueKey(1), size: 16, color: Colors.white)
                        : Text('$index',
                            key: const ValueKey(0),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: K.outline, height: 1.6)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AnimatedDefaultTextStyle(
                      duration: K.fast,
                      style: (t.titleSmall ?? const TextStyle()).copyWith(
                        fontWeight: FontWeight.w600,
                        color: done ? K.outline : K.onSurface,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                      child: Text(step.title),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 2),
                      Text(step.help, style: t.bodySmall),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
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
