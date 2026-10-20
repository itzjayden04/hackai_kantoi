import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/review.dart';
import '../local_store.dart';
import 'file_out.dart';
import 'theme.dart';

/// The feedback review queue: what the user said Kantoi got wrong.
class ReviewQueuePage extends StatelessWidget {
  const ReviewQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback for review')),
      body: ListenableBuilder(
        listenable: localStore,
        builder: (context, _) {
          final items = localStore.review;
          return PageBody(children: [
            Text('When you tap "This was actually legit" or "This was actually a scam", a summary is saved here. '
                'It holds scores and rule names only, never the message text or numbers. Export it to share with the Kantoi team.',
                style: t.bodyMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: const Text('Export as JSON'),
                onPressed: items.isEmpty
                    ? null
                    : () async {
                        final msg = await saveOrShare([
                          (
                            name: 'kantoi-feedback.json',
                            bytes: Uint8List.fromList(utf8.encode(localStore.exportReviewJson())),
                            mime: 'application/json'
                          ),
                        ], subject: 'Kantoi feedback');
                        if (context.mounted) showSnack(context, msg);
                      },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy JSON'),
                onPressed: items.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: localStore.exportReviewJson()));
                        showSnack(context, 'Feedback copied.');
                      },
              ),
              TextButton(onPressed: items.isEmpty ? null : localStore.clearReview, child: const Text('Clear all')),
            ]),
            const SizedBox(height: 12),
            if (items.isEmpty) Text('No feedback yet.', style: t.bodyMedium),
            for (final r in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(r.label == UserLabel.legit ? Icons.thumb_up_alt_outlined : Icons.report_outlined,
                    color: r.disagrees ? const Color(0xFFB45309) : null),
                title: Text(
                    '${r.label == UserLabel.legit ? 'You said legit' : 'You said scam'}: '
                    '${r.summary['scamType'] ?? r.summary['patternType'] ?? r.kind}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Kantoi scored ${r.summary['score']}/100 (${r.summary['level']}). '
                    '${r.disagrees ? 'Kantoi disagreed.' : 'Kantoi agreed.'} ${r.at.toLocal().toString().substring(0, 16)}'),
              ),
          ]);
        },
      ),
    );
  }
}
