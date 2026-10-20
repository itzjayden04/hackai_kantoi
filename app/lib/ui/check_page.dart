
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/investigator.dart';
import '../engine/models.dart';
import '../engine/vision.dart';
import '../state.dart';
import 'activity_log.dart';
import 'result_view.dart';
import 'theme.dart';

class CheckPage extends StatefulWidget {
  const CheckPage({super.key});
  @override
  State<CheckPage> createState() => _CheckPageState();
}

class _CheckPageState extends State<CheckPage> {
  final _text = TextEditingController();
  List<LogStep> _steps = [];
  Investigation? _result;
  bool _busy = false;
  bool _dragging = false;
  String? _error;

  Future<void> _run(String text, {Source source = Source.paste}) async {
    if (text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _steps = [];
    });
    try {
      final r = await investigate(text.trim(), source: source, options: appState.options, onStep: (s) {
        if (mounted) setState(() => _steps = s);
      });
      appState.addHistory(r);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteAndCheck() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text ?? '';
    if (t.trim().isEmpty) {
      setState(() => _error = 'Your clipboard is empty. Copy the suspicious message first.');
      return;
    }
    _text.text = t;
    await _run(t);
  }

  Future<void> _image(Uint8List bytes, String name) async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _steps = [LogStep(tool: 'Screenshot reader', action: 'Reading the text in $name', sentOffDevice: appState.llm.leavesDevice)];
    });
    try {
      final mime = name.toLowerCase().endsWith('.jpg') || name.toLowerCase().endsWith('.jpeg') ? 'image/jpeg' : 'image/png';
      final r = await readImage(bytes, appState.llm, mime: mime);
      _text.text = r.combined;
      setState(() => _busy = false);
      await _run(r.combined, source: Source.screenshot);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickImage() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp'])
    ]);
    if (f == null) return;
    await _image(await f.readAsBytes(), f.name);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) async {
        setState(() => _dragging = false);
        if (d.files.isEmpty) return;
        final f = d.files.first;
        await _image(await f.readAsBytes(), f.name);
      },
      child: PageBody(children: [
        Text('Is this a scam?', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Paste a message, link or email, or drop a screenshot. Kantoi checks it and tells you what to do.',
            style: t.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _dragging ? scheme.primary : Colors.transparent, width: 2),
          ),
          child: TextField(
            controller: _text,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(hintText: 'Paste the suspicious message or link here'),
            onSubmitted: _run,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(_text.text),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search_rounded),
            label: const Text('Check it'),
          ),
          OutlinedButton.icon(onPressed: _busy ? null : _pasteAndCheck, icon: const Icon(Icons.content_paste_rounded), label: const Text('Paste and check')),
          OutlinedButton.icon(onPressed: _busy ? null : _pickImage, icon: const Icon(Icons.image_outlined), label: const Text('Screenshot')),
          if (_text.text.isNotEmpty || _result != null)
            TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _text.clear();
                          _result = null;
                          _steps = [];
                          _error = null;
                        }),
                child: const Text('Clear')),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        if (_busy && _steps.isNotEmpty) ...[
          const SectionTitle('Checking…'),
          ActivityLog(steps: _steps),
        ],
        if (_result != null) ...[
          const SizedBox(height: 20),
          ResultView(inv: _result!),
        ],
        if (_result == null && !_busy) ...[
          const SectionTitle('Try an example'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _examples)
              ActionChip(
                label: Text(e.$1),
                onPressed: () {
                  _text.text = e.$2;
                  _run(e.$2);
                },
              ),
          ]),
          if (appState.history.isNotEmpty) ...[
            const SectionTitle('Recent checks'),
            for (final h in appState.history.take(8))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(riskIcon(h.verdict.level), color: riskColor(h.verdict.level)),
                title: Text(h.artefact.text.replaceAll('\n', ' '), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${riskLabel(h.verdict.level)} · ${h.verdict.scamType}'),
                onTap: () => setState(() {
                  _result = h;
                  _text.text = h.artefact.text;
                }),
              ),
          ],
        ],
      ]),
    );
  }
}

const _examples = [
  (
    'Parcel fee SMS',
    'POS MALAYSIA: Your parcel is held due to an unpaid fee of RM2.50. Pay within 24 hours or it will be returned: https://poslaju-my-redelivery.top/pay'
  ),
  (
    'Bank TAC (genuine)',
    'RM0 Maybank: Your TAC for Third Party Transfer of RM50.00 to account ending 1234 is 482913. Valid for 3 minutes. Do not share TAC with anyone.'
  ),
  (
    'Fake police call',
    'This is Inspector Lim from PDRM. Your IC is linked to a money laundering case. A warrant will be issued today. Transfer your savings to this safe account 5123 4567 8901 immediately and do not tell anyone.'
  ),
  (
    'Job task offer',
    'Hi! We are hiring part-time. Simple tasks: like and follow YouTube videos, earn RM300 daily. Add me on Telegram t.me/hr_lisa_job to start.'
  ),
];
