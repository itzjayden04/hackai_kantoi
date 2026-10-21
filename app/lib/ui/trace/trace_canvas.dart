import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/trace/trace_models.dart';
import '../theme.dart';

const traceCyan = Color(0xFF22D3EE);
const traceMono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['RobotoMono', 'Courier']);

Color traceColor(TraceKind k) => switch (k) {
      TraceKind.message || TraceKind.url || TraceKind.domain => const Color(0xFF60A5FA),
      TraceKind.subdomain || TraceKind.sibling => const Color(0xFF93C5FD),
      TraceKind.ip => const Color(0xFF94A3B8),
      TraceKind.nameserver || TraceKind.mail => traceCyan,
      TraceKind.cert => const Color(0xFF2DD4BF),
      TraceKind.hosting => const Color(0xFFA78BFA),
      TraceKind.country => const Color(0xFF4ADE80),
      TraceKind.phone => const Color(0xFFFBBF24),
      TraceKind.account => const Color(0xFFFB923C),
      TraceKind.email => const Color(0xFFF472B6),
      TraceKind.brand => const Color(0xFFF87171),
      TraceKind.related => const Color(0xFFFF6B6B),
      TraceKind.webReport => const Color(0xFFE11D48),
      TraceKind.purpose => const Color(0xFFF59E0B),
      TraceKind.reputation => const Color(0xFF34D399),
    };

IconData traceIcon(TraceKind k) => switch (k) {
      TraceKind.message => Icons.chat_bubble_outline_rounded,
      TraceKind.url => Icons.link_rounded,
      TraceKind.domain => Icons.language_rounded,
      TraceKind.subdomain => Icons.subdirectory_arrow_right_rounded,
      TraceKind.sibling => Icons.copy_all_outlined,
      TraceKind.ip => Icons.router_outlined,
      TraceKind.nameserver => Icons.dns_outlined,
      TraceKind.mail => Icons.mail_outline_rounded,
      TraceKind.cert => Icons.lock_outline_rounded,
      TraceKind.hosting => Icons.business_outlined,
      TraceKind.country => Icons.public_rounded,
      TraceKind.phone => Icons.phone_outlined,
      TraceKind.account => Icons.account_balance_outlined,
      TraceKind.email => Icons.alternate_email_rounded,
      TraceKind.brand => Icons.theater_comedy_outlined,
      TraceKind.related => Icons.folder_shared_outlined,
      TraceKind.webReport => Icons.travel_explore_rounded,
      TraceKind.purpose => Icons.category_outlined,
      TraceKind.reputation => Icons.star_half_rounded,
    };

/// The live investigation map: nodes pop in as lookups find them, a gentle
/// force layout keeps them apart, packets travel along the links a lookup
/// is working on, and a radar sweep turns while the trace runs. Pinch to
/// zoom, drag to move, tap a node to inspect it.
class TraceCanvas extends StatefulWidget {
  final TraceState state;
  /// Bumped by the owner whenever [state] changes.
  final int version;
  final bool running;
  final String? selected;
  final ValueChanged<String> onTap;
  const TraceCanvas({super.key, required this.state, required this.version, required this.running, required this.onTap, this.selected});

  @override
  State<TraceCanvas> createState() => _TraceCanvasState();
}

class _TraceCanvasState extends State<TraceCanvas> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  final _view = TransformationController();
  final _rnd = math.Random(7);
  final Map<String, Offset> _pos = {};
  final Map<String, double> _born = {};
  final Map<String, double> _edgeBorn = {};
  final Map<String, (TextPainter, TextPainter)> _text = {};
  double _t = 0, _heat = 1, _lastChange = 0;
  // The automatic zoom-to-fit, eased each frame.
  double _fit = 1;
  Offset _centre = Offset.zero;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _sync();
    _ticker.start();
  }

  @override
  void didUpdateWidget(TraceCanvas old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _pos.clear();
      _born.clear();
      _edgeBorn.clear();
      _text.clear();
      _view.value = Matrix4.identity();
    }
    _sync();
    if (!_ticker.isActive) _ticker.start();
  }

  void _sync() {
    final s = widget.state;
    for (final n in s.nodes.values) {
      if (!_pos.containsKey(n.id)) {
        final p = n.parent == null ? null : _pos[n.parent];
        _pos[n.id] = p == null
            ? (n.parent == null ? Offset.zero : Offset(_rnd.nextDouble() * 40 - 20, _rnd.nextDouble() * 40 - 20))
            : p + Offset.fromDirection(_rnd.nextDouble() * 2 * math.pi, 14);
        _born[n.id] = _t;
        _heat = 1;
        _lastChange = _t;
      }
      _text.remove(n.id); // labels and flags may have changed
    }
    for (final e in s.edges.values) {
      _edgeBorn.putIfAbsent(e.key, () => _t);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _view.dispose();
    super.dispose();
  }

  void _tick(Duration d) {
    _t = d.inMicroseconds / 1e6;
    if (_heat > 0.01) {
      _simulate();
      _heat *= 0.985;
    }
    _updateFit();
    _frame.value++;
    // Rest when nothing moves, to save battery.
    if (!widget.running && _heat <= 0.01 && _t - _lastChange > 3) _ticker.stop();
  }

  void _simulate() {
    final s = widget.state;
    final ids = _pos.keys.toList();
    final force = {for (final id in ids) id: Offset.zero};
    const k = 52.0;
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        var d = _pos[ids[i]]! - _pos[ids[j]]!;
        var dist = d.distance;
        if (dist < 0.1) {
          d = Offset(_rnd.nextDouble() - 0.5, _rnd.nextDouble() - 0.5);
          dist = d.distance;
        }
        if (dist > 400) continue;
        final f = d / dist * (k * k / dist) * 0.5;
        force[ids[i]] = force[ids[i]]! + f;
        force[ids[j]] = force[ids[j]]! - f;
      }
    }
    final parents = {for (final e in s.edges.values) e.from};
    for (final e in s.edges.values) {
      final a = _pos[e.from], b = _pos[e.to];
      if (a == null || b == null) continue;
      final leaf = !parents.contains(e.to);
      final rest = leaf ? 70.0 : 100.0;
      final d = b - a;
      final dist = math.max(d.distance, 0.1);
      final f = d / dist * (dist - rest) * 0.12;
      force[e.from] = force[e.from]! + f;
      force[e.to] = force[e.to]! - f;
    }
    final origin = s.originId;
    for (final id in ids) {
      if (id == origin) {
        _pos[id] = Offset.zero;
        continue;
      }
      final f = force[id]! - _pos[id]! * 0.025;
      final len = f.distance;
      final step = math.min(len, 9.0) * math.min(1.0, _heat * 2);
      if (len > 0.001) _pos[id] = _pos[id]! + f / len * step;
    }
  }

  void _updateFit() {
    if (_pos.isEmpty || _size.isEmpty) return;
    var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0;
    for (final p in _pos.values) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final w = maxX - minX + 200, h = maxY - minY + 140;
    final target = math.min(_size.width / w, _size.height / h).clamp(0.3, 1.25);
    final c = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    _fit += (target - _fit) * 0.08;
    _centre += (c - _centre) * 0.08;
  }

  Offset _toScreen(Offset p) => Offset(_size.width / 2, _size.height / 2) + (p - _centre) * _fit;

  void _tap(Offset local) {
    String? best;
    var bd = 30.0 * 30.0;
    for (final e in _pos.entries) {
      final d = (_toScreen(e.value) - local).distanceSquared;
      if (d < bd) {
        bd = d;
        best = e.key;
      }
    }
    if (best != null) widget.onTap(best);
  }

  (TextPainter, TextPainter) _painters(TraceNode n) => _text.putIfAbsent(n.id, () {
        final icon = traceIcon(n.kind);
        final ip = TextPainter(
          text: TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: n.parent == null ? 22 : 15, color: Colors.white)),
          textDirection: TextDirection.ltr,
        )..layout();
        final label = n.kind == TraceKind.country ? '${_flag(n.country)} ${n.label}' : n.label;
        final lp = TextPainter(
          text: TextSpan(
              text: label.length > 22 ? '${label.substring(0, 21)}…' : label,
              style: TextStyle(fontFamily: 'Inter', fontSize: 10, height: 1.2, fontWeight: n.parent == null ? FontWeight.w700 : FontWeight.w500, color: const Color(0xFFCBD5E1))),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 120);
        return (ip, lp);
      });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _size = c.biggest;
      return ClipRRect(
        borderRadius: K.r16,
        child: ColoredBox(
          color: K.night,
          child: Stack(children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _view,
                minScale: 0.5,
                maxScale: 4,
                boundaryMargin: const EdgeInsets.all(300),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _tap(d.localPosition),
                  child: CustomPaint(
                    size: c.biggest,
                    painter: _TracePainter(this),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: K.nightCard.withValues(alpha: 0.85), borderRadius: K.r8, border: Border.all(color: K.nightLine)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.hub_outlined, size: 14, color: widget.running ? traceCyan : const Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Text(widget.running ? 'Graph: building live' : 'Graph: ${widget.state.nodes.length} nodes',
                      style: traceMono.copyWith(fontSize: 11, color: const Color(0xFFCBD5E1))),
                ]),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                tooltip: 'Reset zoom',
                onPressed: () => _view.value = Matrix4.identity(),
                icon: const Icon(Icons.center_focus_strong_outlined, color: Color(0xFFCBD5E1), size: 20),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

String _flag(String? code) {
  if (code == null || code.length != 2) return '';
  final c = code.toUpperCase();
  return String.fromCharCodes([0x1F1E6 + c.codeUnitAt(0) - 65, 0x1F1E6 + c.codeUnitAt(1) - 65]);
}

double _easeOutBack(double x) {
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * math.pow(x - 1, 3) + c1 * math.pow(x - 1, 2);
}

class _TracePainter extends CustomPainter {
  final _TraceCanvasState v;
  _TracePainter(this.v) : super(repaint: v._frame);

  @override
  void paint(Canvas canvas, Size size) {
    final s = v.widget.state;
    final t = v._t;
    final active = s.active;

    // Tactical grid.
    final dot = Paint()..color = const Color(0xFF1E293B);
    for (var x = 12.0; x < size.width; x += 24) {
      for (var y = 12.0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }

    final origin = s.originId == null ? null : v._toScreen(v._pos[s.originId] ?? Offset.zero);

    // Radar sweep while the trace runs.
    if (v.widget.running && origin != null) {
      final r = size.longestSide;
      final a = (t * 1.6) % (2 * math.pi);
      final sweep = Paint()
        ..shader = SweepGradient(
          colors: [traceCyan.withValues(alpha: 0), traceCyan.withValues(alpha: 0.16)],
          stops: const [0.8, 1],
          transform: GradientRotation(a),
        ).createShader(Rect.fromCircle(center: origin, radius: r));
      canvas.drawCircle(origin, r, sweep);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..color = traceCyan.withValues(alpha: 0.08);
      for (final rr in [70.0, 140.0, 210.0]) {
        canvas.drawCircle(origin, rr * v._fit, ring);
      }
    }

    // Links, drawn growing out of their parent.
    for (final e in s.edges.values) {
      final pa = v._pos[e.from], pb = v._pos[e.to];
      if (pa == null || pb == null) continue;
      final a = v._toScreen(pa), b = v._toScreen(pb);
      final g = ((t - (v._edgeBorn[e.key] ?? t)) / 0.5).clamp(0.0, 1.0);
      final end = Offset.lerp(a, b, Curves.easeOut.transform(g))!;
      final hot = s.nodes[e.to]?.flagged ?? false;
      final base = hot ? K.red : const Color(0xFF3B5B9A);
      canvas.drawLine(a, end, Paint()
        ..color = base.withValues(alpha: hot ? 0.75 : 0.6)
        ..strokeWidth = hot ? 1.8 : 1.3);
      // Packets while a lookup works on either end, and just after a link appears.
      final busy = active.contains(e.to) || active.contains(e.from);
      final fresh = t - (v._edgeBorn[e.key] ?? 0) < 1.6;
      if ((busy || fresh) && g >= 1 && v.widget.running) {
        final seed = (e.key.hashCode % 100) / 100;
        for (var k = 0; k < (busy ? 2 : 1); k++) {
          final f = (t * 0.9 + seed + k * 0.5) % 1.0;
          final p = Offset.lerp(a, b, active.contains(e.from) && !active.contains(e.to) ? 1 - f : f)!;
          final c = hot ? K.red : traceCyan;
          canvas.drawCircle(p, 4.5, Paint()..color = c.withValues(alpha: 0.25));
          canvas.drawCircle(p, 2.2, Paint()..color = c);
        }
      }
    }

    // Nodes.
    for (final n in s.nodes.values) {
      final p0 = v._pos[n.id];
      if (p0 == null) continue;
      final o = v._toScreen(p0);
      final age = ((t - (v._born[n.id] ?? t)) / 0.45).clamp(0.0, 1.0);
      final grow = _easeOutBack(age).clamp(0.0, 1.3);
      final isOrigin = n.parent == null;
      final r = (isOrigin ? 24.0 : 15.0) * grow;
      if (r <= 0.5) continue;
      final c = traceColor(n.kind);
      final ring = n.flagged ? K.red : c;

      if (isOrigin) {
        // Pulsing radar rings around the thing being traced.
        for (var k = 0; k < 2; k++) {
          final ph = (t * 0.6 + k * 0.5) % 1.0;
          canvas.drawCircle(o, r + 4 + 22 * ph, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = ring.withValues(alpha: 0.45 * (1 - ph)));
        }
      }
      canvas.drawCircle(o, r + 6, Paint()..color = ring.withValues(alpha: n.flagged ? 0.22 : 0.12));
      canvas.drawCircle(o, r, Paint()..color = n.flagged ? const Color(0xFF2A1215) : K.nightCard);
      canvas.drawCircle(o, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = n.flagged || isOrigin ? 2.4 : 1.6
        ..color = ring);
      if (n.demo) {
        final dash = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFFF59E0B);
        for (var k = 0; k < 12; k++) {
          canvas.drawArc(Rect.fromCircle(center: o, radius: r + 4), k * math.pi / 6, math.pi / 12, false, dash);
        }
      }
      if (active.contains(n.id)) {
        // A scanning arc while a lookup runs on this node.
        canvas.drawArc(Rect.fromCircle(center: o, radius: r + 7), (t * 5) % (2 * math.pi), math.pi * 0.7, false, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = traceCyan);
      }
      if (n.id == v.widget.selected) {
        canvas.drawCircle(o, r + 10, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white);
      }
      if (age < 1) {
        canvas.save();
        canvas.translate(o.dx, o.dy);
        canvas.scale(grow);
        canvas.translate(-o.dx, -o.dy);
      }
      final (icon, label) = v._painters(n);
      icon.paint(canvas, o - Offset(icon.width / 2, icon.height / 2));
      label.paint(canvas, o + Offset(-label.width / 2, (isOrigin ? 24.0 : 15.0) + 6));
      if (age < 1) canvas.restore();
      if (n.demo && age >= 1) {
        final tp = TextPainter(
          text: const TextSpan(text: 'DEMO', style: TextStyle(fontFamily: 'Inter', fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFFF59E0B))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, o + Offset(-tp.width / 2, -r - 16));
      }
    }
  }

  @override
  bool shouldRepaint(_TracePainter old) => true;
}
