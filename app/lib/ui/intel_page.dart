import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/attribution/graph.dart' show shortDate;
import '../engine/attribution/intel_models.dart';
import '../engine/attribution/intel_store.dart';
import 'activity_log.dart';
import 'intel_graph_view.dart';
import 'theme.dart';

const semakMuleUrl = 'https://semakmule.rmp.gov.my';

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

/// The Scam map tab: "Before you pay" check, then this week's trends.
class IntelPage extends StatefulWidget {
  const IntelPage({super.key});
  @override
  State<IntelPage> createState() => _IntelPageState();
}

class _IntelPageState extends State<IntelPage> {
  final _q = TextEditingController();
  QuickCheckResult? _check;
  bool _showLog = false;

  @override
  void initState() {
    super.initState();
    intel.addListener(_changed);
    // Refresh in the background when the last crawl is a few hours old.
    unawaited(intel.ensureLoaded().then((_) => intel.crawl()));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    intel.removeListener(_changed);
    _q.dispose();
    super.dispose();
  }

  void _run() {
    if (_q.text.trim().isEmpty) return;
    setState(() => _check = intel.quickCheck(_q.text));
  }

  Future<void> _photo() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp'])
    ]);
    if (f == null) return;
    final r = intel.checkPhoto(await f.readAsBytes());
    if (mounted) setState(() => _check = r);
  }

  void _semakMule() {
    final v = _q.text.trim();
    if (v.isNotEmpty) Clipboard.setData(ClipboardData(text: v.replaceAll(RegExp(r'[\s-]'), '')));
    launchUrl(Uri.parse(semakMuleUrl), mode: LaunchMode.externalApplication);
    if (v.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Number copied. Paste it into Semak Mule.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (!intel.loaded) return const Center(child: CircularProgressIndicator());
    final board = intel.trends();
    final maxType = board.topTypes.isEmpty ? 1 : board.topTypes.first.$2;
    return PageBody(children: [
      Text('Scam map', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('Which scams are going around in Malaysia, and which websites, numbers and accounts belong together. Kantoi never names people.',
          style: t.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
      const SectionTitle('Before you pay'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Enter the account or phone number you were asked to pay. Kantoi checks it against scams it knows.', style: t.bodyMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _q,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'e.g. 5123 4567 8901 or 012-345 6789',
                suffixIcon: IconButton(tooltip: 'Check', icon: const Icon(Icons.search_rounded), onPressed: _run),
              ),
              onChanged: (_) => setState(() => _check = null),
              onSubmitted: (_) => _run(),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(onPressed: _run, icon: const Icon(Icons.search_rounded), label: const Text('Check')),
              OutlinedButton.icon(onPressed: _semakMule, icon: const Icon(Icons.open_in_new_rounded), label: const Text('Also check on Semak Mule (PDRM)')),
              TextButton.icon(onPressed: _photo, icon: const Icon(Icons.face_outlined), label: const Text('Check a profile photo')),
            ]),
            if (_check != null) ...[const SizedBox(height: 12), _CheckResult(r: _check!)],
          ]),
        ),
      ),
      if (board.topTypes.isNotEmpty) ...[
        const SectionTitle("This week's top scams"),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              for (final (type, n) in board.topTypes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(width: 200, child: Text(type, maxLines: 2)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: n / maxType, minHeight: 10, backgroundColor: scheme.surfaceContainerHighest),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$n', style: t.labelLarge),
                  ]),
                ),
              Align(alignment: Alignment.centerLeft, child: Text('Reports and news stories from the last 7 days.', style: t.bodySmall)),
            ]),
          ),
        ),
      ],
      if (board.campaigns.isNotEmpty) ...[
        const SectionTitle('Active campaigns'),
        for (final c in board.campaigns) _CampaignTile(c: c),
      ],
      if (board.lookalikes.isNotEmpty) ...[
        const SectionTitle('Newest look-alike websites'),
        Card(
          child: Column(children: [
            for (final d in board.lookalikes)
              ListTile(
                leading: Icon(Icons.language_rounded, color: nodeColor(NodeType.domain)),
                title: Text(d.key, style: const TextStyle(fontFamily: 'monospace')),
                subtitle: Text('Pretends to be ${d.brand} · seen ${_ago(d.firstSeen)} · ${sourceLabel(d.source)}'),
                trailing: d.synthetic ? const DemoBadge() : null,
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Text("Found in public certificate logs and scam feeds, often before anyone reports them. Don't open these addresses.", style: t.bodySmall),
      ],
      if (board.news.isNotEmpty) ...[
        const SectionTitle('In the news'),
        Card(
          child: Column(children: [
            for (final n in board.news)
              ListTile(
                leading: const Icon(Icons.newspaper_rounded),
                title: Text(n.title),
                subtitle: Text('${n.source} · ${_ago(n.at)} · ${n.scamType}'),
                trailing: n.synthetic ? const DemoBadge() : const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: n.link.isEmpty ? null : () => launchUrl(Uri.parse(n.link), mode: LaunchMode.externalApplication),
              ),
          ]),
        ),
      ],
      SectionTitle('Updates',
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
        'Kantoi only reads public data: certificate logs, public scam feeds, domain records and news. '
        'It respects robots.txt, never logs in, never looks at social media profiles and never sends automated checks to government websites.',
        style: t.bodySmall,
      ),
      if (intel.hasDemoData) ...[
        const SizedBox(height: 6),
        Text('Items marked "Demo data" are made-up examples so the map is not empty in the demo. They are not real reports.',
            style: t.bodySmall?.copyWith(color: const Color(0xFF92400E))),
      ],
    ]);
  }
}

class _CheckResult extends StatelessWidget {
  final QuickCheckResult r;
  const _CheckResult({required this.r});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = r.found ? const Color(0xFFDC2626) : const Color(0xFF15803D);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(r.found ? Icons.gpp_bad_rounded : Icons.help_outline_rounded, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.found ? 'Stop. This ${r.kind} is linked to scams.' : 'This ${r.kind} is not in Kantoi\'s scam database.',
              style: t.titleSmall?.copyWith(color: c, fontWeight: FontWeight.w800),
            ),
          ),
          if (r.demo) const DemoBadge(),
        ]),
        const SizedBox(height: 6),
        if (r.found) ...[
          Text(
            [
              if (r.reports > 0) 'It appears in ${r.reports} scam report${r.reports == 1 ? '' : 's'}.',
              if (r.campaign != null) 'It belongs to the campaign "${r.campaign!.label}".',
              "Don't pay. If you already paid, call 997 now.",
            ].join(' '),
            style: t.bodyMedium,
          ),
          if (r.campaign != null)
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CampaignPage(campaign: r.campaign!))),
              child: const Text('See the campaign'),
            ),
        ] else
          Text('That does not prove it is safe. New scam accounts appear every day, so also check it on Semak Mule.', style: t.bodyMedium),
      ]),
    );
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
