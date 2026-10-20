import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../engine/relationship.dart';
import '../engine/review.dart';
import '../local_store.dart';
import 'theme.dart';

/// "This was actually legit / a scam". Saved to the review queue on this
/// device; it never changes a result automatically.
class FeedbackBar extends StatefulWidget {
  final Investigation? inv;
  final RelationshipReport? relationship;
  final String prompt;
  const FeedbackBar({super.key, this.inv, this.relationship, this.prompt = 'Was Kantoi wrong?'});
  @override
  State<FeedbackBar> createState() => _FeedbackBarState();
}

class _FeedbackBarState extends State<FeedbackBar> {
  UserLabel? _sent;

  Future<void> _send(UserLabel label) async {
    final summary = widget.inv != null ? investigationSummary(widget.inv!) : relationshipSummary(widget.relationship!);
    await localStore.addReview(ReviewItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      at: DateTime.now(),
      label: label,
      kind: widget.inv != null ? 'message' : 'relationship',
      summary: summary,
    ));
    if (!mounted) return;
    setState(() => _sent = label);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AnimatedSize(
      duration: K.medium,
      curve: K.curve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: K.fast,
        child: _sent != null
            ? Row(key: const ValueKey('sent'), children: [
                const Icon(Icons.check_circle_outline_rounded, color: K.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Thanks. Saved on this device for review. It does not change results automatically.', style: t.bodySmall),
                ),
              ])
            : Column(key: const ValueKey('ask'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.prompt, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Tell Kantoi. It is saved on this phone for review.', style: t.bodySmall),
                const SizedBox(height: 6),
                Wrap(spacing: 4, children: [
                  TextButton.icon(
                      onPressed: () => _send(UserLabel.legit),
                      icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                      label: const Text('This was actually legit')),
                  TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: K.red),
                      onPressed: () => _send(UserLabel.scam),
                      icon: const Icon(Icons.report_outlined, size: 18),
                      label: const Text('This was actually a scam')),
                ]),
              ]),
      ),
    );
  }
}
