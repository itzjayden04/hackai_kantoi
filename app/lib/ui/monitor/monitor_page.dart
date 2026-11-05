import 'package:flutter/material.dart';

import '../../guard/guard_control.dart';
import '../../monitor/monitor.dart';
import '../../report/scam_report.dart';
import '../../state.dart';
import '../kit.dart';
import '../theme.dart';

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
        const TintIcon(Icons.radar_rounded, color: K.primaryContainer, background: K.surfaceMid, size: 48),
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
    final live = guardSupported && _g.has('notifications');
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: PageBody(children: [
          Row(children: [
            const Expanded(
              child: PageTitle('Scam Monitor'),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              // While the monitor cannot read alerts, a bell above "Off"
              // opens the Android setting that turns it on.
              if (guardSupported && !live) ...[
                IconButton(
                  tooltip: 'Allow reading new messages',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.85),
                    foregroundColor: K.error,
                    side: const BorderSide(color: K.glassEdge),
                  ),
                  icon: const Icon(Icons.notifications_active_outlined, size: 22),
                  onPressed: () => openGuardSetting('notifications'),
                ),
                const SizedBox(height: 4),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: live ? K.surfaceMid : K.errorContainer, borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  live ? const PulseDot(color: K.primary, size: 7) : const Icon(Icons.pause_circle_outline_rounded, size: 14, color: K.error),
                  const SizedBox(width: 6),
                  Text(live ? 'Active' : 'Off', style: t.labelMedium?.copyWith(color: live ? K.primary : K.error)),
                ]),
              ),
            ]),
          ]),
          const SizedBox(height: 24),
          if (!guardSupported)
            const KCard(child: Text('The Scam Monitor works on Android phones.'))
          else if (s == null)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else ...[
            KSection(
              'This week',
              first: true,
              info: 'Messages Kantoi checked each day, with the ones it warned you about in red. Pull down to refresh.',
              children: [
                Reveal(child: KCard(padding: const EdgeInsets.fromLTRB(20, 18, 20, 16), child: _WeekChart(days: s.lastDays(7)))),
                Reveal(index: 1, child: _Summary(s: s, week: s.lastDays(7))),
              ],
            ),
            KSection(
              'Apps',
              info: 'Tap an app to see its warnings and how much of its alerts Kantoi can read. Switch one off to stop watching it.',
              trailing: Text('${s.watching} of ${s.installed.length} watched', style: t.labelMedium?.copyWith(color: K.secondary)),
              children: [
                KGroup(children: [
                  for (final a in s.installed)
                    _AppRow(a: a, today: s.today, onToggle: (v) async {
                      await setAppMonitored(a.pkg, v);
                      _load();
                    }, onOpen: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MonitorAppPage(app: a, status: _g)))),
                  if (s.installed.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('None of the supported apps is installed.')),
                  _notInstalled(t, s),
                ]),
              ],
            ),
            KSection(
              'Settings',
              info: 'Hide scam notifications: when a message is very likely a scam, Kantoi removes its alert and shows its own warning instead.',
              children: [
                KCard(
                  padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                  child: Row(children: [
                    const TintIcon(Icons.notifications_off_outlined, background: K.surfaceMid, size: 38),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Hide scam notifications', style: t.titleMedium)),
                    Switch(
                      value: s.hideScams,
                      onChanged: (v) async {
                        await setHideScams(v);
                        _load();
                      },
                    ),
                  ]),
                ),
              ],
            ),
          ],
        ]),
      ),
    );
  }

  /// The last row of the apps list: the supported apps that are not on this
  /// phone, folded away until asked for.
  Widget _notInstalled(TextTheme t, MonitorSnapshot s) => Column(children: [
        InkWell(
          onTap: () => setState(() => _showAll = !_showAll),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              const Icon(Icons.apps_rounded, color: K.secondary, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text('${s.notInstalled.length} more supported apps', style: t.bodyMedium?.copyWith(color: K.secondary))),
              AnimatedRotation(turns: _showAll ? 0.5 : 0, duration: K.fast, child: const Icon(Icons.expand_more_rounded, color: K.secondary)),
            ]),
          ),
        ),
        AnimatedSize(
                  duration: K.medium,
                  curve: K.curve,
                  alignment: Alignment.topCenter,
                  child: !_showAll
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final a in s.notInstalled)
                              Container(
                                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                                decoration: BoxDecoration(color: K.surfaceLow, borderRadius: BorderRadius.circular(99)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  AppTile(a.name, size: 24),
                                  const SizedBox(width: 8),
                                  Text(a.name, style: t.labelMedium),
                                ]),
                              ),
                          ]),
                        ),
                ),
      ]);
}

/// The week in four figures, two to a row.
class _Summary extends StatelessWidget {
  final MonitorSnapshot s;
  final List<(String, int, int)> week;
  const _Summary({required this.s, required this.week});

  @override
  Widget build(BuildContext context) {
    final checked = week.fold(0, (a, d) => a + d.$2 + d.$3);
    final caught = week.fold(0, (a, d) => a + d.$3);
    return StatGrid([
      StatTile(
        label: 'Watching',
        value: '${s.watching}',
        caption: '${s.watching} of ${s.installed.length} apps',
        icon: Icons.apps_rounded,
      ),
      StatTile(
        label: 'Alerts',
        value: '${s.alertsToday}',
        caption: 'Today',
        icon: Icons.notifications_none_rounded,
        valueColor: s.alertsToday > 0 ? K.error : K.onSurface,
      ),
      StatTile(label: 'Checked', value: '$checked', caption: 'Last 7 days', icon: Icons.mark_email_read_outlined),
      StatTile(
        label: 'Caught',
        value: '$caught',
        caption: 'Last 7 days',
        icon: Icons.gpp_maybe_outlined,
        valueColor: caught > 0 ? K.error : K.onSurface,
      ),
    ]);
  }
}

/// Seven days drawn as clusters of thin lines: grey for messages checked,
/// red for the ones Kantoi warned about, navy for today.
class _WeekChart extends StatelessWidget {
  final List<(String, int, int)> days;
  const _WeekChart({required this.days});

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _short(String key) {
    final d = DateTime.parse(key);
    return '${d.day} ${_months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final max = days.fold<int>(1, (m, d) => d.$2 + d.$3 > m ? d.$2 + d.$3 : m);
    final total = days.fold(0, (a, d) => a + d.$2 + d.$3);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Overview', style: t.headlineSmall),
            const SizedBox(height: 4),
            Text('${_short(days.first.$1)} – ${_short(days.last.$1)}'.toUpperCase(), style: monoCaps()),
          ]),
        ),
        BigNumber('$total', unit: ' checked', size: 26),
      ]),
      const SizedBox(height: 18),
      SizedBox(
        height: 110,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (i, d) in days.indexed)
            Expanded(
              child: Tooltip(
                message: '${d.$2 + d.$3} checked, ${d.$3} warned',
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 400 + i * 60),
                  curve: K.curve,
                  builder: (_, f, _) {
                    final h = (100 * f * (d.$2 + d.$3) / max).clamp(6.0, 100.0);
                    final red = d.$2 + d.$3 == 0 ? 0.0 : h * d.$3 / (d.$2 + d.$3);
                    final today = i == days.length - 1;
                    final base = today ? K.navy : (d.$2 + d.$3 == 0 ? K.surfaceHigh : const Color(0xFFC7CDD6));
                    return Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      for (var k = 0; k < 5; k++) ...[
                        if (k > 0) const SizedBox(width: 2.5),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          if (red > 0) Container(width: 1.6, height: red, color: K.error),
                          Container(width: 1.6, height: h - red, color: base),
                        ]),
                      ],
                    ]);
                  },
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Text(_short(days.first.$1).toUpperCase(), style: monoCaps()),
        const Spacer(),
        Container(width: 6, height: 6, decoration: const BoxDecoration(color: K.error, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('WARNED', style: monoCaps()),
        const Spacer(),
        Text('TODAY', style: monoCaps(color: K.navy)),
      ]),
    ]);
  }
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
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          AppTile(a.name, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              const SizedBox(height: 2),
              Text(
                !a.on ? 'Paused' : (n > 0 ? '$n alert${n == 1 ? '' : 's'} today' : 'No alerts today'),
                style: t.bodySmall?.copyWith(color: n > 0 && a.on ? K.error : K.secondary),
              ),
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
    int count(String l) => l == 'all' ? all.length : all.where((x) => x.level == l).length;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Check detail')),
      body: PageBody(children: [
        KCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Row(children: [
                AppTile(a.name, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.name, style: t.titleLarge),
                  ]),
                ),
                Column(children: [
                  Switch(
                    value: _on,
                    onChanged: (v) async {
                      await setAppMonitored(a.pkg, v);
                      setState(() => _on = v);
                    },
                  ),
                  Text(_on ? 'Watching' : 'Paused', style: t.labelSmall?.copyWith(color: K.secondary)),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(coverageHelp(a.coverage), style: t.bodySmall?.copyWith(color: K.secondary)),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(color: K.surfaceLow, borderRadius: K.r8),
              child: Row(children: [
                const Icon(Icons.fact_check_outlined, size: 18, color: K.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Last 2 weeks', style: t.bodyMedium)),
                Text('${a.checked} checked · ${a.alerts} warned', style: t.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(children: [
            for (final (v, label, col) in [
              ('all', 'All', K.primary),
              ('danger', 'High risk', K.red),
              ('suspicious', 'Suspicious', K.orange),
              ('caution', 'Careful', K.amber),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(label: label, n: count(v), color: col, selected: _filter == v, onTap: () => setState(() => _filter = v)),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              const TintIcon(Icons.verified_user_outlined, background: K.surfaceMid, size: 56),
              const SizedBox(height: 12),
              Text(all.isEmpty ? 'No warnings from ${a.name} yet.' : 'Nothing at this level.',
                  textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
            ]),
          ),
        for (final (i, x) in shown.indexed)
          Reveal(
            index: i,
            child: Padding(padding: const EdgeInsets.only(bottom: 12), child: _AlertCard(alert: x, appName: a.name)),
          ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock_outline_rounded, size: 14, color: K.outline),
          const SizedBox(width: 6),
          Text('Checked on this phone. Nothing is uploaded.', style: t.labelSmall?.copyWith(color: K.outline)),
        ]),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int n;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.n, required this.color, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: selected ? K.primaryContainer : Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: selected ? Colors.white : K.onSurface)),
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: selected ? Colors.white.withValues(alpha: 0.2) : color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
                child: Text('$n',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : color)),
              ),
            ]),
          ),
        ),
      );
}

class _AlertCard extends StatelessWidget {
  final GuardAlert alert;
  final String appName;
  const _AlertCard({required this.alert, required this.appName});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = levelColor(alert.level);
    final danger = alert.level == 'danger';
    final h = alert.at.hour % 12 == 0 ? 12 : alert.at.hour % 12;
    final time = '${alert.at.day}/${alert.at.month} $h:${alert.at.minute.toString().padLeft(2, '0')} ${alert.at.hour < 12 ? 'AM' : 'PM'}';
    final label = alert.label.isEmpty ? alert.level : alert.label;
    return DecoratedBox(
      decoration: const BoxDecoration(borderRadius: K.r16, boxShadow: K.shadow),
      child: ClipRRect(
        borderRadius: K.r16,
        child: Container(
          color: Colors.white,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: c),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: c)),
                        ]),
                      ),
                      const Spacer(),
                      Text(time, style: t.labelMedium?.copyWith(color: K.secondary)),
                    ]),
                    const SizedBox(height: 10),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TintIcon(danger ? Icons.priority_high_rounded : Icons.help_outline_rounded, color: c, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(alert.chat.isEmpty ? appName : alert.chat,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      if (alert.headline.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: K.r8),
                            child: Text(alert.headline, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
                          ),
                        ),
                      ],
                    ]),
                    if (alert.text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: K.surfaceLow, borderRadius: K.r12),
                        child: Text(alert.text, maxLines: 4, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                      ),
                    ],
                    if (alert.reasons.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final r in alert.reasons.take(3))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: K.surfaceMid, borderRadius: BorderRadius.circular(6)),
                            child: Text(r, style: t.labelMedium?.copyWith(color: K.onSurfaceVariant)),
                          ),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(backgroundColor: K.surfaceMid, foregroundColor: K.primary, minimumSize: const Size(0, 46)),
                          icon: const Icon(Icons.travel_explore_rounded, size: 18),
                          label: const Text('Trace'),
                          onPressed: () {
                            Navigator.of(context).popUntil((r) => r.isFirst);
                            appState.openTrace(alert.target.isEmpty ? alert.text : alert.target);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: danger ? K.error : K.surfaceHigh,
                            foregroundColor: danger ? Colors.white : K.primary,
                            minimumSize: const Size(0, 46),
                          ),
                          icon: const Icon(Icons.flag_outlined, size: 18),
                          label: const Text('Report'),
                          onPressed: () {
                            Navigator.of(context).popUntil((r) => r.isFirst);
                            appState.openReport(
                                report: reportFromAlert(
                                    id: 'rep-${DateTime.now().millisecondsSinceEpoch}', app: alert.app, chat: alert.chat, text: alert.text, scamType: alert.headline));
                          },
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
