import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../engine/attribution/graph.dart' show shortDate;
import '../engine/attribution/intel_models.dart';
import '../engine/attribution/intel_store.dart';
import '../engine/forensics/tls_probe.dart';
import '../engine/trace/trace_models.dart';
import '../engine/trace/tracer.dart' show Tracer;
import '../engine/webintel/web_intel.dart' show WebIntel;
import '../state.dart';
import 'activity_log.dart';
import 'intel_graph_view.dart';
import 'kit.dart';
import 'theme.dart';
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

class _IntelPageState extends State<IntelPage> {
  final _q = TextEditingController();
  Tracer? _tracer;
  http.Client? _http;
  TraceState? _s;
  StreamSubscription<TraceEvent>? _sub;
  Timer? _clock;
  int _v = 0;
  String? _selected;
  DateTime? _pausedAt;
  Duration _pausedFor = Duration.zero;
  bool _showLog = false;

  bool get _running => _s != null && !_s!.finished;

  @override
  void initState() {
    super.initState();
    intel.addListener(_changed);
    appState.traceRequest.addListener(_onRequest);
    // Refresh in the background when the last crawl is a few hours old.
    unawaited(intel.ensureLoaded().then((_) => widget.autoCrawl ? intel.crawl() : null));
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
  void dispose() {
    intel.removeListener(_changed);
    appState.traceRequest.removeListener(_onRequest);
    _stop();
    _q.dispose();
    super.dispose();
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
    return PageBody(children: [
      if (s == null) ...[
        Text('Trace', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Follow a scam link, number or account to see where it really leads. Kantoi looks it up live and draws the map as it goes.',
            style: t.bodyLarge?.copyWith(color: K.onSurfaceVariant)),
        const SizedBox(height: 16),
      ],
      _inputBar(),
      if (s == null) ..._idle(context, t) else ..._trace(context, t, s),
    ]);
  }

  Widget _inputBar() => KCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            key: const ValueKey('trace-input'),
            controller: _q,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Paste a link, number, account or message',
              prefixIcon: const Icon(Icons.travel_explore_rounded),
              suffixIcon: IconButton(tooltip: 'Paste', icon: const Icon(Icons.content_paste_rounded), onPressed: _paste),
            ),
            onSubmitted: (_) => _start(),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.radar_rounded),
            label: Text(_s == null ? 'Start trace' : 'Start new trace'),
          ),
        ]),
      );

  List<Widget> _idle(BuildContext context, TextTheme t) {
    if (!intel.loaded) return const [Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))];
    final board = intel.trends();
    Widget how(IconData i, Color c, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [Icon(i, size: 18, color: c), const SizedBox(width: 10), Expanded(child: Text(text, style: t.bodyMedium))]),
        );
    return [
      const SectionTitle('How a trace works'),
      KCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          how(Icons.cloud_outlined, K.primaryContainer, 'Follows redirects and asks public records: domain registry, DNS, certificate logs and IP owners.'),
          how(Icons.lock_outline_rounded, K.green, 'Checks look-alike names, number formats and the scam map saved on this phone.'),
          how(Icons.hub_outlined, K.primary, 'Draws every server, nameserver, certificate and country it finds, live.'),
          const SizedBox(height: 6),
          Text('Passive lookups only: Kantoi never scans, logs in to or attacks anything.', style: t.bodySmall),
        ]),
      ),
      const SectionTitle('Try it', trailing: DemoBadge()),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ActionChip(avatar: const Icon(Icons.language_rounded, size: 18), label: const Text('A fake parcel site'), onPressed: () => _try('poslaju-my-redelivery.top')),
        ActionChip(avatar: const Icon(Icons.phone_outlined, size: 18), label: const Text('A scam number'), onPressed: () => _try('+60 11-2004 7731')),
      ]),
      const SizedBox(height: 6),
      Text('These examples come from the demo data bundled with Kantoi. The sites are made up, so the live lookups find little.', style: t.bodySmall),
      if (board.lookalikes.isNotEmpty) ...[
        const SectionTitle('Newest look-alike websites'),
        KCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final d in board.lookalikes)
              ListTile(
                leading: Icon(Icons.language_rounded, color: nodeColor(NodeType.domain)),
                title: Text(d.key, style: const TextStyle(fontFamily: 'monospace')),
                subtitle: Text('Pretends to be ${d.brand} · seen ${_ago(d.firstSeen)} · ${sourceLabel(d.source)}'),
                trailing: d.synthetic ? const DemoBadge() : const Icon(Icons.radar_rounded),
                onTap: () => _try(d.key),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Text("Found in public certificate logs and scam feeds. Tap one to trace it. Don't open these addresses.", style: t.bodySmall),
      ],
      if (board.campaigns.isNotEmpty) ...[
        SectionTitle('Known campaigns', trailing: board.campaigns.every((c) => c.synthetic) ? const DemoBadge() : null),
        for (final c in board.campaigns) _CampaignTile(c: c),
      ],
      SectionTitle('Scam map updates',
          trailing: TextButton.icon(
            onPressed: intel.crawling ? null : () => intel.crawl(force: true),
            icon: intel.crawling
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
            label: Text(intel.crawling ? 'Updating…' : 'Refresh now'),
          )),
      Text(
        intel.db.lastCrawl == null ? 'Not updated from the internet yet.' : 'Last updated ${_ago(intel.db.lastCrawl!)} at ${TimeOfDay.fromDateTime(intel.db.lastCrawl!).format(context)}.',
        style: t.bodyMedium,
      ),
      if (intel.crawlLog.isNotEmpty) ...[
        TextButton(
          onPressed: () => setState(() => _showLog = !_showLog),
          child: Text(_showLog ? 'Hide what Kantoi checked' : 'Show what Kantoi checked (${intel.crawlLog.length} steps)'),
        ),
        if (_showLog || intel.crawling) ActivityLog(steps: intel.crawlLog),
      ],
      const SizedBox(height: 10),
      Text(
        'The scam map only reads public data: certificate logs, public scam feeds, domain records and news. '
        'It respects robots.txt, never logs in and never sends automated checks to government websites.',
        style: t.bodySmall,
      ),
      if (intel.hasDemoData) ...[
        const SizedBox(height: 6),
        Text('Items marked "Demo data" are made-up examples so the map is not empty in the demo. They are not real reports.',
            style: t.bodySmall?.copyWith(color: const Color(0xFF92400E))),
      ],
    ];
  }

  List<Widget> _trace(BuildContext context, TextTheme t, TraceState s) {
    final paused = _tracer?.paused ?? false;
    final semak = s.nodes.values.where((n) => n.kind == TraceKind.phone || n.kind == TraceKind.account).toList();
    return [
      const SizedBox(height: 16),
      TraceHud(state: s, elapsed: _elapsed, paused: paused),
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
            label: const Text('Police PDF'),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      FilledButton.icon(onPressed: _openFindings, icon: const Icon(Icons.fact_check_outlined), label: const Text('View full findings')),
      const SizedBox(height: 12),
      Text('Passive lookups only. Results show what public records say right now; scammers change servers often.', style: t.bodySmall),
      if (s.hasDemo) ...[
        const SizedBox(height: 6),
        Text('Dots marked DEMO come from made-up demo data bundled with Kantoi, not from real reports.',
            style: t.bodySmall?.copyWith(color: const Color(0xFF92400E))),
      ],
    ];
  }
}

class _CampaignTile extends StatelessWidget {
  final Campaign c;
  const _CampaignTile({required this.c});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CampaignPage(campaign: c))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c.label, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                if (c.synthetic) const DemoBadge(),
              ]),
              const SizedBox(height: 4),
              Text(
                'First seen ${shortDate(c.firstSeen)} · last active ${_ago(c.lastSeen)} · ${c.reports.length} report${c.reports.length == 1 ? '' : 's'} · '
                '${c.domains} website${c.domains == 1 ? '' : 's'}',
                style: t.bodySmall,
              ),
              if (c.targets.isNotEmpty || c.channels.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text([if (c.targets.isNotEmpty) 'Targets ${c.targets.join(', ').toLowerCase()}', if (c.channels.isNotEmpty) 'via ${c.channels.join(', ')}'].join(' '),
                    style: t.bodyMedium),
              ],
            ]),
          ),
        ),
      ),
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
      appBar: AppBar(title: const Text('Scam campaign')),
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
