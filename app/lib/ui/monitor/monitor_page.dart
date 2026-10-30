import 'package:flutter/material.dart';

import '../../guard/guard_control.dart';
import '../../monitor/monitor.dart';
import '../../report/scam_report.dart';
import '../../state.dart';
import '../kit.dart';
import '../theme.dart';

Color coverageColor(Coverage c) => switch (c) {
      Coverage.full => K.green,
      Coverage.preview || Coverage.email => K.amber,
      Coverage.sender => K.outline,
    };

Color levelColor(String level) => switch (level) {
      'danger' => K.red,
      'suspicious' => K.orange,
      'caution' => K.amber,
      _ => K.green,
    };

/// Brand-coloured letter tile instead of real logos.
class AppTile extends StatelessWidget {
  final String name;
  final double size;
  const AppTile(this.name, {super.key, this.size = 40});

  static const _colors = {
    'WhatsApp': Color(0xFF25D366),
    'WhatsApp Business': Color(0xFF128C7E),
    'Telegram': Color(0xFF229ED9),
    'Telegram X': Color(0xFF229ED9),
    'Messenger': Color(0xFF0084FF),
    'Facebook': Color(0xFF1877F2),
    'Facebook Lite': Color(0xFF1877F2),
    'Instagram': Color(0xFFE1306C),
    'TikTok': Color(0xFF111111),
    'Gmail': Color(0xFFEA4335),
    'Outlook': Color(0xFF0078D4),
    'Shopee': Color(0xFFEE4D2D),
    'Lazada': Color(0xFF0F146D),
    'Carousell': Color(0xFFD2232A),
    'Signal': Color(0xFF3A76F0),
    'Viber': Color(0xFF7360F2),
    'LINE': Color(0xFF06C755),
    'WeChat': Color(0xFF07C160),
    'Discord': Color(0xFF5865F2),
    'Snapchat': Color(0xFFFFC107),
    'X (Twitter)': Color(0xFF111111),
    'Reddit': Color(0xFFFF4500),
    'LinkedIn': Color(0xFF0A66C2),
  };

  @override
  Widget build(BuildContext context) {
    final c = _colors[name] ?? K.primaryContainer;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Text(name.isEmpty ? '?' : name[0], style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.45)),
    );
  }
}

/// The Scam Monitor card on the Check tab.
class MonitorCard extends StatefulWidget {
  const MonitorCard({super.key});
  @override
  State<MonitorCard> createState() => _MonitorCardState();
}

class _MonitorCardState extends State<MonitorCard> {
  MonitorSnapshot? _s;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await loadMonitor();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = _s;
    return KCard(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MonitorPage()));
        _load();
      },
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: K.primaryContainer.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.radar_rounded, color: K.primaryContainer),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Scam Monitor', style: t.titleMedium),
            const SizedBox(height: 2),
            Text(
              s == null
                  ? 'See which apps Kantoi watches and what it caught'
                  : 'Watching ${s.watching} app${s.watching == 1 ? '' : 's'} · ${s.alertsToday} alert${s.alertsToday == 1 ? '' : 's'} today',
              style: t.bodySmall,
            ),
          ]),
        ),
        if (s != null && s.installed.isNotEmpty)
          SizedBox(
            width: 64,
            height: 28,
            child: Stack(children: [
              for (final (i, a) in s.installed.where((a) => a.on).take(3).indexed) Positioned(left: i * 18.0, child: AppTile(a.name, size: 28)),
            ]),
          ),
        const Icon(Icons.chevron_right_rounded, color: K.outline),
      ]),
    );
  }
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});
  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  MonitorSnapshot? _s;
  GuardStatus _g = const GuardStatus();
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await loadMonitor();
    final g = await guardStatus();
    if (mounted) {
      setState(() {
        _s = s;
        _g = g;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Scam Monitor')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: PageBody(children: [
          Text('Kantoi reads new message alerts on this phone and warns you about scams. Nothing is uploaded.',
              style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (!guardSupported)
            const KCard(child: Text('The Scam Monitor works on Android phones.'))
          else if (s == null)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else ...[
            if (!_g.has('notifications'))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: KCard(
                  color: const Color(0xFFFFFBEB),
                  borderColor: const Color(0xFFFEF3C7),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Turn on "Read new messages" so the monitor can work.', style: t.bodyMedium),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: () => openGuardSetting('notifications'), child: const Text('Turn on')),
                  ]),
                ),
              ),
            Reveal(child: _Summary(s: s, caughtWeek: s.lastDays(7).fold(0, (a, d) => a + d.$3))),
            const SizedBox(height: 16),
            Reveal(index: 1, child: _WeekChart(days: s.lastDays(7))),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: s.hideScams,
              onChanged: (v) async {
                await setHideScams(v);
                _load();
              },
              title: const Text('Hide scam notifications'),
              subtitle: const Text("When a message is very likely a scam, Kantoi removes its alert and shows its own warning instead."),
            ),
            const SizedBox(height: 8),
            SectionTitle('Installed apps (${s.installed.length})'),
            KCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final (i, a) in s.installed.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 68),
                  _AppRow(a: a, today: s.today, onToggle: (v) async {
                    await setAppMonitored(a.pkg, v);
                    _load();
                  }, onOpen: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MonitorAppPage(app: a, status: _g)))),
                ],
                if (s.installed.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('None of the supported apps is installed.')),
              ]),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: Icon(_showAll ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              label: Text('Not installed (${s.notInstalled.length} more supported apps)'),
              onPressed: () => setState(() => _showAll = !_showAll),
            ),
            if (_showAll)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in s.notInstalled) Chip(avatar: AppTile(a.name, size: 20), label: Text(a.name)),
              ]),
            const SizedBox(height: 12),
            KCard(
              color: K.surfaceLow,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, color: K.primary),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'Some apps hide message text in their alerts. Kantoi can only check what the alert shows. '
                        'Android 15 and later also hide one-time codes from apps like Kantoi.',
                        style: t.bodySmall)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final MonitorSnapshot s;
  final int caughtWeek;
  const _Summary({required this.s, required this.caughtWeek});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget tile(String n, String label, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: K.r16),
            child: Column(children: [
              Text(n, style: t.headlineMedium?.copyWith(color: c, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, style: t.labelMedium?.copyWith(color: K.onSurfaceVariant)),
            ]),
          ),
        );
    return Row(children: [
      tile('${s.watching}', 'Apps watched', K.primaryContainer),
      const SizedBox(width: 8),
      tile('${s.alertsToday}', 'Alerts today', K.orange),
      const SizedBox(width: 8),
      tile('$caughtWeek', 'Caught this week', K.red),
    ]);
  }
}

/// Seven bars of messages checked, with the warning share in red.
class _WeekChart extends StatelessWidget {
  final List<(String, int, int)> days;
  const _WeekChart({required this.days});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final max = days.fold<int>(1, (m, d) => d.$2 + d.$3 > m ? d.$2 + d.$3 : m);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Last 7 days', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          _legend(K.primaryContainer.withValues(alpha: 0.35), 'Checked'),
          const SizedBox(width: 12),
          _legend(K.red, 'Warned'),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final (i, d) in days.indexed)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('${d.$2}', style: t.labelSmall?.copyWith(color: K.outline)),
                    const SizedBox(height: 2),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 400 + i * 60),
                      curve: K.curve,
                      builder: (_, f, _) {
                        final h = 80 * f * (d.$2 + d.$3) / max;
                        final red = d.$2 + d.$3 == 0 ? 0.0 : h * d.$3 / (d.$2 + d.$3);
                        return Column(children: [
                          Container(height: (h - red).clamp(2, 80), decoration: BoxDecoration(
                            color: i == days.length - 1 ? K.primaryContainer : K.primaryContainer.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.vertical(top: const Radius.circular(4), bottom: Radius.circular(red > 0 ? 0 : 4)),
                          )),
                          if (red > 0) Container(height: red, decoration: const BoxDecoration(color: K.red, borderRadius: BorderRadius.vertical(bottom: Radius.circular(4)))),
                        ]);
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(names[DateTime.parse(d.$1).weekday - 1], style: t.labelSmall?.copyWith(color: i == days.length - 1 ? K.primary : K.outline)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _legend(Color c, String s) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(s, style: const TextStyle(fontSize: 11, color: K.outline)),
      ]);
}

class _AppRow extends StatelessWidget {
  final MonitoredApp a;
  final String today;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;
  const _AppRow({required this.a, required this.today, required this.onToggle, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = a.alertsOn(today);
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          AppTile(a.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Pill(coverageLabel(a.coverage), color: coverageColor(a.coverage)),
                if (n > 0) Text('$n alert${n == 1 ? '' : 's'} today', style: t.labelSmall?.copyWith(color: K.red)),
              ]),
            ]),
          ),
          Switch(value: a.on, onChanged: onToggle),
        ]),
      ),
    );
  }
}

/// One app's alerts, newest first, with Trace and Report on each.
class MonitorAppPage extends StatefulWidget {
  final MonitoredApp app;
  final GuardStatus status;
  const MonitorAppPage({super.key, required this.app, required this.status});
  @override
  State<MonitorAppPage> createState() => _MonitorAppPageState();
}

class _MonitorAppPageState extends State<MonitorAppPage> {
  String _filter = 'all';
  late bool _on = widget.app.on;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = widget.app;
    final all = alertsFor(widget.status, a.pkg);
    final shown = all.where((x) => _filter == 'all' || x.level == _filter).toList();
    return Scaffold(
      appBar: AppBar(title: Text(a.name)),
      body: PageBody(children: [
        Row(children: [
          AppTile(a.name, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Pill(coverageLabel(a.coverage), color: coverageColor(a.coverage)),
              const SizedBox(height: 6),
              Text(coverageHelp(a.coverage), style: t.bodySmall),
            ]),
          ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _on,
          title: const Text('Watch this app'),
          subtitle: Text('${a.checked} messages checked, ${a.alerts} warnings in 2 weeks'),
          onChanged: (v) async {
            await setAppMonitored(a.pkg, v);
            setState(() => _on = v);
          },
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('All')),
            ButtonSegment(value: 'danger', label: Text('High')),
            ButtonSegment(value: 'suspicious', label: Text('Suspicious')),
            ButtonSegment(value: 'caution', label: Text('Careful')),
          ],
          selected: {_filter},
          onSelectionChanged: (s) => setState(() => _filter = s.first),
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(all.isEmpty ? 'No warnings from ${a.name} yet.' : 'Nothing at this level.',
                textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
          ),
        for (final (i, x) in shown.indexed)
          Reveal(
            index: i,
            child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _AlertCard(alert: x, appName: a.name)),
          ),
      ]),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final GuardAlert alert;
  final String appName;
  const _AlertCard({required this.alert, required this.appName});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = levelColor(alert.level);
    final h = alert.at.hour % 12 == 0 ? 12 : alert.at.hour % 12;
    final time = '${alert.at.day}/${alert.at.month} $h:${alert.at.minute.toString().padLeft(2, '0')} ${alert.at.hour < 12 ? 'AM' : 'PM'}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: K.r16,
        border: Border.all(color: K.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: c),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Pill(alert.label.isEmpty ? alert.level : alert.label, color: c),
                  const SizedBox(width: 8),
                  Text(time, style: t.labelSmall?.copyWith(color: K.outline)),
                ]),
                const SizedBox(height: 6),
                if (alert.chat.isNotEmpty) Text(alert.chat, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                if (alert.text.isNotEmpty) Text(alert.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                if (alert.reasons.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final r in alert.reasons.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                        child: Text(r, style: t.labelSmall?.copyWith(color: c)),
                      ),
                  ]),
                ],
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    icon: const Icon(Icons.hub_outlined, size: 18),
                    label: const Text('Trace'),
                    onPressed: () {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      appState.openTrace(alert.target.isEmpty ? alert.text : alert.target);
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: const Text('Report'),
                    onPressed: () {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      appState.openReport(
                          report: reportFromAlert(
                              id: 'rep-${DateTime.now().millisecondsSinceEpoch}', app: alert.app, chat: alert.chat, text: alert.text, scamType: alert.headline));
                    },
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
