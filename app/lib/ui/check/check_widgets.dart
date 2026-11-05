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
            child: Icon(on ? Icons.verified_user_rounded : Icons.verified_user_outlined, color: c, size: 24),
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
                if (s != null && on) ...[
                  const SizedBox(height: 2),
                  Text(today == 0 ? 'No warnings today' : '$today warning${today == 1 ? '' : 's'} today', style: t.bodySmall),
                ],
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

/// Short pill label. "Safe" only when Kantoi saw signs the item is genuine;
/// otherwise "No signs", because finding nothing doesn't prove it's safe.
String shortRisk(RiskLevel l, [List<Finding> findings = const []]) => switch (l) {
  RiskLevel.safe => findings.any((f) => !f.isRisk) ? 'Safe' : 'No signs',
  RiskLevel.caution => 'Careful',
  RiskLevel.suspicious => 'Suspicious',
  RiskLevel.danger => 'Scam',
};

/// One past check as a list row: a tinted icon for where it came from, what
/// it was, the source in small capitals, and the verdict and time on the
/// right.
class RecentCheckCard extends StatelessWidget {
  final Investigation inv;
  const RecentCheckCard({super.key, required this.inv});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final v = inv.verdict;
    final c = riskColor(v.level);
    final detail = sourceDetail(inv);
    final at = TimeOfDay.fromDateTime(inv.artefact.receivedAt).format(context);
    return KCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultPage(inv: inv))),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: const BorderRadius.all(Radius.circular(14))),
            child: Icon(sourceIcon(inv.artefact), size: 21, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.scamType, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(
                  [sourceLabel(inv.artefact), ?detail].join(' · ').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoCaps(size: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(shortRisk(v.level, inv.findings), style: t.titleSmall?.copyWith(color: c, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(at.toUpperCase(), style: monoCaps(size: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Past checks under "• TODAY, 5 NOV"-style day headers, newest first.
List<Widget> datedChecks(List<Investigation> checks, {int revealFrom = 0}) {
  final out = <Widget>[];
  String? day;
  for (final (i, h) in checks.indexed) {
    final d = dayLabel(h.artefact.receivedAt);
    if (d != day) {
      if (day != null) out.add(const SizedBox(height: 10));
      out.add(DateHeader(d));
      day = d;
    }
    out.add(Reveal(index: revealFrom + i, child: Padding(padding: const EdgeInsets.only(bottom: 8), child: RecentCheckCard(inv: h))));
  }
  return out;
}

/// Every check kept on this phone.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Recent checks')),
    body: ListenableBuilder(
      listenable: appState,
      builder: (context, _) => PageBody(
        children: [
          Text('Kept on this phone only. Old checks are deleted automatically (see Settings).', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          if (appState.history.isEmpty) const Text('No checks yet.'),
          ...datedChecks(appState.history),
        ],
      ),
    ),
  );
}

/// A tappable tile for another way in, e.g. "Check a person or chat".
class WayInTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;
  const WayInTile({super.key, required this.icon, required this.title, this.subtitle, this.color = K.primary, required this.onTap});

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
            style: t.titleMedium?.copyWith(color: K.onSurface),
          ),
          if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: t.bodySmall)],
        ],
      ),
    );
  }
}
