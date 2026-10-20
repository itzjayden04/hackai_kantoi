import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../awareness/explainers.dart';
import '../engine/models.dart';

/// What goes on a family warning picture. Never the original message.
class WarningContent {
  final String title;
  final List<String> signs;
  final String todo;
  const WarningContent(this.title, this.signs, this.todo);

  factory WarningContent.fromExplainer(Explainer e) => WarningContent(e.name, e.signs.take(3).toList(), e.todo.first);

  /// The scam type, its three strongest signs (topped up from the explainer
  /// card) and the next step.
  factory WarningContent.fromInvestigation(Investigation inv) {
    final e = explainerForInvestigation(inv);
    final risks = inv.findings.where((f) => f.isRisk).toList()..sort((a, b) => b.weight.compareTo(a.weight));
    final signs = <String>[];
    for (final f in risks) {
      if (signs.length < 3 && !signs.contains(f.title)) signs.add(f.title);
    }
    for (final s in e.signs) {
      if (signs.length < 3) signs.add(s);
    }
    final title = e.id == 'general' || e.genuine ? inv.verdict.scamType : e.name;
    return WarningContent(title, signs, inv.verdict.nextStep);
  }
}

/// Opens the "Warn family" choices: a picture for WhatsApp groups, or the
/// plain text that was there before.
Future<void> showWarnFamily(BuildContext context, Investigation inv, String text) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.image_outlined),
          title: const Text('Send as a picture'),
          subtitle: const Text('A clear warning card for family WhatsApp groups'),
          onTap: () {
            Navigator.pop(sheet);
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WarningImagePage(content: WarningContent.fromInvestigation(inv), text: text)));
          },
        ),
        ListTile(
          leading: const Icon(Icons.copy_rounded),
          title: const Text('Copy as text'),
          subtitle: const Text('Paste it into any chat'),
          onTap: () {
            Navigator.pop(sheet);
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Warning copied. Paste it into your family chat.')));
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// The picture itself: fixed size and always light, so it looks the same in
/// every chat.
class WarningPoster extends StatelessWidget {
  final WarningContent content;
  const WarningPoster({super.key, required this.content});

  static const red = Color(0xFFDC2626);
  static const ink = Color(0xFF111827);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SizedBox(
        width: 360,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Container(
            color: red,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 30),
              SizedBox(width: 10),
              Text('SCAM WARNING', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(content.title, style: const TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 16),
              const Text('Watch out for', style: TextStyle(color: red, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final s in content.signs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.cancel_rounded, color: red, size: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s, style: const TextStyle(color: ink, fontSize: 16, height: 1.3))),
                  ]),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('What to do', style: TextStyle(color: Color(0xFF15803D), fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(content.todo, style: const TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w600, height: 1.3)),
                ]),
              ),
              const SizedBox(height: 10),
              const Text('Lost money? Call 997 (National Scam Response Centre) at once.',
                  style: TextStyle(color: ink, fontSize: 13, height: 1.3)),
            ]),
          ),
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: const Color(0xFF1E3A8A),
            child: const Row(children: [
              Icon(Icons.policy_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Checked with Kantoi',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              ),
              Text('Please share', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Renders the widget behind [key] to PNG bytes.
Future<Uint8List?> capturePng(GlobalKey key, {double pixelRatio = 3}) async {
  final b = key.currentContext?.findRenderObject();
  if (b is! RenderRepaintBoundary) return null;
  final img = await b.toImage(pixelRatio: pixelRatio);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data?.buffer.asUint8List();
}

class WarningImagePage extends StatefulWidget {
  final WarningContent content;
  final String? text;
  const WarningImagePage({super.key, required this.content, this.text});
  @override
  State<WarningImagePage> createState() => _WarningImagePageState();
}

class _WarningImagePageState extends State<WarningImagePage> {
  final _key = GlobalKey();
  bool _busy = false;

  String get _caption =>
      widget.text ?? 'Scam warning: ${widget.content.title}. ${widget.content.todo} (Checked with Kantoi)';

  Future<void> _run(Future<String?> Function(Uint8List png) job) async {
    setState(() => _busy = true);
    final m = ScaffoldMessenger.of(context);
    try {
      final png = await capturePng(_key);
      if (png == null) throw StateError('no picture');
      final msg = await job(png);
      if (msg != null) m.showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: _caption));
      m.showSnackBar(const SnackBar(content: Text('Could not make the picture here. The warning text was copied instead.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _share(Uint8List png) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(png, mimeType: 'image/png', name: 'kantoi-scam-warning.png')],
      fileNameOverrides: const ['kantoi-scam-warning.png'],
      text: _caption,
    ));
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Warning picture')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 40), children: [
        Text('Share this with your family group. It does not include the message or any personal details.', style: t.bodyMedium),
        const SizedBox(height: 16),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: FittedBox(
              child: DecoratedBox(
                decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16)]),
                child: RepaintBoundary(key: _key, child: WarningPoster(content: widget.content)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilledButton.icon(
                icon: const Icon(Icons.share_rounded),
                label: const Text('Share picture'),
                onPressed: _busy ? null : () => _run(_share),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy as text instead'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _caption));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Warning copied.')));
                },
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
