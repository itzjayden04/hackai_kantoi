import 'package:flutter/material.dart';

import '../theme.dart';

/// A ring that fills to [value] (0..1) with [label] in the middle. Animates
/// whenever the value changes.
class ScoreRing extends StatelessWidget {
  final double value;
  final String label;
  final String? sub;
  final Color color;
  final double size;
  const ScoreRing({super.key, required this.value, required this.label, this.sub, this.color = K.primary, this.size = 84});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0, 1)),
          duration: const Duration(milliseconds: 900),
          curve: K.curve,
          builder: (_, v, _) => Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: size / 11,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: size / 3.6, fontWeight: FontWeight.w800, color: K.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
              if (sub != null) Text(sub!, style: TextStyle(fontSize: size / 8.5, color: K.outline, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      );
}

/// Icon in a soft rounded square, as on the Stitch cards.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(this.icon, {super.key, this.color = K.primary, this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(size / 3.5)),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

/// Pops its child in with a little overshoot, for right/wrong feedback.
class PopIn extends StatelessWidget {
  final Widget child;
  const PopIn({super.key, required this.child});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        curve: Curves.elasticOut,
        builder: (_, v, c) => Transform.scale(scale: 0.4 + 0.6 * v, child: c),
        child: child,
      );
}
