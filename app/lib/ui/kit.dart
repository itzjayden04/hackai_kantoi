import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/models.dart';
import 'theme.dart';

// Shared building blocks for every screen: cards, pills, progress, popups,
// in-app notifications and the live "how Kantoi works" pipeline.

/// Frosted white card: large radius, a hairline white edge and a soft,
/// wide shadow. Pass [borderColor] to outline a selected or tinted card.
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
    final frosted = color == null && !dark;
    final bg = color ?? (dark ? scheme.surfaceContainerLow : K.glass);
    final edge = borderColor ?? (frosted ? K.glassEdge : null);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: K.rCard, boxShadow: frosted ? K.shadow : null),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: K.rCard, side: edge == null ? BorderSide.none : BorderSide(color: edge)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// A titled block on a page: a small grey heading, an optional "i" for the
/// detail and a right-hand action, then its content. The space above it is
/// what separates one feature from the next.
class KSection extends StatelessWidget {
  final String title;
  final String? info;

  /// Extra content under the [info] text in its sheet, e.g. an activity log.
  final Widget? infoBody;
  final Widget? trailing;
  final List<Widget> children;
  final bool first;
  const KSection(this.title, {super.key, this.info, this.infoBody, this.trailing, required this.children, this.first = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 34,
          child: Row(children: [
            const SizedBox(width: 4),
            Expanded(
              child: Row(children: [
                Flexible(child: Text(title, style: t.titleSmall?.copyWith(color: K.secondary, fontWeight: FontWeight.w500))),
                if (info != null) ...[const SizedBox(width: 6), InfoButton(title: title, message: info!, body: infoBody)],
              ]),
            ),
            ?trailing,
          ]),
        ),
        const SizedBox(height: 8),
        for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 12), c],
      ]),
    );
  }
}

/// One frosted card holding a list: a header line (title, an optional badge,
/// an optional "i" and a right-hand note) over rows split by hairlines.
class KGroup extends StatelessWidget {
  final String? title;
  final String? badge;
  final Color badgeColor;
  final String? info;
  final String? note;
  final Color noteColor;
  final List<Widget> children;
  const KGroup(
      {super.key,
      this.title,
      this.badge,
      this.badgeColor = K.primary,
      this.info,
      this.note,
      this.noteColor = K.outline,
      required this.children});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Expanded(
              child: Row(children: [
                Flexible(child: Text(title!, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(99)),
                    child: Text(badge!, style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ],
                if (info != null) ...[const SizedBox(width: 4), InfoButton(title: title!, message: info!)],
              ]),
            ),
            if (note != null) Text(note!, style: t.labelMedium?.copyWith(color: noteColor)),
          ]),
        ),
      for (final (i, c) in children.indexed) ...[
        if (i > 0) const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: K.surfaceHigh),
        c,
      ],
    ]);
    return KCard(padding: EdgeInsets.zero, child: list);
  }
}

/// Brand colour, short mark ("TnG", "M"), and whether the colour is too
/// light for text on white. Stands in for real logos, which Kantoi does not
/// ship.
const _brands = <String, (Color, String, bool)>{
  'Shopee': (Color(0xFFEE4D2D), 'S', false),
  'Lazada': (Color(0xFF0F146D), 'L', false),
  'Boost': (Color(0xFFEA2127), 'B', false),
  "Touch 'n Go": (Color(0xFF0055A5), 'TnG', false),
  'Maybank': (Color(0xFFFFC72C), 'M', true),
  'CIMB': (Color(0xFFC8102E), 'C', false),
  'Public Bank': (Color(0xFFE31837), 'PB', false),
  'RHB': (Color(0xFF0067B1), 'RHB', false),
  'Bank Islam': (Color(0xFFB5121B), 'BI', false),
  'BSN': (Color(0xFF0072BC), 'BSN', false),
  'Pos Malaysia': (Color(0xFFED1C24), 'Pos', false),
  'J&T Express': (Color(0xFFE3001B), 'J&T', false),
  'DHL': (Color(0xFFD40511), 'DHL', false),
  'LHDN': (Color(0xFF1F3C88), 'LHDN', false),
  'PDRM': (Color(0xFF0B1F5C), 'PDRM', false),
  'MyEG': (Color(0xFF00A651), 'EG', false),
  'KWSP': (Color(0xFF0B4EA2), 'EPF', false),
  'JPJ': (Color(0xFF1E3A8A), 'JPJ', false),
};

/// The look of [brand]'s mark: its colour, short mark and whether the colour
/// is too light for text on white (Maybank's yellow). Unknown brands get navy
/// and their first letter.
(Color, String, bool) brandLook(String brand) {
  final b = _brands[brand];
  return (b?.$1 ?? K.navy, b?.$2 ?? (brand.isEmpty ? '?' : brand[0].toUpperCase()), b?.$3 ?? false);
}

/// Small spaced-out monospace capitals for labels, dates and units
/// ("THIS WEEK", "12:11 PM"), next to big light numbers.
TextStyle monoCaps({Color color = K.outline, double size = 11}) =>
    TextStyle(fontFamily: 'monospace', fontSize: size, letterSpacing: 1.2, height: 1.3, color: color);

/// A big, light number with its decimals or unit greyed, as in "72/100".
class BigNumber extends StatelessWidget {
  final String value;
  final String? unit;
  final double size;
  final Color color;
  const BigNumber(this.value, {super.key, this.unit, this.size = 34, this.color = K.onSurface});

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
        TextSpan(text: value, style: TextStyle(fontSize: size, height: 1.1, fontWeight: FontWeight.w400, letterSpacing: -1.2, color: color)),
        if (unit != null)
          TextSpan(text: unit, style: TextStyle(fontSize: size * 0.62, fontWeight: FontWeight.w400, letterSpacing: -0.5, color: K.outline)),
      ]));
}

/// One figure in a 2-column grid: label top-left in mono capitals, a small
/// icon in a white circle top-right, the big number and a mono caption.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String? caption;
  final IconData icon;
  final Color valueColor;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.unit,
    this.caption,
    this.valueColor = K.onSurface,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: K.glass,
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(color: K.glassEdge),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(label.toUpperCase(), style: monoCaps())),
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: K.surfaceMid, shape: BoxShape.circle),
              child: Icon(icon, size: 17, color: K.onSurface),
            ),
          ]),
          const SizedBox(height: 10),
          BigNumber(value, unit: unit, size: 32, color: valueColor),
          if (caption != null) ...[const SizedBox(height: 4), Text(caption!.toUpperCase(), style: monoCaps(size: 10))],
        ]),
      );
}

/// A grid of [StatTile]s, two to a row.
class StatGrid extends StatelessWidget {
  final List<Widget> tiles;
  const StatGrid(this.tiles, {super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
            ]),
          ),
        ],
      ]);
}

/// "• TODAY, 5 NOV" above a run of dated rows.
class DateHeader extends StatelessWidget {
  final String text;
  const DateHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Row(children: [
          Container(width: 4, height: 4, decoration: const BoxDecoration(color: K.onSurface, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(text.toUpperCase(), style: monoCaps()),
        ]),
      );
}

/// "Today", "Yesterday" or "3 Nov" for a day header.
String dayLabel(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final diff = DateTime(n.year, n.month, n.day).difference(day).inDays;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final date = '${d.day} ${months[d.month - 1]}';
  return diff == 0 ? 'Today, $date' : diff == 1 ? 'Yesterday, $date' : date;
}

/// A navy card with the soft gradient and glow of the Trace header and a
/// large faint watermark icon in the corner.
class NavyGlowCard extends StatelessWidget {
  final Widget child;
  final IconData? watermark;
  final VoidCallback? onTap;
  const NavyGlowCard({super.key, required this.child, this.watermark, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        borderRadius: K.rCard,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(gradient: navyGlow),
          child: InkWell(
            onTap: onTap,
            child: Stack(children: [
              const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: navyGlowSpot))),
              if (watermark != null)
                Positioned(right: -30, top: -20, child: Icon(watermark, size: 190, color: const Color(0x14FFFFFF))),
              Padding(padding: const EdgeInsets.all(20), child: child),
            ]),
          ),
        ),
      );
}

/// Kantoi's blue wash, as on the Trace header: deep blue in one corner easing to a lighter blue.
const navyGlow = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [K.navy, K.blue, Color(0xFF63A6EC)],
  stops: [0, 0.5, 1],
);

/// The soft light patch that sits on [navyGlow], like light through glass.
const navyGlowSpot = RadialGradient(
  center: Alignment(0.7, 0.6),
  radius: 0.9,
  colors: [Color(0x55A9D2F6), Color(0x00A9D2F6)],
);

/// The last row of a shortened [KGroup]: "Show all N" / "Show less".
class KGroupMore extends StatelessWidget {
  final bool open;
  final int total;
  final VoidCallback onTap;
  const KGroupMore({super.key, required this.open, required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
        label: Text(open ? 'Show less' : 'Show all $total'),
        onPressed: onTap,
      );
}

/// A tappable row inside a [KGroup]: small round icon, label with an
/// optional grey line under it, chevron.
class KGroupRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  /// The right-hand icon: a chevron, or e.g. "open in new" for an outside link.
  final IconData trailing;

  /// Shown instead of the round [icon], e.g. a brand tile.
  final Widget? leading;

  /// A small icon before the [subtitle], e.g. a lock before "Encrypted".
  final IconData? subtitleIcon;

  /// The colour of the [trailing] icon; grey by default.
  final Color trailingColor;
  const KGroupRow(
      {super.key,
      required this.icon,
      this.leading,
      this.subtitleIcon,
      this.trailingColor = K.outline,
      this.color = K.primary,
      required this.label,
      this.subtitle,
      this.onTap,
      this.trailing = Icons.chevron_right_rounded});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(children: [
            leading ??
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 17),
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: K.onSurface)),
                if (subtitle != null)
                  Row(children: [
                    if (subtitleIcon != null) ...[Icon(subtitleIcon, size: 13, color: K.outline), const SizedBox(width: 4)],
                    Flexible(child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: K.outline))),
                  ]),
              ]),
            ),
            Icon(trailing, color: trailingColor, size: trailing == Icons.chevron_right_rounded ? 20 : 18),
          ]),
        ),
      );
}

/// A plain "i" icon (no circle behind it) that opens an explanation in a
/// sheet, so screens can stay short and the detail is one tap away. Pass
/// [color] for a dark background.
class InfoButton extends StatelessWidget {
  final String title;
  final String message;
  final Widget? body;
  final Color color;
  const InfoButton({super.key, required this.title, required this.message, this.body, this.color = K.secondary});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'About $title',
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          foregroundColor: color,
          fixedSize: const Size(32, 32),
          minimumSize: const Size(32, 32),
          padding: EdgeInsets.zero,
        ),
        icon: const Icon(Icons.info_outline_rounded, size: 20),
        onPressed: () => showKSheet<void>(context, title: title, message: message, body: body, primary: 'Got it'),
      );
}

/// A page's big title.
class PageTitle extends StatelessWidget {
  final String text;
  const PageTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 32, height: 38 / 32));
}

/// A field label above its input, as in the design system forms.
class FieldLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const FieldLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: K.onSurface))),
          ?trailing,
        ]),
      );
}

/// Round tinted icon badge used at the start of list rows and cards.
class TintIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color? background;
  final double size;
  final bool square;
  const TintIcon(this.icon, {super.key, this.color = K.primary, this.background, this.size = 40, this.square = false});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? color.withValues(alpha: 0.08),
          shape: square ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: square ? BorderRadius.circular(size * 0.25) : null,
        ),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

/// Small section heading with an optional right-hand note.
class SectionLabel extends StatelessWidget {
  final String text;
  final String? note;
  final Color? noteColor;
  const SectionLabel(this.text, {super.key, this.note, this.noteColor});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(children: [
        Expanded(child: Text(text, style: t.labelLarge?.copyWith(color: K.secondary))),
        if (note != null) Text(note!, style: t.labelMedium?.copyWith(color: noteColor ?? K.secondary)),
      ]),
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
          color: solid ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: solid ? Colors.white : color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: solid ? Colors.white : color)),
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
  IconData icon = Icons.verified_user_rounded,
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
            borderRadius: K.rCard,
            child: InkWell(
              borderRadius: K.rCard,
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
