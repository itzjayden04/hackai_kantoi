import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../engine/attribution/graph.dart' show shortDate;
import '../history/history_log.dart';
import '../engine/attribution/intel_models.dart';
import '../engine/attribution/intel_store.dart';
import '../engine/forensics/tls_probe.dart';
import '../engine/sitecheck/site_check.dart' show SiteChecker;
import '../engine/trace/agent_model.dart' show GeminiAgentModel;
import '../engine/trace/trace_models.dart';
import '../engine/trace/tracer.dart' show Tracer;
import '../engine/webintel/web_intel.dart' show WebIntel;
import '../state.dart';
import 'activity_log.dart';
import 'intel_graph_view.dart';
import 'kit.dart';
import 'theme.dart';
import 'trace/site_summary.dart';
import 'trace/trace_canvas.dart';
import 'trace/trace_widgets.dart';


String _ago(DateTime d) {
  final days = DateTime.now().difference(d).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Made-up example data for the demo, not a real report',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
          child: const Text('Demo data', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
        ),
      );
}


/// Colours of the Trace screen: its blue header and the Scam watch list.
abstract final class _TC {
  /// "Scam watch" and the "TRY A DEMO" label.
  static const ink = Color(0xFF123F78);

  /// Icons and links on white.
  static const blue = Color(0xFF1D56C4);

  /// The Start trace bar.
  static const deep = K.navy;

  /// List rows and the tab track.
  static const card = Color(0xFFF6F7F9);
  static const track = Color(0xFFF1F3F6);

  /// The outline icons of reported scams.
  static const icon = Color(0xFF1A2B5F);
}

/// Two tabs in a grey pill track; the open one is a white pill with its
/// count in blue.
class _WatchTabs extends StatelessWidget {
  final List<(String, int)> tabs;
  final int selected;
  final ValueChanged<int> onSelect;
  const _WatchTabs({required this.tabs, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(color: _TC.track, borderRadius: BorderRadius.all(Radius.circular(99))),
      child: Row(children: [
        for (final (i, (label, n)) in tabs.indexed)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: K.fast,
                curve: K.curve,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: i == selected ? Colors.white : Colors.transparent,
                  borderRadius: const BorderRadius.all(Radius.circular(99)),
                  boxShadow: i == selected ? const [BoxShadow(color: Color(0x14111418), blurRadius: 10, offset: Offset(0, 3))] : null,
                ),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: label),
                    TextSpan(text: '   $n', style: TextStyle(color: i == selected ? _TC.blue : K.outline)),
                  ]),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(
                    fontSize: 15,
                    color: i == selected ? K.onSurface : K.outline,
                    fontWeight: i == selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// One Scam watch row: a light grey card with a white tile on the left,
/// a title and grey lines under it, and a chevron.
class _WatchRow extends StatelessWidget {
  final Widget tile;
  final String title;
  final List<Widget> lines;
  final VoidCallback onTap;
  const _WatchRow({required this.tile, required this.title, required this.lines, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _TC.card,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  boxShadow: [BoxShadow(color: Color(0x12111418), blurRadius: 10, offset: Offset(0, 3))],
                ),
                child: tile,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontSize: 16)),
                  const SizedBox(height: 2),
                  ...lines,
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: K.outline),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A brand's short mark in its own colour, for the white tile of a fake
/// website row ("S" in Shopee orange, "TnG" in Touch 'n Go blue).
class _BrandLetter extends StatelessWidget {
  final String brand;
  const _BrandLetter(this.brand);

  @override
  Widget build(BuildContext context) {
    final (color, mark, light) = brandLook(brand);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: FittedBox(
        child: Text(mark,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: light ? const Color(0xFFF59E0B) : color)),
      ),
    );
  }
}

/// "DEMO" in small capitals inside a hairline pill.
class _DemoChip extends StatelessWidget {
  const _DemoChip();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(99)),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Text('DEMO', style: monoCaps(size: 11, color: const Color(0xFF4B5563))),
      );
}

/// The Trace tab: a live investigation that builds a map from real lookups,
/// starting from a link, number, account, email or whole message.
class IntelPage extends StatefulWidget {
  /// For tests: the HTTP client each trace uses, whether to refresh the scam
  /// map from the internet when the tab opens, and whether to read
  /// certificates over a raw socket.
  final http.Client Function()? client;
  final bool autoCrawl;
  final bool probeCertificates;
  const IntelPage({super.key, this.client, this.autoCrawl = true, this.probeCertificates = true});
  @override
  State<IntelPage> createState() => _IntelPageState();
}

class _IntelPageState extends State<IntelPage> with WidgetsBindingObserver {
  final _q = TextEditingController();
  Tracer? _tracer;
  http.Client? _http;
  TraceState? _s;
  StreamSubscription<TraceEvent>? _sub;
  Timer? _clock;
  /// Keeps the scam map fresh while the app is open.
  Timer? _autoRefresh;
  int _v = 0;
  String? _selected;
  DateTime? _pausedAt;
  Duration _pausedFor = Duration.zero;
  /// Which Scam watch list is open: look-alike sites or known campaigns.
  int _watchTab = 0;
  /// Let the AI investigator lead traces (needs a Gemini key).
  bool _useAgent = true;

  bool get _agentAvailable => GeminiAgentModel.supports(appState.llm);

  bool get _running => _s != null && !_s!.finished;

  @override
  void initState() {
    super.initState();
    intel.addListener(_changed);
    appState.traceRequest.addListener(_onRequest);
    appState.backHandlers[1] = _back;
    // The scam map keeps itself fresh: when the tab opens, when the app comes
    // back to the front, and every few minutes while it is open. Each run
    // only goes online when the last one is older than [crawlEvery].
    unawaited(intel.ensureLoaded().then((_) => widget.autoCrawl ? intel.crawl() : null));
    if (widget.autoCrawl) {
      WidgetsBinding.instance.addObserver(this);
      _autoRefresh = Timer.periodic(const Duration(minutes: 5), (_) => intel.crawl());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRequest());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _onRequest() {
    final r = appState.traceRequest.value;
    if (r == null || !mounted) return;
    appState.traceRequest.value = null;
    if (r.trim().isEmpty) return;
    _q.text = r;
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) intel.crawl();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefresh?.cancel();
    intel.removeListener(_changed);
    appState.traceRequest.removeListener(_onRequest);
    if (appState.backHandlers[1] == _back) appState.backHandlers.remove(1);
    _stop();
    _q.dispose();
    super.dispose();
  }

  /// Back button: a running trace stops but keeps its map. A finished trace
  /// stays on screen until the user starts a new one, so back leaves the tab.
  bool _back() {
    if (!_running) return false;
    _tracer?.cancel();
    _tracer?.resume();
    return true;
  }

  /// Clears the map and shows the empty Trace screen for a new search.
  void _newTrace() {
    _stop();
    setState(() {
      _s = null;
      _tracer = null;
      _selected = null;
      _q.clear();
    });
  }

  void _stop() {
    _tracer?.cancel();
    _sub?.cancel();
    _sub = null;
    _clock?.cancel();
    _http?.close();
    _http = null;
  }

  Future<void> _start() async {
    final text = _q.text.trim();
    if (text.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _stop();
    if (!intel.loaded) await intel.ensureLoaded();
    if (!mounted) return;
    final client = widget.client?.call() ?? http.Client();
    final tracer = Tracer(
      client: client,
      graph: intel.graph,
      keys: appState.keys,
      tlsProbe: widget.probeCertificates && tlsProbeSupported ? (h) => probeTls(h) : null,
      // Public web reports (Google Search via Gemini when a key is set,
      // otherwise public search pages). The user's own details are skipped.
      webIntel: WebIntel(client: client, llm: appState.llm),
      ownDetails: appState.ownDetails,
      // What each website is for (page words, then Gemini on the page text
      // when a key is set) and its top-sites rank.
      siteChecker: SiteChecker(client: client, llm: appState.llm, keys: appState.keys),
      // The AI investigator chooses each next lookup; without it the
      // standard trace runs every lookup in a fixed order.
      agent: _useAgent && _agentAvailable ? GeminiAgentModel(appState.llm, client: client) : null,
      // A short beat between lookups so each step can be followed on the map.
      pace: const Duration(milliseconds: 250),
    );
    final s = TraceState();
    setState(() {
      _http = client;
      _tracer = tracer;
      _s = s;
      _selected = null;
      _pausedAt = null;
      _pausedFor = Duration.zero;
      _v++;
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _sub = tracer.run(text).listen((e) {
      if (!mounted || _s != s) return;
      setState(() {
        s.apply(e);
        _v++;
      });
      if (e is TraceFinished) _finished(s);
    });
  }

  void _finished(TraceState s) {
    _clock?.cancel();
    _http?.close();
    _http = null;
    if (s.cancelled || !mounted) return;
    final risks = s.flags.where((f) => f.isRisk).length;
    historyLog.add(HistoryEntry(HistoryType.trace, s.target,
        detail: '${s.entityCount} items, $risks warning sign${risks == 1 ? '' : 's'}', result: s.level.name, at: DateTime.now(), ref: s.target));
    showKToast(
      context,
      title: 'Trace complete',
      body: '${s.entityCount} items found, $risks warning sign${risks == 1 ? '' : 's'}. Tap to see the findings.',
      icon: Icons.radar_rounded,
      color: riskColor(s.level),
      onTap: _openFindings,
    );
  }

  void _togglePause() {
    final t = _tracer;
    if (t == null || !_running) return;
    setState(() {
      if (t.paused) {
        t.resume();
        if (_pausedAt != null) _pausedFor += DateTime.now().difference(_pausedAt!);
        _pausedAt = null;
      } else {
        t.pause();
        _pausedAt = DateTime.now();
      }
    });
  }

  Duration get _elapsed {
    final s = _s;
    if (s?.startedAt == null) return Duration.zero;
    final end = s!.finishedAt ?? _pausedAt ?? DateTime.now();
    final d = end.difference(s.startedAt!) - _pausedFor;
    return d.isNegative ? Duration.zero : d;
  }

  void _openFindings() {
    final s = _s;
    if (s == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TraceFindingsPage(state: s)));
  }

  void _inspect(String id) {
    final s = _s;
    if (s == null) return;
    setState(() => _selected = id);
    showTraceInspector(context, s, id).then((_) {
      if (mounted) setState(() => _selected = null);
    });
  }

  void _try(String v) {
    _q.text = v;
    _start();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final v = d?.text?.trim();
    if (v != null && v.isNotEmpty) setState(() => _q.text = v);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = _s;
    // Two parts: the navy header (A) to paste and start a trace, sitting on
    // the shell's navy wash, then a light sheet (B) with everything else.
    // Pull down to update the scam map straight away.
    return RefreshIndicator(
      onRefresh: () => intel.crawl(force: true),
      child: ListView(padding: EdgeInsets.zero, physics: const AlwaysScrollableScrollPhysics(), children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), child: _header(t, s)),
      Container(
        constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height * 0.85),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
        // Room at the bottom so the floating tab bar never covers the last section.
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: s == null ? _idle(context, t) : _trace(context, t, s),
        ),
      ),
    ]),
    );
  }

  /// Part A, on the blue wash: the big title, a light paste box with a Paste
  /// button, a deep blue Start trace bar and the two demo inputs as pills.
  Widget _header(TextTheme t, TraceState? s) {
    Widget demo(IconData icon, String label, String value) => Material(
            color: Colors.white,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => _try(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 17, color: _TC.blue),
                  const SizedBox(width: 6),
                  Text(label, maxLines: 1, style: t.labelLarge?.copyWith(color: _TC.blue, fontSize: 14)),
                ]),
              ),
            ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Trace', style: t.displaySmall?.copyWith(fontSize: 40, height: 46 / 40, fontWeight: FontWeight.w500, color: Colors.white)),
      const SizedBox(height: 20),
      // The paste box: search icon, the field, a divider and a Paste button.
      Container(
        decoration: BoxDecoration(
          color: const Color(0xC7FFFFFF),
          borderRadius: const BorderRadius.all(Radius.circular(30)),
          border: Border.all(color: const Color(0xE6FFFFFF)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
        child: Row(children: [
          const Icon(Icons.search_rounded, color: _TC.blue, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('trace-input'),
              controller: _q,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.search,
              style: t.bodyMedium?.copyWith(fontSize: 13, color: K.onSurface),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintText: 'Link, number, account or message',
                hintMaxLines: 1,
                hintStyle: t.bodyMedium?.copyWith(fontSize: 13, color: const Color(0xFF6B7280)),
              ),
              onSubmitted: (_) => _start(),
            ),
          ),
          Container(width: 1, height: 28, color: const Color(0x331D56C4)),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: _TC.blue, textStyle: t.titleMedium, padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: _paste,
            icon: const Icon(Icons.content_paste_rounded, size: 20),
            label: const Text('Paste'),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: _TC.deep,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 56),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w500),
        ),
        onPressed: _start,
        icon: const Icon(Icons.north_east_rounded, size: 20),
        label: Text(s == null ? 'Start trace' : 'Start new trace'),
      ),
      if (_agentAvailable)
        Theme(
          data: Theme.of(context).copyWith(
            listTileTheme: const ListTileThemeData(textColor: Colors.white, iconColor: Colors.white),
          ),
          child: SwitchListTile(
            key: const ValueKey('trace-agent-switch'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            dense: true,
            value: _useAgent,
            onChanged: (v) => setState(() => _useAgent = v),
            secondary: const Icon(Icons.psychology_rounded),
            title: const Text('AI investigator'),
          ),
        ),
      if (s == null) ...[
        const SizedBox(height: 18),
        // "TRY A DEMO" on the left, the two demo pills on the right; on a
        // narrow screen the pills shrink to fit.
        Row(children: [
          const SizedBox(width: 4),
          Text('TRY A DEMO', style: monoCaps(color: _TC.ink, size: 12)),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                demo(Icons.language_rounded, 'Parcel site', 'poslaju-my-redelivery.top'),
                const SizedBox(width: 10),
                demo(Icons.phone_outlined, 'Phone number', '+60 11-2004 7731'),
              ]),
            ),
          ),
        ]),
      ],
    ]);
  }

  List<Widget> _idle(BuildContext context, TextTheme t) {
    if (!intel.loaded) return const [Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))];
    final board = intel.trends();
    final sites = board.lookalikes;
    final demo = board.campaigns.every((c) => c.synthetic);
    // Look-alike websites and known campaigns share one card, switched by
    // underlined tabs; a list with nothing in it has no tab.
    final tabs = [
      if (board.lookalikes.isNotEmpty) ('Fake websites', board.lookalikes.length),
      if (board.campaigns.isNotEmpty) ('Reported scams', board.campaigns.length),
    ];
    final tab = _watchTab.clamp(0, tabs.isEmpty ? 0 : tabs.length - 1);
    final showSites = tabs.isNotEmpty && tabs[tab].$1 == 'Fake websites';
    final info = 'Fake websites: new addresses found in public certificate logs and scam feeds that pretend to be a real brand. '
            "Tap one to trace it. Don't open these addresses.\n\n"
            'Reported scams: groups of reports that come from the same scam.\n\n'
            'The scam map only reads public data: certificate logs, public scam feeds, domain records and news. '
            'It respects robots.txt, never logs in and never sends automated checks to government websites.\n\n'
            'It updates by itself while the app is open. Pull down to update it now. '
            '${intel.db.lastCrawl == null ? 'Not updated yet.' : 'Last updated ${_ago(intel.db.lastCrawl!)}, ${TimeOfDay.fromDateTime(intel.db.lastCrawl!).format(context)}.'}'
            '${intel.hasDemoData ? '\n\nItems marked "DEMO" are made-up examples so the map is not empty in the demo. They are not real reports.' : ''}';
    return [
      // "Scam watch" in the page's own font, large and in the header's ink blue.
      Row(children: [
        Expanded(
          child: Row(children: [
            Flexible(child: Text('Scam watch', maxLines: 1, style: t.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w500, color: _TC.ink))),
            const SizedBox(width: 6),
            InfoButton(
              title: 'Scam watch',
              message: info,
              color: K.secondary,
              body: intel.crawlLog.isEmpty ? null : SingleChildScrollView(child: ActivityLog(steps: intel.crawlLog)),
            ),
          ]),
        ),
        // A quiet spinner while it updates in the background.
        if (intel.crawling) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      if (tabs.isNotEmpty) ...[
        const SizedBox(height: 18),
        _WatchTabs(tabs: tabs, selected: tab, onSelect: (i) => setState(() => _watchTab = i)),
        const SizedBox(height: 16),
        if (showSites)
          for (final d in sites)
            _WatchRow(
              tile: _BrandLetter(d.brand ?? ''),
              title: d.key,
              lines: [
                Row(children: [
                  Flexible(child: Text('Pretends to be ${d.brand}', style: t.bodyMedium?.copyWith(color: K.outline))),
                  if (d.synthetic) ...[const SizedBox(width: 10), const _DemoChip()],
                ]),
              ],
              onTap: () => _try(d.key),
            )
        else
          for (final c in board.campaigns) _CampaignTile(c: c, badge: !demo),
      ],
    ];
  }

  List<Widget> _trace(BuildContext context, TextTheme t, TraceState s) {
    final paused = _tracer?.paused ?? false;
    final semak = s.nodes.values.where((n) => n.kind == TraceKind.phone || n.kind == TraceKind.account).toList();
    return [
      Row(children: [
        Expanded(child: Text('Live trace', style: t.titleLarge)),
        TextButton.icon(
          onPressed: _newTrace,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('New trace'),
        ),
      ]),
      const SizedBox(height: 8),
      TraceHud(state: s, elapsed: _elapsed, paused: paused),
      if (s.mainSite case final site?) ...[
        const SizedBox(height: 12),
        Reveal(child: SiteSummaryCard(site: site, compact: true)),
      ],
      const SizedBox(height: 12),
      SizedBox(
        height: 380,
        child: TraceCanvas(state: s, version: _v, running: _running && !paused, selected: _selected, onTap: _inspect),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: KProgressBar(value: s.progress, height: 6, color: s.finished ? K.green : K.primaryContainer)),
        const SizedBox(width: 10),
        Text(s.finished ? 'Done' : '${s.done} of ${s.total} lookups', style: traceMono.copyWith(fontSize: 11.5, color: K.onSurfaceVariant)),
      ]),
      const SizedBox(height: 4),
      Text('Tap a dot to inspect it. Pinch to zoom, drag to move.', style: t.bodySmall),
      if (s.agent || s.thoughts.isNotEmpty || s.agentNotes.isNotEmpty) ...[
        const SizedBox(height: 12),
        TraceAgentCard(state: s),
      ],
      const SizedBox(height: 12),
      TraceEntityCard(state: s),
      const SizedBox(height: 12),
      TraceAuditFeed(state: s, onShowAll: _openFindings),
      if (semak.isNotEmpty) ...[
        const SizedBox(height: 12),
        KCard(
          color: K.surfaceLow,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.local_police_outlined, color: K.primary),
              const SizedBox(width: 12),
              Expanded(child: Text('Also check ${semak.first.label} on the police Semak Mule site. Kantoi copies it for you.', style: t.bodyMedium)),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => openSemakMule(context, semak.first.kind == TraceKind.phone ? semak.first.label : semak.first.id.split(':').last),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Check on Semak Mule'),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _running ? _togglePause : _start,
            icon: Icon(_running ? (paused ? Icons.play_arrow_rounded : Icons.pause_rounded) : Icons.replay_rounded),
            label: Text(_running ? (paused ? 'Resume trace' : 'Pause trace') : 'Trace again'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => exportTracePdf(context, s),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Report PDF'),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      FilledButton.icon(onPressed: _openFindings, icon: const Icon(Icons.fact_check_outlined), label: const Text('View full findings')),
      const SizedBox(height: 12),
      Text(s.hasDemo ? 'Public records only. DEMO dots are made up.' : 'Public records only, as of now.',
          textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: K.outline)),
    ];
  }
}

class _CampaignTile extends StatelessWidget {
  final Campaign c;
  /// Off when the section title already says every campaign is demo data.
  final bool badge;
  const _CampaignTile({required this.c, this.badge = true});

  /// An icon for how the campaign reaches people, read from its name.
  IconData get _icon {
    final l = c.label.toLowerCase();
    if (l.contains('sms')) return Icons.mail_outline_rounded;
    if (l.contains('call')) return Icons.phone_outlined;
    if (l.contains('job')) return Icons.work_outline_rounded;
    if (l.contains('whatsapp') || l.contains('romance')) return Icons.chat_bubble_outline_rounded;
    if (l.contains('crypto') || l.contains('invest')) return Icons.payments_outlined;
    return Icons.hub_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // "Fake Pos Laju fee SMS, October wave" reads as the name, with
    // "October" on its own line under the counts.
    final cut = c.label.lastIndexOf(', ');
    final name = cut > 0 ? c.label.substring(0, cut) : c.label;
    final wave = cut > 0 ? c.label.substring(cut + 2).replaceAll(RegExp(r'\s*wave$'), '') : null;
    final grey = t.bodyMedium?.copyWith(color: K.outline);
    return _WatchRow(
      tile: Icon(_icon, color: _TC.icon, size: 26),
      title: name,
      lines: [
        Row(children: [
          Flexible(
            child: Text('${c.reports.length} report${c.reports.length == 1 ? '' : 's'} · ${c.domains} site${c.domains == 1 ? '' : 's'}',
                style: grey),
          ),
          if (c.synthetic && badge) ...[const SizedBox(width: 10), const _DemoChip()],
        ]),
        if (wave != null && wave.isNotEmpty) Text(wave, style: t.bodySmall?.copyWith(color: K.outline)),
      ],
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CampaignPage(campaign: c))),
    );
  }
}

/// A campaign's profile: when it started, who it targets, how it works, and
/// the evidence that ties it together.
class CampaignPage extends StatelessWidget {
  final Campaign campaign;
  const CampaignPage({super.key, required this.campaign});

  @override
  Widget build(BuildContext context) {
    final c = campaign;
    final t = Theme.of(context).textTheme;
    final g = intel.graph;
    final ents = c.entityIds.map((id) => g.nodes[id]).whereType<IntelEntity>().toList()..sort((a, b) => a.type.index.compareTo(b.type.index));
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(k, style: t.labelLarge)),
            Expanded(child: Text(v)),
          ]),
        );
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Scam campaign')),
      body: PageBody(children: [
        Row(children: [
          Expanded(child: Text(c.label, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
          if (c.synthetic) const DemoBadge(),
        ]),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              row('Type', c.scamType),
              if (c.brand != null) row('Pretends to be', c.brand!),
              row('First seen', shortDate(c.firstSeen)),
              row('Last active', shortDate(c.lastSeen)),
              row('Reports', '${c.reports.length}'),
              row('Linked details', NodeType.values.where((x) => (c.counts[x] ?? 0) > 0).map((x) => '${c.counts[x]} ${nodeTypeLabel(x).toLowerCase()}${c.counts[x]! > 1 ? 's' : ''}').join(', ')),
              if (c.targets.isNotEmpty) row('Targets', c.targets.join(', ')),
              if (c.tactics.isNotEmpty) row('Tactics', c.tactics.join(', ')),
              if (c.channels.isNotEmpty) row('Reaches people by', c.channels.join(', ')),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('Show the network'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IntelGraphPage(graph: g.campaignGraph(c), title: c.label))),
        ),
        const SectionTitle('What belongs to it'),
        Card(
          child: Column(children: [
            for (final e in ents.take(40))
              ListTile(
                dense: true,
                leading: Icon(nodeIcon(e.type), color: nodeColor(e.type)),
                title: Text(e.display, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${nodeTypeLabel(e.type)} · ${sourceLabel(e.source)}'),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Text('Account owners are never shown. Mule accounts are often held by people who were tricked into lending them.', style: t.bodySmall),
      ]),
    );
  }
}

/// Settings: the optional abuse.ch key for the URLhaus feed, and a reset.
class IntelSettingsSection extends StatefulWidget {
  const IntelSettingsSection({super.key});
  @override
  State<IntelSettingsSection> createState() => _IntelSettingsSectionState();
}

class _IntelSettingsSectionState extends State<IntelSettingsSection> {
  late final _key = TextEditingController(text: intel.userAbusechKey);

  @override
  void initState() {
    super.initState();
    intel.ensureLoaded().then((_) {
      if (mounted && _key.text.isEmpty) _key.text = intel.userAbusechKey;
    });
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Scam map'),
      Text('Kantoi keeps a map of known scam websites, numbers and accounts on this device.', style: t.bodyMedium),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () async {
            await intel.reset();
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scam map cleared. Demo data reloaded.')));
          },
          child: const Text('Clear the scam map on this device'),
        ),
      ),
    ]);
  }
}
