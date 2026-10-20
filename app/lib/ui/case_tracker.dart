import 'package:flutter/material.dart';

import '../engine/cases.dart';
import '../local_store.dart';
import 'emergency_page.dart';

String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 60) return '${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'} ago';
  if (d.inHours < 48) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
  return '${d.inDays} days ago';
}

/// The victim's checklist for one case, saved on the device.
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
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(c.summary, style: t.bodySmall)),
            const SizedBox(width: 8),
            Text('${c.done.length} of ${caseSteps.length} done', style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              for (final s in caseSteps)
                CheckboxListTile(
                  dense: compact,
                  value: c.done.containsKey(s.id),
                  onChanged: (v) => localStore.setStep(c, s.id, v == true),
                  title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: compact ? null : Text(s.help),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Text('Saved on this device. Kantoi reminds you about anything not done yet.', style: t.bodySmall),
        ]);
      },
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
        const amber = Color(0xFFB45309);
        final t = Theme.of(context).textTheme;
        return Material(
          color: amber.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.notifications_active_rounded, color: amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: 'Still to do for your case (${c.title}, ${timeAgo(c.createdAt)}): ',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: '${c.pending.map((s) => s.pendingLabel).join(', ')}.'),
                  ]), style: t.bodyMedium),
                ),
              ]),
              Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
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
