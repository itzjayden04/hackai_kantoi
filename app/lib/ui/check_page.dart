
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/investigator.dart';
import '../engine/models.dart';
import '../intake/intake_settings.dart';
import '../intake/router.dart';
import '../intake/share_intake.dart';
import '../state.dart';
import 'activity_log.dart';
import 'emergency_page.dart';
import 'intake_widgets.dart';
import 'result_view.dart';
import 'theme.dart';

class CheckPage extends StatefulWidget {
  const CheckPage({super.key});
  @override
  State<CheckPage> createState() => _CheckPageState();
}

class _CheckPageState extends State<CheckPage> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  List<LogStep> _steps = [];
  Investigation? _result;
  bool _busy = false;
  bool _dragging = false;
  String? _error;
  String? _note;
  String? _fileName;

  @override
  void initState() {
    super.initState();
    pendingShare.addListener(_takeShare);
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeShare());
  }

  @override
  void dispose() {
    pendingShare.removeListener(_takeShare);
    _focus.dispose();
    super.dispose();
  }

  /// Starts a check straight away for anything shared from another app.
  void _takeShare() {
    final item = pendingShare.value;
    if (item == null || !mounted || _busy) return;
    pendingShare.value = null;
    if (item.bytes != null) {
      _check(bytes: item.bytes, name: item.name ?? 'shared file', mime: item.mime, source: Source.share);
    } else {
      _text.text = item.text!;
      _check(text: item.text, source: Source.share);
    }
  }

  /// Every input goes through the intake router, then the investigation.
  Future<void> _check({String? text, Uint8List? bytes, String? name, String? mime, Source? source, IntakeKind? kind}) async {
    if (_busy || (bytes == null && (text ?? '').trim().isEmpty)) return;
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
      _result = null;
      _steps = [];
      _fileName = name;
    });
    try {
      await intakeSettings.load();
      final routed = await routeInput(
        text: text?.trim(),
        bytes: bytes,
        name: name,
        mime: mime,
        forceKind: kind,
        source: source,
        llm: appState.llm,
        situation: 'unsure',
        askConsent: (what) => askMediaConsent(context, what),
        virusTotalKey: intakeSettings.virusTotalKey,
        onStep: (s) {
          if (mounted) setState(() => _steps = s);
        },
      );
      final r = await investigate(routed.text, source: routed.source, options: appState.options, extras: routed.extras, onStep: (s) {
        if (mounted) setState(() => _steps = s);
      });
      appState.addHistory(r);
      if (mounted) {
        setState(() {
          _result = r;
          _note = routed.note;
        });
      }
    } on IntakeError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(String text) => _check(text: text);

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

  Future<void> _addFile() async {
    // Android's picker filters by type itself; elsewhere list what Kantoi reads.
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final f = await openFile(acceptedTypeGroups: [
      if (!android)
        const XTypeGroup(label: 'Screenshots, documents, recordings, apps and chats', extensions: [
          'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'pdf', 'docx', 'docm', 'apk', 'opus', 'ogg', 'mp3', 'm4a', 'aac', 'wav', 'flac',
          'mp4', 'mov', '3gp', 'webm', 'txt', 'json', 'eml', 'zip',
        ]),
    ]);
    if (f == null) return;
    await _check(bytes: await f.readAsBytes(), name: f.name, mime: f.mimeType);
  }

  Future<void> _scanQr() async {
    final v = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (v == null) return;
    _text.text = v;
    await _check(text: v, kind: IntakeKind.qr, source: Source.qr);
  }

  void _clear() => setState(() {
        _text.clear();
        _result = null;
        _steps = [];
        _error = null;
        _note = null;
        _fileName = null;
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return PageBody(children: [
        Text('Is this a scam?', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TriageButtons(
          onUnsure: () => _focus.requestFocus(),
          onPaid: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EmergencyPage(inv: _result))),
        ),
        const SizedBox(height: 16),
        Text('Paste a message, link or email, or add a screenshot, PDF, voice note or app file. Kantoi checks it and tells you what to do.',
            style: t.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _dragging ? scheme.primary : Colors.transparent, width: 2),
          ),
          child: TextField(
            controller: _text,
            focusNode: _focus,
            minLines: 4,
            maxLines: 10,
            decoration: InputDecoration(hintText: _dragging ? 'Drop the file to check it' : 'Paste the suspicious message, link or email here'),
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
          OutlinedButton.icon(onPressed: _busy ? null : _addFile, icon: const Icon(Icons.attach_file_rounded), label: const Text('Add file')),
          if (cameraQrAvailable)
            OutlinedButton.icon(onPressed: _busy ? null : _scanQr, icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('Scan QR')),
          if (_text.text.isNotEmpty || _result != null || _fileName != null)
            TextButton(onPressed: _busy ? null : _clear, child: const Text('Clear')),
        ]),
        if (_fileName != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.insert_drive_file_outlined, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(_fileName!, style: t.bodyMedium, overflow: TextOverflow.ellipsis)),
            Text('Stays on your device', style: t.bodySmall?.copyWith(color: scheme.outline)),
          ]),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        if (_busy && _steps.isNotEmpty) ...[
          const SectionTitle('Checking…'),
          ActivityLog(steps: _steps),
        ],
        if (_result != null) ...[
          if (_note != null) ...[
            const SizedBox(height: 16),
            Text(_note!, style: t.bodyMedium?.copyWith(color: scheme.primary)),
          ],
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
      ]);
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
