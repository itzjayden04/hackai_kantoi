import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/attribution/graph.dart' show shortDate, clusterThreshold;
import '../engine/attribution/intel_models.dart';

Color nodeColor(NodeType t) => switch (t) {
      NodeType.domain => const Color(0xFF2563EB),
      NodeType.ip => const Color(0xFF64748B),
      NodeType.phone => const Color(0xFF16A34A),
      NodeType.bankAccount => const Color(0xFFDC2626),
      NodeType.wallet => const Color(0xFFD97706),
      NodeType.handle => const Color(0xFF7C3AED),
      NodeType.photo => const Color(0xFFDB2777),
      NodeType.template => const Color(0xFF0D9488),
    };

IconData nodeIcon(NodeType t) => switch (t) {
      NodeType.domain => Icons.language_rounded,
      NodeType.ip => Icons.dns_outlined,
      NodeType.phone => Icons.phone_outlined,
      NodeType.bankAccount => Icons.account_balance_outlined,
      NodeType.wallet => Icons.currency_bitcoin_rounded,
      NodeType.handle => Icons.alternate_email_rounded,
      NodeType.photo => Icons.face_outlined,
      NodeType.template => Icons.chat_bubble_outline_rounded,
    };

/// A full page with the explorable network for one campaign or one check.
class IntelGraphPage extends StatelessWidget {
  final Subgraph graph;
  final String title;
  const IntelGraphPage({super.key, required this.graph, this.title = 'Scam network'});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(child: IntelGraphView(graph: graph)),
      );
}

/// Force-directed drawing of a subgraph. Pinch or scroll to zoom, drag to
/// move, tap a dot to see what it is and why it is linked.
class IntelGraphView extends StatefulWidget {
  final Subgraph graph;
  const IntelGraphView({super.key, required this.graph});
  @override
  State<IntelGraphView> createState() => _IntelGraphViewState();
}

class _IntelGraphViewState extends State<IntelGraphView> {
  static const _size = Size(1000, 760);
  late Map<String, Offset> _pos = layoutGraph(widget.graph, _size);
  String? _selected;

  @override
  void didUpdateWidget(IntelGraphView old) {
    super.didUpdateWidget(old);
    if (old.graph != widget.graph) _pos = layoutGraph(widget.graph, _size);
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.graph.highlight.where(_pos.containsKey).firstOrNull;
  }

  void _tap(Offset p) {
    String? best;
    var bd = 30.0 * 30.0;
    for (final e in _pos.entries) {
      final d = (e.value - p).distanceSquared;
      if (d < bd) {
        bd = d;
        best = e.key;
      }
    }
    setState(() => _selected = best);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.graph;
    if (g.isEmpty) return const Center(child: Text('Nothing to show yet.'));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final demo = g.nodes.any((n) => n.synthetic);
    final canvas = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(
          'Tap a dot to see what it is and why it is linked. Lines show shared servers, accounts or wording.'
          '${demo ? ' Contains demo data.' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      _Legend(types: g.nodes.map((n) => n.type).toSet()),
      Expanded(
        child: ClipRect(
          child: InteractiveViewer(
            constrained: false,
            boundaryMargin: const EdgeInsets.all(400),
            minScale: 0.3,
            maxScale: 3,
            child: GestureDetector(
              onTapUp: (d) => _tap(d.localPosition),
              child: CustomPaint(
                size: _size,
                painter: _GraphPainter(g, _pos, _selected, Theme.of(context).colorScheme, Theme.of(context).textTheme.labelSmall!),
              ),
            ),
          ),
        ),
      ),
    ]);
    final details = _selected == null ? null : _Details(graph: g, id: _selected!, onPick: (id) => setState(() => _selected = id));
    if (wide) {
      return Row(children: [
        Expanded(child: canvas),
        if (details != null) SizedBox(width: 360, child: Material(elevation: 1, child: details)),
      ]);
    }
    return Column(children: [
      Expanded(flex: 3, child: canvas),
      if (details != null) Expanded(flex: 2, child: Material(elevation: 2, child: details)),
    ]);
  }
}

/// Fruchterman-Reingold layout, seeded so the same graph always looks the same.
Map<String, Offset> layoutGraph(Subgraph g, Size size, {int iterations = 300}) {
  final n = g.nodes.length;
  final ids = g.nodes.map((e) => e.id).toList();
  final rnd = math.Random(42);
  final c = Offset(size.width / 2, size.height / 2);
  final pos = <String, Offset>{
    for (var i = 0; i < n; i++)
      ids[i]: c + Offset.fromDirection(2 * math.pi * i / math.max(n, 1), size.shortestSide * 0.3) + Offset(rnd.nextDouble() * 10, rnd.nextDouble() * 10)
  };
  if (n <= 1) return {for (final id in ids) id: c};
  final k = math.sqrt(size.width * size.height / n) * 0.75;
  var temp = size.width / 8;
  for (var it = 0; it < iterations; it++) {
    final disp = <String, Offset>{for (final id in ids) id: Offset.zero};
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        var d = pos[ids[i]]! - pos[ids[j]]!;
        var dist = d.distance;
        if (dist < 0.01) {
          d = Offset(rnd.nextDouble() - 0.5, rnd.nextDouble() - 0.5);
          dist = d.distance;
        }
        final f = d / dist * (k * k / dist);
        disp[ids[i]] = disp[ids[i]]! + f;
        disp[ids[j]] = disp[ids[j]]! - f;
      }
    }
    for (final e in g.edges) {
      final a = pos[e.a], b = pos[e.b];
      if (a == null || b == null) continue;
      final d = a - b;
      final dist = math.max(d.distance, 0.01);
      final f = d / dist * (dist * dist / k) * (0.5 + e.strength);
      disp[e.a] = disp[e.a]! - f;
      disp[e.b] = disp[e.b]! + f;
    }
    for (final id in ids) {
      // A gentle pull to the middle keeps separate pieces on screen.
      final toCentre = (c - pos[id]!) * 0.01;
      final d = disp[id]! + toCentre;
      final len = math.max(d.distance, 0.01);
      final p = pos[id]! + d / len * math.min(len, temp);
      pos[id] = Offset(p.dx.clamp(40, size.width - 40), p.dy.clamp(40, size.height - 40));
    }
    temp = math.max(temp * 0.985, 1.5);
  }
  return pos;
}

class _GraphPainter extends CustomPainter {
  final Subgraph g;
  final Map<String, Offset> pos;
  final String? selected;
  final ColorScheme scheme;
  final TextStyle label;
  _GraphPainter(this.g, this.pos, this.selected, this.scheme, this.label);

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in g.edges) {
      final a = pos[e.a], b = pos[e.b];
      if (a == null || b == null) continue;
      final active = selected != null && (e.a == selected || e.b == selected);
      final p = Paint()
        ..color = (active ? scheme.primary : scheme.outline).withValues(alpha: active ? 0.9 : 0.25 + 0.5 * e.strength)
        ..strokeWidth = 1 + 2.5 * e.strength + (active ? 1 : 0);
      if (e.strength < clusterThreshold) {
        // Weak links are dashed.
        final d = b - a, len = d.distance;
        for (var t = 0.0; t < len; t += 10) {
          canvas.drawLine(a + d * (t / len), a + d * (math.min(t + 5, len) / len), p);
        }
      } else {
        canvas.drawLine(a, b, p);
      }
    }
    for (final n in g.nodes) {
      final o = pos[n.id];
      if (o == null) continue;
      final hl = g.highlight.contains(n.id);
      final sel = n.id == selected;
      final r = n.type == NodeType.template ? 13.0 : 11.0;
      if (hl) canvas.drawCircle(o, r + 7, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.45));
      if (sel) {
        canvas.drawCircle(o, r + 4, Paint()
          ..color = scheme.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
      }
      canvas.drawCircle(o, r, Paint()..color = nodeColor(n.type));
      canvas.drawCircle(o, r, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
      final text = n.display.length > 26 ? '${n.display.substring(0, 25)}…' : n.display;
      final tp = TextPainter(
        text: TextSpan(text: text, style: label.copyWith(color: scheme.onSurface, fontWeight: hl || sel ? FontWeight.w700 : null)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 180);
      tp.paint(canvas, o + Offset(-tp.width / 2, r + 4));
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) => old.selected != selected || old.g != g || old.pos != pos || old.scheme != scheme;
}

class _Legend extends StatelessWidget {
  final Set<NodeType> types;
  const _Legend({required this.types});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Wrap(spacing: 12, runSpacing: 4, children: [
          for (final t in NodeType.values.where(types.contains))
            Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 5, backgroundColor: nodeColor(t)),
              const SizedBox(width: 4),
              Text(nodeTypeLabel(t), style: Theme.of(context).textTheme.labelSmall),
            ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const CircleAvatar(radius: 5, backgroundColor: Color(0xFFF59E0B)),
            const SizedBox(width: 4),
            Text('What you checked', style: Theme.of(context).textTheme.labelSmall),
          ]),
        ]),
      );
}

class _Details extends StatelessWidget {
  final Subgraph graph;
  final String id;
  final void Function(String) onPick;
  const _Details({required this.graph, required this.id, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = graph.nodes.firstWhere((x) => x.id == id);
    final edges = graph.edges.where((e) => e.a == id || e.b == id).toList()..sort((a, b) => b.strength.compareTo(a.strength));
    final byId = {for (final x in graph.nodes) x.id: x};
    final facts = <String>[
      if (graph.highlight.contains(id)) 'From the item you checked',
      'Source: ${sourceLabel(n.source)}${n.synthetic ? ' (demo data, not a real report)' : ''}',
      'First seen ${shortDate(n.firstSeen)}',
      if (n.brand != null) 'Imitates ${n.brand}',
      if (n.registrar != null) 'Registrar: ${n.registrar}',
      if (n.created != null) 'Registered ${shortDate(n.created!)}',
      if (n.nameservers.isNotEmpty) 'Nameservers: ${n.nameservers.join(', ')}',
      if (n.ips.isNotEmpty) 'Server address: ${n.ips.join(', ')}',
      if (n.network != null) 'Hosting network: ${n.network}${n.country == null ? '' : ' (${n.country})'}',
      if (n.pageTitle != null) 'Page title: ${n.pageTitle}',
      if (n.type == NodeType.bankAccount) 'Owner not shown: mule accounts are often held by people tricked into lending them.',
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Icon(nodeIcon(n.type), color: nodeColor(n.type)),
        const SizedBox(width: 8),
        Expanded(child: Text(nodeTypeLabel(n.type), style: t.labelLarge)),
      ]),
      const SizedBox(height: 4),
      SelectableText(n.display, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      for (final f in facts) Text(f, style: t.bodySmall),
      const SizedBox(height: 12),
      Text(edges.isEmpty ? 'No links shown' : 'Linked because', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      for (final e in edges)
        if (byId[e.other(id)] case final o?)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(nodeIcon(o.type), color: nodeColor(o.type), size: 20),
            title: Text('${edgeLabel(e.kind)}: ${o.display}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${e.evidence}. Link strength ${(e.strength * 100).round()}%'),
            onTap: () => onPick(o.id),
          ),
    ]);
  }
}
