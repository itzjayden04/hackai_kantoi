import 'package:flutter/material.dart';

import '../../engine/models.dart';
import '../../guard/guard_control.dart';
import '../../state.dart';
import '../kit.dart';
import '../protection_page.dart';
import '../theme.dart';
import 'check_format.dart';
import 'result_page.dart';

/// Shows whether phone protection is on, with today's warnings. Tapping it
/// opens the Protection centre.
class ProtectionStatusCard extends StatefulWidget {
  const ProtectionStatusCard({super.key});
  @override
  State<ProtectionStatusCard> createState() => _ProtectionStatusCardState();
}

class _ProtectionStatusCardState extends State<ProtectionStatusCard> with WidgetsBindingObserver {
  GuardStatus? _s;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await guardStatus();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    if (!guardSupported) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final s = _s;
    final on = s?.ready ?? false;
    final now = DateTime.now();
    final today = s?.recent.where((a) => a.at.year == now.year && a.at.month == now.month && a.at.day == now.day).length ?? 0;
    final c = on ? K.primary : K.amber;
    return KCard(
      color: on ? K.surfaceMid : K.amber.withValues(alpha: 0.08),
      borderColor: on ? Colors.transparent : K.amber.withValues(alpha: 0.3),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProtectionPage()));
        _refresh();
      },
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(on ? Icons.shield_rounded : Icons.shield_outlined, color: c, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(s == null ? 'Auto-Protection' : (on ? 'Auto-Protection is on' : 'Auto-Protection is off'), style: t.titleMedium),
                    ),
                    if (on) const PulseDot(color: K.green, size: 7),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  s == null
                      ? 'Checking...'
                      : on
                      ? (today == 0
                            ? 'Watching chat messages, links and payment apps. No warnings today.'
                            : '$today warning${today == 1 ? '' : 's'} shown today. Watching chats, links and payment apps.')
                      : 'Turn it on so Kantoi can warn you before you reply or pay.',
                  style: t.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: on ? Colors.white : K.amber, borderRadius: BorderRadius.circular(99)),
            child: Text(
              on ? 'Settings' : 'Turn on',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? K.primary : Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

String shortRisk(RiskLevel l) => switch (l) {
  RiskLevel.safe => 'Safe',
  RiskLevel.caution => 'Careful',
  RiskLevel.suspicious => 'Suspicious',
  RiskLevel.danger => 'Scam',
};

/// One past check: risk dot, title, risk pill, where it came from, the main
/// reason and when.
class RecentCheckCard extends StatelessWidget {
  final Investigation inv;
  const RecentCheckCard({super.key, required this.inv});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final v = inv.verdict;
    final c = riskColor(v.level);
    final detail = sourceDetail(inv);
    return KCard(
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultPage(inv: inv))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(v.scamType, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Pill(shortRisk(v.level), color: c),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(sourceIcon(inv.artefact), size: 16, color: K.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                sourceLabel(inv.artefact),
                style: t.bodySmall?.copyWith(color: K.onSurface, fontWeight: FontWeight.w500),
              ),
              if (detail != null) ...[
                Text('  ·  ', style: t.bodySmall?.copyWith(color: K.outline)),
                Expanded(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  shortReason(inv),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelMedium?.copyWith(color: K.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              Text(timeAgo(inv.artefact.receivedAt), style: t.labelMedium?.copyWith(color: K.outline)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Every check kept on this phone.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recent checks')),
    body: ListenableBuilder(
      listenable: appState,
      builder: (context, _) => PageBody(
        children: [
          Text('Kept on this phone only. Old checks are deleted automatically (see Settings).', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (appState.history.isEmpty) const Text('No checks yet.'),
          for (final (i, h) in appState.history.indexed)
            Reveal(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RecentCheckCard(inv: h),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A tappable tile for another way in, e.g. "Check a person or chat".
class WayInTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const WayInTile({super.key, required this.icon, required this.title, required this.subtitle, this.color = K.primary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return KCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: K.onSurface),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: t.bodySmall),
        ],
      ),
    );
  }
}
