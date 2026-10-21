import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../engine/models.dart';
import '../../engine/trace/trace_models.dart';
import '../../engine/trace/trace_pdf.dart';
import '../../engine/trace/tracer.dart' show semakMuleUrl;
import '../file_out.dart';
import '../kit.dart';
import '../theme.dart';
import 'trace_canvas.dart';

String clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

String elapsedText(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

String flagEmoji(String? code) {
  if (code == null || code.length != 2) return '';
  final c = code.toUpperCase();
  return String.fromCharCodes([0x1F1E6 + c.codeUnitAt(0) - 65, 0x1F1E6 + c.codeUnitAt(1) - 65]);
}

/// Opens the police Semak Mule site (it has no API) with the number copied,
/// so the user can paste it there.
Future<void> openSemakMule(BuildContext context, String? value) async {
  final v = value?.replaceAll(RegExp(r'[^\d+]'), '') ?? '';
  if (v.isNotEmpty) await Clipboard.setData(ClipboardData(text: v.replaceFirst('+', '')));
  await launchUrl(Uri.parse(semakMuleUrl), mode: LaunchMode.externalApplication);
  if (v.isNotEmpty && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied. Paste it into Semak Mule.')));
  }
}

Future<void> exportTracePdf(BuildContext context, TraceState s) async {
  final bytes = await buildTracePdf(s);
  final d = DateTime.now();
  final msg = await saveOrShare([
    (name: 'kantoi-trace-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.pdf', bytes: bytes, mime: 'application/pdf')
  ], subject: 'Kantoi scam trace');
  if (context.mounted) showSnack(context, msg);
}

Future<void> shareTraceText(BuildContext context, TraceState s) async {
  try {
    await SharePlus.instance.share(ShareParams(text: traceSummaryText(s), subject: 'Kantoi scam trace'));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: traceSummaryText(s)));
    if (context.mounted) showSnack(context, 'Copied the findings.');
  }
}

/// What a country was found through, e.g. "Server" or "Phone number".
String countryRole(TraceState s, TraceNode country) {
  final roles = <String>{};
  for (final e in s.edges.values.where((e) => e.to == country.id)) {
    final from = s.nodes[e.from];
    if (from == null) continue;
    roles.add(switch (from.kind) {
      TraceKind.hosting || TraceKind.ip => 'Server',
      TraceKind.phone => 'Phone number',
      _ => traceKindLabel(from.kind),
    });
  }
  return roles.join(', ');
}

// ---------------------------------------------------------------- HUD

class TraceHud extends StatelessWidget {
  final TraceState state;
  final Duration elapsed;
  final bool paused;
  const TraceHud({super.key, required this.state, required this.elapsed, required this.paused});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final running = !s.finished;
    final status = s.finished ? (s.cancelled ? 'Trace stopped' : 'Trace complete') : (paused ? 'Trace paused' : 'Live forensic trace');
    final statusColor = s.finished ? K.green : (paused ? K.amber : K.red);
    final lvl = riskColor(s.level);
    const muted = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: Color(0xFF94A3B8));
    final origin = s.originId == null ? null : s.nodes[s.originId];
    Widget stat(String k, Widget v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: muted), const SizedBox(height: 4), v]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: K.r16,
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1B2740), K.night]),
        border: Border.all(color: K.nightLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (running && !paused) PulseDot(color: statusColor, size: 9) else Icon(s.finished ? Icons.check_circle_rounded : Icons.pause_circle_rounded, size: 14, color: statusColor),
          const SizedBox(width: 8),
          Expanded(child: Text(status.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: statusColor))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: K.r8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.radar_rounded, size: 14, color: traceCyan),
              const SizedBox(width: 6),
              Text(elapsedText(elapsed), style: traceMono.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        const Text('Investigation canvas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 4),
        Row(children: [
          Icon(origin == null ? Icons.travel_explore_rounded : traceIcon(origin.kind), size: 15, color: origin?.flagged == true ? const Color(0xFFF87171) : const Color(0xFF93C5FD)),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Target: ${s.target.replaceAll(RegExp(r'\s+'), ' ')}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: traceMono.copyWith(fontSize: 12.5, color: origin?.flagged == true ? const Color(0xFFF87171) : const Color(0xFFCBD5E1))),
          ),
        ]),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: K.nightLine, height: 1)),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          stat('Risk level', Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: lvl, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(child: Text(traceRiskLabel(s.score), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color.lerp(lvl, Colors.white, 0.25)))),
          ])),
          stat('Nodes linked', Text('${s.entityCount} found', style: traceMono.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
          stat('Countries',
              Text(s.countries.isEmpty ? '–' : s.countries.join(' / '), style: traceMono.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- entities

class TraceEntityCard extends StatelessWidget {
  final TraceState state;
  const TraceEntityCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = Theme.of(context).textTheme;
    final counts = <TraceKind, int>{};
    for (final n in s.nodes.values) {
      if (n.id == s.originId) continue;
      counts[n.kind] = (counts[n.kind] ?? 0) + 1;
    }
    final countries = s.nodes.values.where((n) => n.kind == TraceKind.country).toList();
    return KCard(
      color: K.surfaceLow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: K.primaryContainer, borderRadius: K.r8),
            child: const Icon(Icons.account_tree_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.entityCount} related ${s.entityCount == 1 ? 'entity' : 'entities'} discovered', style: t.titleMedium),
              const SizedBox(height: 2),
              Text(
                  countries.isEmpty
                      ? 'No countries found yet'
                      : 'Spread across ${countries.length} ${countries.length == 1 ? 'country' : 'countries'}',
                  style: t.bodySmall),
            ]),
          ),
          if (s.flags.isNotEmpty) Pill(traceRiskLabel(s.score), color: riskColor(s.level)),
        ]),
        if (countries.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in countries)
              _Chip(icon: null, lead: flagEmoji(c.country), text: '${c.label}${countryRole(s, c).isEmpty ? '' : ' (${countryRole(s, c)})'}'),
          ]),
        ],
        if (counts.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in counts.entries) _Chip(icon: traceIcon(e.key), color: traceColor(e.key), text: '${traceKindLabel(e.key)} · ${e.value}'),
          ]),
        ],
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData? icon;
  final String? lead;
  final Color? color;
  final String text;
  const _Chip({this.icon, this.lead, this.color, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: K.surfaceHigh, borderRadius: K.r8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Icon(icon, size: 14, color: Color.lerp(color, K.onSurface, 0.35)),
          if (lead != null && lead!.isNotEmpty) Text(lead!, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: K.onSurface))),
        ]),
      );
}

// ---------------------------------------------------------------- audit feed

class TraceAuditFeed extends StatelessWidget {
  final TraceState state;
  final int max;
  final VoidCallback? onShowAll;
  const TraceAuditFeed({super.key, required this.state, this.max = 6, this.onShowAll});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = state.lookups.reversed.take(max).toList();
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.terminal_rounded, color: K.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('Investigation audit feed', style: t.titleMedium)),
          Text('${state.lookups.length} lookups', style: traceMono.copyWith(fontSize: 11, color: K.onSurfaceVariant)),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 12, runSpacing: 4, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline_rounded, size: 13, color: K.green),
            Text(' on this phone', style: t.labelSmall?.copyWith(color: K.onSurfaceVariant)),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_outlined, size: 13, color: K.primaryContainer),
            Text(' online lookup', style: t.labelSmall?.copyWith(color: K.onSurfaceVariant)),
          ]),
        ]),
        const Divider(height: 20),
        if (items.isEmpty) Text('Waiting for the first lookup…', style: t.bodySmall),
        for (final l in items) TraceLookupRow(key: ValueKey(l.id), lookup: l),
        if (onShowAll != null && state.lookups.length > max)
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: onShowAll, child: Text('Show all ${state.lookups.length} lookups'))),
      ]),
    );
  }
}

class TraceLookupRow extends StatelessWidget {
  final TraceLookup lookup;
  const TraceLookupRow({super.key, required this.lookup});

  @override
  Widget build(BuildContext context) {
    final l = lookup;
    final s = l.step;
    final alarm = l.alarming;
    final (IconData icon, Color c) = switch (s.status) {
      StepStatus.done => alarm ? (Icons.gavel_rounded, K.red) : (Icons.check_rounded, K.primaryContainer),
      StepStatus.failed => (Icons.close_rounded, K.amber),
      StepStatus.skipped => (Icons.remove_rounded, K.outline),
      StepStatus.running => (Icons.more_horiz_rounded, traceCyan),
    };
    final body = s.status == StepStatus.running ? '${s.action}…' : s.result;
    return Reveal(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: alarm ? const EdgeInsets.all(10) : const EdgeInsets.symmetric(vertical: 4),
        decoration: alarm ? BoxDecoration(color: K.errorContainer.withValues(alpha: 0.6), borderRadius: K.r8) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: s.status == StepStatus.running
                ? const Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2, color: traceCyan))
                : Icon(icon, size: 15, color: c),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(clock(s.at), style: traceMono.copyWith(fontSize: 11.5, color: alarm ? K.red : K.onSurfaceVariant, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Icon(l.online ? Icons.cloud_outlined : Icons.lock_outline_rounded, size: 13, color: l.online ? K.primaryContainer : K.green),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(s.tool,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: alarm ? K.red : K.primaryContainer)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(body, style: TextStyle(fontSize: 13.5, height: 1.35, color: alarm ? K.onErrorContainer : K.onSurface)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- inspector

Future<void> showTraceInspector(BuildContext context, TraceState s, String id) {
  final n = s.nodes[id];
  if (n == null) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => TraceNodeDetails(state: s, node: n, scroll: scroll),
    ),
  );
}

class TraceNodeDetails extends StatelessWidget {
  final TraceState state;
  final TraceNode node;
  final ScrollController? scroll;
  const TraceNodeDetails({super.key, required this.state, required this.node, this.scroll});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = node;
    final c = traceColor(n.kind);
    final links = state.edges.values.where((e) => e.from == n.id || e.to == n.id).toList();
    final flags = state.flags.where((f) => f.nodeId == n.id).toList();
    final lookups = state.lookups.where((l) => l.nodeId == n.id && l.step.status != StepStatus.running).toList();
    final semak = n.kind == TraceKind.phone || n.kind == TraceKind.account;
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: n.flagged ? K.errorContainer : c.withValues(alpha: 0.15), borderRadius: K.r16),
          child: Icon(traceIcon(n.kind), color: n.flagged ? K.red : Color.lerp(c, K.onSurface, 0.4)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(traceKindLabel(n.kind).toUpperCase(), style: t.labelSmall?.copyWith(color: n.flagged ? K.red : K.onSurfaceVariant))),
              if (n.parent == null) ...[const SizedBox(width: 6), const Pill('Origin', color: K.primary)],
              if (n.demo) ...[const SizedBox(width: 6), const Pill('Demo data', color: K.amber)],
            ]),
            const SizedBox(height: 2),
            SelectableText(n.label, style: t.titleLarge),
          ]),
        ),
      ]),
      if (n.demo) ...[
        const SizedBox(height: 8),
        Text('This comes from made-up demo data bundled with the app, not from a real report.', style: t.bodySmall?.copyWith(color: const Color(0xFF92400E))),
      ],
      const SizedBox(height: 14),
      if (n.facts.isEmpty) Text(n.parent == null ? 'The thing you asked Kantoi to trace.' : 'Found by the lookups below.', style: t.bodyMedium),
      for (final (k, v) in n.facts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: t.labelMedium?.copyWith(color: K.onSurfaceVariant))),
            Expanded(child: SelectableText(v, style: t.bodyMedium)),
          ]),
        ),
      if (n.kind == TraceKind.webReport)
        if (n.facts.where((f) => f.$1 == 'Link').firstOrNull case (_, final link)) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open the source page'),
          ),
          const SizedBox(height: 4),
          Text('Opens in your browser. Kantoi only shows pages a search actually returned.', style: t.bodySmall),
        ],
      if (flags.isNotEmpty) ...[
        const SectionTitle('Signs'),
        for (final f in flags)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(f.isRisk ? Icons.warning_amber_rounded : Icons.verified_outlined, color: f.isRisk ? K.red : K.green),
            title: Text(f.title, style: t.titleSmall),
            subtitle: Text(f.why),
          ),
      ],
      if (links.isNotEmpty) ...[
        const SectionTitle('Linked to'),
        for (final e in links)
          if (state.nodes[e.from == n.id ? e.to : e.from] case final o?)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(traceIcon(o.kind), color: Color.lerp(traceColor(o.kind), K.onSurface, 0.35), size: 20),
              title: Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(e.from == n.id ? '${traceKindLabel(o.kind)} · ${e.label}' : '${e.label} · from ${traceKindLabel(o.kind).toLowerCase()}'),
            ),
      ],
      if (lookups.isNotEmpty) ...[
        const SectionTitle('Lookups'),
        for (final l in lookups) TraceLookupRow(lookup: l),
      ],
      if (semak) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => openSemakMule(context, n.kind == TraceKind.phone ? n.label : n.id.split(':').last),
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Check on Semak Mule'),
        ),
        const SizedBox(height: 6),
        Text('Semak Mule is the police check for mule accounts and numbers. Kantoi copies the number for you; it never checks it automatically.',
            style: t.bodySmall),
      ],
    ]);
  }
}

// ---------------------------------------------------------------- full findings

class TraceFindingsPage extends StatelessWidget {
  final TraceState state;
  const TraceFindingsPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = Theme.of(context).textTheme;
    final risks = s.flags.where((f) => f.isRisk).toList();
    final good = s.flags.where((f) => !f.isRisk).toList();
    final semak = s.nodes.values.where((n) => n.kind == TraceKind.phone || n.kind == TraceKind.account).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Full findings'), actions: [
        IconButton(tooltip: 'Share as text', onPressed: () => shareTraceText(context, s), icon: const Icon(Icons.share_outlined)),
      ]),
      body: PageBody(children: [
        KCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(s.target.replaceAll(RegExp(r'\s+'), ' '), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium)),
              Pill(traceRiskLabel(s.score), color: riskColor(s.level)),
            ]),
            const SizedBox(height: 6),
            Text(
                '${s.entityCount} items found by ${s.lookups.length} lookups'
                '${s.countries.isEmpty ? '' : ' across ${s.countries.map(countryName).join(', ')}'}.'
                '${s.finished ? '' : ' The trace is still running.'}',
                style: t.bodyMedium),
          ]),
        ),
        if (risks.isNotEmpty) ...[
          const SectionTitle('Warning signs'),
          for (final f in risks)
            _FlagTile(f: f, node: f.nodeId == null ? null : s.nodes[f.nodeId], onTap: f.nodeId == null ? null : () => showTraceInspector(context, s, f.nodeId!)),
        ],
        if (good.isNotEmpty) ...[
          const SectionTitle('Reassuring signs'),
          for (final f in good) _FlagTile(f: f, node: null),
        ],
        const SectionTitle('Everything found'),
        for (final (k, ns) in traceGroups(s))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                shape: const Border(),
                leading: Icon(traceIcon(k), color: Color.lerp(traceColor(k), K.onSurface, 0.35)),
                title: Text('${traceKindLabel(k)} (${ns.length})', style: t.titleSmall),
                children: [
                  for (final n in ns)
                    ListTile(
                      dense: true,
                      title: Text(n.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: n.facts.isEmpty ? null : Text(n.facts.map((f) => '${f.$1}: ${f.$2}').join('\n'), maxLines: 4, overflow: TextOverflow.ellipsis),
                      trailing: n.demo ? const Pill('Demo', color: K.amber) : (n.flagged ? const Icon(Icons.warning_amber_rounded, color: K.red, size: 18) : null),
                      onTap: () => showTraceInspector(context, s, n.id),
                    ),
                ],
              ),
            ),
          ),
        if (semak.isNotEmpty) ...[
          const SectionTitle('Check with the police'),
          KCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Semak Mule (PDRM) shows whether an account or number has been reported. It has no public API, so check it yourself.', style: t.bodyMedium),
              const SizedBox(height: 10),
              for (final n in semak)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton.icon(
                    onPressed: () => openSemakMule(context, n.kind == TraceKind.phone ? n.label : n.id.split(':').last),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text('Check ${n.label} on Semak Mule', overflow: TextOverflow.ellipsis),
                  ),
                ),
            ]),
          ),
        ],
        SectionTitle('Lookup log (${s.lookups.length})'),
        KCard(child: Column(children: [for (final l in s.lookups) TraceLookupRow(lookup: l)])),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: () => exportTracePdf(context, s), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Police report PDF')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => shareTraceText(context, s), icon: const Icon(Icons.share_outlined), label: const Text('Share as text')),
        const SizedBox(height: 12),
        Text('Kantoi only used passive, public lookups. It did not scan, log in to or attack any system.', style: t.bodySmall),
        if (s.hasDemo) ...[
          const SizedBox(height: 6),
          Text('Items marked "Demo" are made-up examples bundled with the app, not real reports.', style: t.bodySmall?.copyWith(color: const Color(0xFF92400E))),
        ],
      ]),
    );
  }
}

class _FlagTile extends StatelessWidget {
  final TraceFlag f;
  final TraceNode? node;
  final VoidCallback? onTap;
  const _FlagTile({required this.f, this.node, this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: KCard(
          onTap: onTap,
          color: f.isRisk ? K.errorContainer.withValues(alpha: 0.35) : const Color(0xFFE7F6EC),
          borderColor: Colors.transparent,
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(f.isRisk ? Icons.warning_amber_rounded : Icons.verified_outlined, color: f.isRisk ? K.red : K.green),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(f.why, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            if (f.demo) const Pill('Demo', color: K.amber),
          ]),
        ),
      );
}
