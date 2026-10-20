import 'package:flutter/material.dart';

import '../engine/models.dart';

/// Every step Kantoi took, in order, with what (if anything) left the device.
class ActivityLog extends StatelessWidget {
  final List<LogStep> steps;
  const ActivityLog({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final outline = Theme.of(context).colorScheme.outline;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: [
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 22, height: 22, child: _icon(s.status)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: s.tool, style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: '  ${s.action}'),
                    ])),
                    if (s.result.isNotEmpty) Text(s.result, style: t.bodySmall),
                  ]),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: s.sentOffDevice ? 'This step contacted an online service' : 'This step ran on your device',
                  child: Icon(s.sentOffDevice ? Icons.cloud_outlined : Icons.phonelink_lock_outlined, size: 18, color: outline),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _icon(StepStatus s) => switch (s) {
        StepStatus.running => const Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2)),
        StepStatus.done => const Icon(Icons.check_circle_rounded, color: Color(0xFF15803D), size: 20),
        StepStatus.skipped => const Icon(Icons.remove_circle_outline_rounded, color: Colors.grey, size: 20),
        StepStatus.failed => const Icon(Icons.error_outline_rounded, color: Color(0xFFB45309), size: 20),
      };
}
