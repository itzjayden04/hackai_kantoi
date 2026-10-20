import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../engine/relationship.dart';
import '../engine/review.dart';
import '../local_store.dart';

/// "This was actually legit / a scam". Saved to the review queue on this
/// device; it never changes a result automatically.
class FeedbackBar extends StatefulWidget {
  final Investigation? inv;
  final RelationshipReport? relationship;
  const FeedbackBar({super.key, this.inv, this.relationship});
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
    if (_sent != null) {
      return Row(children: [
        const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF15803D), size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Thanks. Saved on this device for review. It does not change results automatically.', style: t.bodySmall),
        ),
      ]);
    }
    return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('Was Kantoi wrong?', style: t.bodySmall),
      TextButton.icon(
          onPressed: () => _send(UserLabel.legit), icon: const Icon(Icons.thumb_up_alt_outlined, size: 18), label: const Text('This was actually legit')),
      TextButton.icon(
          onPressed: () => _send(UserLabel.scam), icon: const Icon(Icons.report_outlined, size: 18), label: const Text('This was actually a scam')),
    ]);
  }
}
