import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/models.dart';
import 'theme.dart';

// Shared building blocks for every screen: cards, pills, progress, popups,
// in-app notifications and the live "how Kantoi works" pipeline.

/// White rounded card with the design system's hairline border.
class KCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  const KCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.borderColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: color ?? (dark ? scheme.surfaceContainerLow : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: K.r16, side: BorderSide(color: borderColor ?? scheme.outlineVariant.withValues(alpha: 0.6))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Small rounded label, e.g. a risk level or "On device".
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;
  const Pill(this.text, {super.key, required this.color, this.icon, this.solid = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: solid ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: solid ? Colors.white : color), const SizedBox(width: 4)],
          Text(text.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: solid ? Colors.white : color)),
        ]),
      );
}

Pill riskPill(RiskLevel l) => Pill(riskLabel(l), color: riskColor(l), icon: riskIcon(l));

/// A dot that breathes, used for "Protected" and live states.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, this.color = K.green, this.size = 8});
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size * 2.4,
        height: widget.size * 2.4,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Stack(alignment: Alignment.center, children: [
            Container(
              width: widget.size * (1 + 1.4 * _c.value),
              height: widget.size * (1 + 1.4 * _c.value),
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.35 * (1 - _c.value))),
            ),
            Container(width: widget.size, height: widget.size, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ]),
        ),
      );
}

/// Rounded progress bar that animates to [value] (0..1); null = indeterminate.
class KProgressBar extends StatelessWidget {
  final double? value;
  final Color? color;
  final double height;
  const KProgressBar({super.key, this.value, this.color, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final track = Theme.of(context).colorScheme.surfaceContainerHigh;
    if (value == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(minHeight: height, color: c, backgroundColor: track),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value!.clamp(0, 1)),
      duration: K.medium,
      curve: K.curve,
      builder: (_, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(value: v, minHeight: height, color: c, backgroundColor: track),
      ),
    );
  }
}

/// Fades and slides its child in once, after [delay]. Used to stagger lists.
class Reveal extends StatelessWidget {
  final Widget child;
  final int index;
  const Reveal({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 360 + 60 * math.min(index, 8)),
        curve: Interval(math.min(index, 8) * 0.08, 1, curve: K.curve),
        builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: c)),
        child: child,
      );
}

/// Bottom-sheet popup with a title, body and up to two buttons.
Future<T?> showKSheet<T>(
  BuildContext context, {
  required String title,
  IconData? icon,
  Color? iconColor,
  String? message,
  Widget? body,
  String? primary,
  VoidCallback? onPrimary,
  String? secondary,
  VoidCallback? onSecondary,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (icon != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: (iconColor ?? K.primary).withValues(alpha: 0.1), borderRadius: K.r16),
                    child: Icon(icon, color: iconColor ?? K.primary, size: 28),
                  ),
                ),
              const SizedBox(height: 12),
              Text(title, style: t.headlineSmall),
              if (message != null) ...[const SizedBox(height: 8), Text(message, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant))],
              if (body != null) ...[const SizedBox(height: 16), Flexible(child: body)],
              const SizedBox(height: 20),
              if (primary != null)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onPrimary?.call();
                  },
                  child: Text(primary),
                ),
              if (secondary != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onSecondary?.call();
                  },
                  child: Text(secondary),
                ),
              ],
            ]),
          ),
        );
      },
    );

/// In-app notification that slides down from the top of the screen, like a
/// heads-up notification. Tapping it runs [onTap].
void showKToast(
  BuildContext context, {
  required String title,
  String? body,
  IconData icon = Icons.shield_rounded,
  Color color = K.primary,
  VoidCallback? onTap,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => _Toast(title: title, body: body, icon: icon, color: color, onTap: () {
      remove();
      onTap?.call();
    }, onDone: remove),
  );
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  final String title;
  final String? body;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onDone;
  const _Toast({required this.title, this.body, required this.icon, required this.color, required this.onTap, required this.onDone});
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: K.medium)..forward();
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(seconds: 5), _close);
  }

  Future<void> _close() async {
    if (!mounted) return;
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.paddingOf(context).top + 8,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -1.4), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: K.curve)),
        child: Dismissible(
          key: const ValueKey('toast'),
          direction: DismissDirection.up,
          onDismissed: (_) => widget.onDone(),
          child: Material(
            elevation: 8,
            shadowColor: Colors.black26,
            color: Colors.white,
            borderRadius: K.r16,
            child: InkWell(
              borderRadius: K.r16,
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(widget.icon, color: widget.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(widget.title, style: t.titleMedium?.copyWith(color: K.onSurface)),
                      if (widget.body != null) Text(widget.body!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: K.outline),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The six stages every check goes through, in order. Each [LogStep] from
/// the engine falls into one of them by its tool name.
enum Stage { read, protect, rules, links, ai, verdict }

extension StageInfo on Stage {
  String get label => switch (this) {
        Stage.read => 'Read',
        Stage.protect => 'Protect',
        Stage.rules => 'Scam signs',
        Stage.links => 'Links',
        Stage.ai => 'AI',
        Stage.verdict => 'Verdict',
      };
  String get blurb => switch (this) {
        Stage.read => 'Reading the message, picture or file',
        Stage.protect => 'Hiding your personal details before anything leaves the phone',
        Stage.rules => 'Looking for known scam tricks and wording',
        Stage.links => 'Checking links, websites and who runs them',
        Stage.ai => 'Asking the AI for a second opinion',
        Stage.verdict => 'Adding up the evidence',
      };
  IconData get icon => switch (this) {
        Stage.read => Icons.document_scanner_outlined,
        Stage.protect => Icons.privacy_tip_outlined,
        Stage.rules => Icons.rule_rounded,
        Stage.links => Icons.travel_explore_rounded,
        Stage.ai => Icons.auto_awesome_outlined,
        Stage.verdict => Icons.gavel_rounded,
      };
}

Stage stageOf(LogStep s) {
  final t = s.tool.toLowerCase();
  if (t.contains('risk scorer') || t.contains('verdict')) return Stage.verdict;
  if (t.startsWith('ai ')) return Stage.ai;
  if (t.contains('privacy') || t.contains('injection')) return Stage.protect;
  if (t.contains('link') || t.contains('rdap') || t.contains('domain') || t.contains('cloak') || t.contains('threat') ||
      t.contains('virustotal') || t.contains('reports')) {
    return Stage.links;
  }
  if (t.contains('reader') || t.contains('router') || t.contains('speech') || t.contains('parser') || t.contains('file')) {
    return Stage.read;
  }
  return Stage.rules;
}

/// The live "how Kantoi works" view: six stages joined by a line that fills
/// as the check moves along, with a packet travelling to the active stage,
/// then every tool that ran, each marked on-device (lock) or online (cloud).
class PipelineView extends StatefulWidget {
  final List<LogStep> steps;
  final bool finished;
  final bool showTools;
  const PipelineView({super.key, required this.steps, this.finished = false, this.showTools = true});
  @override
  State<PipelineView> createState() => _PipelineViewState();
}

class _PipelineViewState extends State<PipelineView> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final byStage = <Stage, List<LogStep>>{};
    for (final s in widget.steps) {
      byStage.putIfAbsent(stageOf(s), () => []).add(s);
    }
    // The furthest stage reached so far is the active one.
    var active = widget.steps.isEmpty ? 0 : widget.steps.map((s) => stageOf(s).index).reduce(math.max);
    if (widget.finished) active = Stage.values.length;
    final running = widget.steps.where((s) => s.status == StepStatus.running).toList();
    final current = running.isNotEmpty ? running.last : null;
    final total = widget.steps.length;
    final finishedSteps = widget.steps.where((s) => s.status != StepStatus.running).length;

    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(widget.finished ? Icons.task_alt_rounded : Icons.radar_rounded, color: widget.finished ? K.green : K.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.finished ? 'How Kantoi checked this' : 'Kantoi is checking', style: t.titleMedium)),
          Text('$finishedSteps/$total steps', style: t.labelMedium?.copyWith(color: K.outline, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 64,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(
              painter: _RailPainter(active: active, count: Stage.values.length, phase: _c.value, finished: widget.finished),
              child: Row(children: [
                for (final st in Stage.values)
                  Expanded(child: _StageNode(stage: st, state: st.index < active ? 2 : (st.index == active ? 1 : 0), pulse: _c.value)),
              ]),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: K.fast,
          child: Padding(
            key: ValueKey(widget.finished ? 'done' : '${current?.tool}${current?.action}'),
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              widget.finished
                  ? 'Done. Every step is listed below.'
                  : current != null
                      ? '${current.tool}: ${current.action}'
                      : (active < Stage.values.length ? Stage.values[active].blurb : ''),
              style: t.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (!widget.finished) ...[const SizedBox(height: 10), KProgressBar(value: total == 0 ? null : (active + 0.5) / Stage.values.length, height: 6)],
        if (widget.showTools && widget.steps.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(),
          for (final st in Stage.values)
            if (byStage[st] != null)
              for (final (i, s) in byStage[st]!.indexed) _ToolRow(step: s, stage: i == 0 ? st : null),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Icon(Icons.lock_outline_rounded, size: 14, color: K.outline),
            const SizedBox(width: 4),
            Text('on this phone', style: t.labelSmall?.copyWith(color: K.outline)),
            const SizedBox(width: 8),
            const Icon(Icons.cloud_outlined, size: 14, color: K.outline),
            const SizedBox(width: 4),
            Text('went online (personal details hidden)', style: t.labelSmall?.copyWith(color: K.outline)),
          ]),
        ],
      ]),
    );
  }
}

class _StageNode extends StatelessWidget {
  final Stage stage;
  final int state; // 0 waiting, 1 active, 2 done
  final double pulse;
  const _StageNode({required this.stage, required this.state, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final c = state == 2 ? K.green : (state == 1 ? K.primary : K.outlineVariant);
    return Column(children: [
      SizedBox(
        width: 40,
        height: 40,
        child: Stack(alignment: Alignment.center, children: [
          if (state == 1)
            Container(
              width: 32 + 10 * pulse,
              height: 32 + 10 * pulse,
              decoration: BoxDecoration(shape: BoxShape.circle, color: K.primary.withValues(alpha: 0.18 * (1 - pulse))),
            ),
          AnimatedContainer(
            duration: K.medium,
            curve: K.curve,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state == 0 ? Colors.white : c,
              border: Border.all(color: c, width: 2),
            ),
            child: AnimatedSwitcher(
              duration: K.fast,
              transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
              child: Icon(state == 2 ? Icons.check_rounded : stage.icon,
                  key: ValueKey(state == 2), size: 16, color: state == 0 ? K.outline : Colors.white),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 4),
      Text(stage.label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: state == 0 ? K.outline : K.onSurface)),
    ]);
  }
}

/// Draws the line between stage nodes: filled up to the active stage, with
/// a small packet moving towards it.
class _RailPainter extends CustomPainter {
  final int active;
  final int count;
  final double phase;
  final bool finished;
  _RailPainter({required this.active, required this.count, required this.phase, required this.finished});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / count;
    const y = 20.0;
    final x0 = w / 2, x1 = size.width - w / 2;
    final base = Paint()
      ..color = K.outlineVariant
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x0, y), Offset(x1, y), base);
    final reached = finished ? x1 : x0 + w * math.min(active, count - 1);
    canvas.drawLine(Offset(x0, y), Offset(reached, y), base..color = K.green);
    if (!finished && active > 0 && active < count) {
      final from = x0 + w * (active - 1);
      final px = from + w * phase;
      canvas.drawCircle(Offset(px, y), 4, Paint()..color = K.primary);
      canvas.drawCircle(Offset(px, y), 8, Paint()..color = K.primary.withValues(alpha: 0.2));
    }
  }

  @override
  bool shouldRepaint(_RailPainter o) => o.active != active || o.phase != phase || o.finished != finished;
}

class _ToolRow extends StatelessWidget {
  final LogStep step;
  final Stage? stage;
  const _ToolRow({required this.step, this.stage});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (stage != null)
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(stage!.label.toUpperCase(), style: t.labelSmall?.copyWith(color: K.outline, letterSpacing: 1)),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 20,
            height: 20,
            child: switch (step.status) {
              StepStatus.running => const Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2)),
              StepStatus.done => const Icon(Icons.check_circle_rounded, color: K.green, size: 18),
              StepStatus.skipped => const Icon(Icons.remove_circle_outline_rounded, color: K.outline, size: 18),
              StepStatus.failed => const Icon(Icons.error_outline_rounded, color: K.amber, size: 18),
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: step.tool, style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: '  ${step.action}', style: TextStyle(color: K.onSurfaceVariant.withValues(alpha: 0.9))),
              ]), style: t.bodySmall?.copyWith(color: K.onSurface)),
              if (step.result.isNotEmpty) Text(step.result, style: t.bodySmall),
            ]),
          ),
          const SizedBox(width: 8),
          Icon(step.sentOffDevice ? Icons.cloud_outlined : Icons.lock_outline_rounded, size: 16, color: K.outline),
        ]),
      ),
    ]);
  }
}
