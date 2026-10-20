import 'package:flutter/material.dart';

import '../engine/retention.dart';
import '../local_store.dart';
import 'limits_page.dart';
import 'review_page.dart';
import 'theme.dart';

/// Settings section: how long data is kept, delete everything, the
/// feedback queue and the honest limits page.
class PrivacyControls extends StatelessWidget {
  const PrivacyControls({super.key});

  Future<void> _deleteAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete all your Kantoi data?'),
        content: const Text('This removes your checks, live alerts, case checklists, feedback and settings from this device. '
            'It cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await localStore.deleteAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All your Kantoi data has been deleted.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: localStore,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Your data'),
        Text('Kantoi deletes old checks, alerts, feedback and case checklists automatically.', style: t.bodyMedium),
        const SizedBox(height: 10),
        DropdownButtonFormField<Retention>(
          key: ValueKey(localStore.retention),
          initialValue: localStore.retention,
          decoration: const InputDecoration(labelText: 'Keep my data for'),
          items: [for (final r in Retention.values) DropdownMenuItem(value: r, child: Text(retentionLabels[r]!))],
          onChanged: (v) => localStore.setRetention(v ?? defaultRetention),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.rate_review_outlined),
            label: Text('Feedback for review (${localStore.review.length})'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReviewQueuePage())),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.info_outline_rounded),
            label: const Text("What Kantoi can't do"),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LimitsPage())),
          ),
        ]),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
          icon: const Icon(Icons.delete_forever_rounded),
          label: const Text('Delete all my Kantoi data'),
          onPressed: () => _deleteAll(context),
        ),
      ]),
    );
  }
}
