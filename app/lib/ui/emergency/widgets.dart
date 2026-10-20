import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../kit.dart';
import '../theme.dart';
import 'hotlines.dart';

/// Deep red for the Emergency header: high contrast with white text.
const emergencyRed = Color(0xFFB91C1C);

void copyText(BuildContext context, String text, String what) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$what copied.'), duration: const Duration(seconds: 2)));
}

Future<void> dial(String number) async {
  try {
    await launchUrl(Uri.parse('tel:$number'));
  } catch (_) {}
}

/// Text with [placeholders] drawn as highlighted chips, so the user sees
/// what still needs filling in.
class ScriptText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const ScriptText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium!;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in RegExp(r'\[[^\]]+\]').allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(
        text: m.group(0),
        style: base.copyWith(fontWeight: FontWeight.w700, color: K.primary, backgroundColor: K.surfaceHighest),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans), style: base);
  }
}

/// A label and value with a copy button, like one line of an incident sheet.
class CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final bool mono;
  const CopyRow({super.key, required this.label, required this.value, this.icon, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: K.surfaceLow,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 18, color: K.outline), const SizedBox(width: 10)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: t.labelMedium?.copyWith(color: K.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(
                        color: K.onSurface, fontFamily: mono ? 'monospace' : null, fontWeight: mono ? FontWeight.w600 : null)),
              ]),
            ),
            IconButton(
              tooltip: 'Copy ${label.toLowerCase()}',
              style: IconButton.styleFrom(backgroundColor: Colors.white),
              icon: const Icon(Icons.content_copy_rounded, size: 18, color: K.primary),
              onPressed: () => copyText(context, value, label),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Bank fraud lines, each one tap to dial.
class HotlineList extends StatelessWidget {
  const HotlineList({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.account_balance_outlined, color: K.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('Bank fraud lines', style: t.titleMedium)),
          Text('Tap to call', style: t.labelMedium?.copyWith(color: K.outline)),
        ]),
        const SizedBox(height: 4),
        Text('Numbers from each bank\'s own website. Bank not listed? Call the number on the back of your card.', style: t.bodySmall),
        const SizedBox(height: 12),
        for (final h in bankHotlines) _HotlineTile(h),
      ]),
    );
  }
}

class _HotlineTile extends StatelessWidget {
  final Hotline h;
  const _HotlineTile(this.h);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: K.surfaceLow,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => dial(h.dial),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Text(h.short, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: K.primary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${h.bank} · ${h.label}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text(h.number, style: t.bodyMedium?.copyWith(color: K.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
                  if (h.hours != null) Text(h.hours!, style: t.labelSmall?.copyWith(color: K.outline)),
                ]),
              ),
              IconButton(
                tooltip: 'Call ${h.bank}',
                icon: const Icon(Icons.call_outlined, color: K.primary),
                onPressed: () => dial(h.dial),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Opens the bank list as a pop-up sheet (used from the report page).
Future<void> showHotlineSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: const [HotlineList()],
        ),
      ),
    );
