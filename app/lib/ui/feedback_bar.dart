import 'package:flutter/material.dart';

import '../engine/community/community.dart';
import '../engine/models.dart';
import '../engine/relationship.dart';
import '../engine/review.dart';
import '../local_store.dart';
import '../state.dart';
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

  /// What happened with the community report, shown under the thanks.
  String? _community;

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
    await _share(label);
  }

  /// Shares the websites, numbers and accounts with other Kantoi users
  /// (signed-in, verified accounts only). The message itself never leaves.
  Future<void> _share(UserLabel label) async {
    final inv = widget.inv;
    final store = communityIntel;
    if (inv == null || store == null) return;
    final ids = indicatorsIn(inv.artefact.entities, ownDetails: appState.ownDetails);
    if (ids.isEmpty) return;
    if (!store.canReport) {
      setState(() => _community = store.whyNot);
      return;
    }
    try {
      final n = await store.report(ids, scam: label == UserLabel.scam, scamType: inv.verdict.scamType);
      if (!mounted) return;
      setState(() => _community = n == 0
          ? null
          : 'Shared with the Kantoi community: ${ids.map((i) => i.display).join(', ')}. '
              'Only the website, or a masked number or account, is shared.');
    } catch (e) {
      if (mounted) setState(() => _community = 'Could not share with the community: $e');
    }
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
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Thanks. Saved on this device for review. It does not change results automatically.', style: t.bodySmall),
                    if (_community != null) ...[
                      const SizedBox(height: 4),
                      Text(_community!, style: t.bodySmall?.copyWith(color: K.primary)),
                    ],
                  ]),
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
