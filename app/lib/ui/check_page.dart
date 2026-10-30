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
import 'check/check_widgets.dart';
import 'intake_widgets.dart';
import 'kit.dart';
import 'relationship_page.dart';
import 'result_view.dart';
import 'theme.dart';

/// The Check tab: paste or add something, watch Kantoi check it, then read
/// the result in place.
class CheckPage extends StatefulWidget {
  const CheckPage({super.key});
  @override
  State<CheckPage> createState() => _CheckPageState();
}

class _CheckPageState extends State<CheckPage> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  List<LogStep> _steps = [];
  Investigation? _result;
  bool _busy = false;
  // Bumped to cancel: results of an older run are ignored.
  int _runId = 0;
  String? _error;
  String? _note;
  String? _fileName;
  String _checking = '';

  @override
  void initState() {
    super.initState();
    pendingShare.addListener(_takeShare);
    appState.backHandlers[0] = _back;
    _text.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeShare());
  }

  @override
  void dispose() {
    pendingShare.removeListener(_takeShare);
    if (appState.backHandlers[0] == _back) appState.backHandlers.remove(0);
    _focus.dispose();
    _scroll.dispose();
    _text.dispose();
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
    if (_busy) return;
    if (bytes == null && (text ?? '').trim().isEmpty) {
      setState(() => _error = 'Paste or type the message first, or add a screenshot or file.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final run = ++_runId;
    bool live() => mounted && run == _runId;
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
      _result = null;
      _steps = [];
      _fileName = name;
      _checking = name ?? text!.trim().replaceAll(RegExp(r'\s+'), ' ');
    });
    _toTop();
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
          if (live()) setState(() => _steps = s);
        },
      );
      final r = await investigate(
        routed.text,
        source: routed.source,
        options: appState.options,
        extras: routed.extras,
        onStep: (s) {
          if (live()) setState(() => _steps = s);
        },
      );
      if (!live()) return;
      appState.addHistory(r);
      if (mounted) {
        setState(() {
          _result = r;
          _note = routed.note;
        });
        _toTop();
      }
    } on IntakeError catch (e) {
      if (live()) setState(() => _error = e.message);
    } catch (e) {
      if (live()) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (live()) setState(() => _busy = false);
    }
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: K.medium, curve: K.curve);
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

  Future<void> _pick(List<XTypeGroup> groups) async {
    final f = await openFile(acceptedTypeGroups: groups);
    if (f == null) return;
    await _check(bytes: await f.readAsBytes(), name: f.name, mime: f.mimeType);
  }

  // Android's picker filters by MIME type; the extensions help elsewhere.
  Future<void> _addImage() => _pick(const [
    XTypeGroup(label: 'Screenshots and photos', extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'], mimeTypes: ['image/*']),
  ]);

  Future<void> _addFile() {
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return _pick([
      if (!android)
        const XTypeGroup(
          label: 'Screenshots, documents, recordings, apps and chats',
          extensions: [
            'png',
            'jpg',
            'jpeg',
            'webp',
            'gif',
            'bmp',
            'pdf',
            'docx',
            'docm',
            'apk',
            'opus',
            'ogg',
            'mp3',
            'm4a',
            'aac',
            'wav',
            'flac',
            'mp4',
            'mov',
            '3gp',
            'webm',
            'txt',
            'json',
            'eml',
            'zip',
          ],
        ),
    ]);
  }

  Future<void> _scanQr() async {
    final v = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (v == null) return;
    _text.text = v;
    await _check(text: v, kind: IntakeKind.qr, source: Source.qr);
  }

  /// Back button: stop a running check, or close the result, and return
  /// to the empty Check screen. False when there is nothing to go back from.
  bool _back() {
    if (!_busy && _result == null && _error == null) return false;
    _runId++;
    _busy = false;
    _clear();
    return true;
  }

  void _clear() {
    setState(() {
      _text.clear();
      _result = null;
      _steps = [];
      _error = null;
      _note = null;
      _fileName = null;
      _checking = '';
    });
    _toTop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final inset = MediaQuery.paddingOf(context).bottom;
    final idle = !_busy && _result == null;
    final showBar = !_busy && _result != null;
    return Stack(
      children: [
        ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(16, 8, 16, inset + (showBar ? 96 : 32)),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Is this a scam?', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Check a message, link, email, screenshot or file. Kantoi tells you what to do.',
                      style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    AnimatedSize(
                      duration: K.medium,
                      curve: K.curve,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: K.medium,
                        switchInCurve: K.curve,
                        transitionBuilder: _fadeSlide,
                        layoutBuilder: _topLayout,
                        child: idle ? _intakeCard(t) : _checkingCard(t),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      KCard(
                        color: K.errorContainer.withValues(alpha: 0.5),
                        borderColor: Colors.transparent,
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: K.error),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_error!, style: t.bodyMedium?.copyWith(color: K.onErrorContainer)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: K.medium,
                      switchInCurve: K.curve,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: _fadeSlide,
                      layoutBuilder: _topLayout,
                      child: _busy
                          ? PipelineView(key: const ValueKey('pipeline'), steps: _steps)
                          : _result != null
                          ? Column(
                              key: ObjectKey(_result),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_note != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.info_outline_rounded, size: 18, color: K.primary),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(_note!, style: t.bodySmall?.copyWith(color: K.primary)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ResultView(inv: _result!, inlineActions: false),
                              ],
                            )
                          : _home(t),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSwitcher(
            duration: K.medium,
            switchInCurve: K.curve,
            transitionBuilder: (w, a) => SlideTransition(
              position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(a),
              child: w,
            ),
            child: showBar ? StickyActions(key: ObjectKey(_result), inv: _result!, onNew: _clear, bottomInset: inset) : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  static Widget _fadeSlide(Widget w, Animation<double> a) => FadeTransition(
    opacity: a,
    child: SlideTransition(
      position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
      child: w,
    ),
  );

  static Widget _topLayout(Widget? current, List<Widget> previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]);

  Widget _intakeCard(TextTheme t) {
    Widget iconBtn(IconData icon, String tip, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton.filledTonal(
        tooltip: tip,
        style: IconButton.styleFrom(backgroundColor: K.surfaceLow, foregroundColor: K.onSurfaceVariant),
        icon: Icon(icon, size: 20),
        onPressed: onTap,
      ),
    );
    return Container(
      key: const ValueKey('intake'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: K.r16,
        boxShadow: const [BoxShadow(color: Color(0x140B1C30), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Scam check', style: t.labelLarge?.copyWith(color: K.onSurfaceVariant)),
              ),
              const Icon(Icons.lock_outline_rounded, size: 14, color: K.outline),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Personal details hidden',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(color: K.outline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            focusNode: _focus,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: 'Paste a message, link, email, bank account or phone number...',
              filled: true,
              fillColor: K.surfaceLow,
              border: const OutlineInputBorder(borderRadius: K.r8, borderSide: BorderSide.none),
              enabledBorder: const OutlineInputBorder(borderRadius: K.r8, borderSide: BorderSide.none),
              focusedBorder: const OutlineInputBorder(
                borderRadius: K.r8,
                borderSide: BorderSide(color: K.primary, width: 1.5),
              ),
              suffixIcon: _text.text.isEmpty
                  ? null
                  : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded, size: 18), onPressed: _text.clear),
            ),
            onSubmitted: _run,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      backgroundColor: K.surfaceHigh,
                      foregroundColor: K.primary,
                      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _pasteAndCheck,
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: const Text('Paste & check', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              iconBtn(Icons.add_photo_alternate_outlined, 'Screenshot or photo', _addImage),
              if (cameraQrAvailable) iconBtn(Icons.qr_code_scanner_rounded, 'Scan a QR code', _scanQr),
              iconBtn(Icons.attach_file_rounded, 'PDF, Word, voice note, app or chat file', _addFile),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: () => _run(_text.text), icon: const Icon(Icons.policy_outlined), label: const Text('Check with Kantoi AI')),
          const SizedBox(height: 10),
          Text(
            'Also reads screenshots, PDFs, Word files, voice notes, app files (APK) and WhatsApp chat exports.',
            style: t.bodySmall?.copyWith(color: K.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// What is being (or was) checked, with a way to start again.
  Widget _checkingCard(TextTheme t) => KCard(
    key: const ValueKey('checking'),
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    child: Row(
      children: [
        Icon(_fileName != null ? Icons.insert_drive_file_outlined : Icons.sms_outlined, color: K.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_busy ? 'Checking' : 'Checked', style: t.labelMedium?.copyWith(color: K.outline)),
              Text(_checking, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
            ],
          ),
        ),
        TextButton(onPressed: _busy ? null : _clear, child: const Text('New check')),
      ],
    ),
  );

  Widget _home(TextTheme t) => ListenableBuilder(
    key: const ValueKey('home'),
    listenable: appState,
    builder: (context, _) {
      final history = appState.history;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Reveal(index: 0, child: ProtectionStatusCard()),
          const SizedBox(height: 12),
          Reveal(
            index: 1,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: WayInTile(
                      icon: Icons.people_outline_rounded,
                      title: 'Check a person or chat',
                      subtitle: 'Love, job or investment chats',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RelationshipScreen())),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WayInTile(
                      icon: Icons.emergency_outlined,
                      color: K.red,
                      title: 'Already paid?',
                      subtitle: 'Get help right now',
                      onTap: () => appState.tab.value = tabEmergency,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (history.isNotEmpty) ...[
            SectionTitle(
              'Recent checks',
              trailing: history.length > 3
                  ? TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage())),
                      child: const Text('See all'),
                    )
                  : null,
            ),
            for (final (i, h) in history.take(3).indexed)
              Reveal(
                index: i + 2,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RecentCheckCard(inv: h),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Reveal(index: 5, child: _samples(t)),
        ],
      );
    },
  );

  Widget _samples(TextTheme t) => KCard(
    color: K.surfaceLow,
    borderColor: Colors.transparent,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.tips_and_updates_outlined, color: K.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Not sure what to check? Try a sample', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, icon, text) in samples)
              ActionChip(
                avatar: Icon(icon, size: 18, color: K.primary),
                backgroundColor: Colors.white,
                side: BorderSide.none,
                label: Text(label),
                onPressed: () {
                  _text.text = text;
                  _run(text);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Made-up examples for practice.', style: t.labelSmall?.copyWith(color: K.outline)),
      ],
    ),
  );
}

/// Practice messages: a parcel scam and a genuine bank TAC first, so the
/// demo shows a real message judged correctly too.
const samples = [
  (
    'Parcel scam SMS',
    Icons.local_shipping_outlined,
    'POS MALAYSIA: Your parcel is held due to an unpaid fee of RM2.50. Pay within 24 hours or it will be returned: https://poslaju-my-redelivery.top/pay',
  ),
  (
    'Real bank TAC',
    Icons.account_balance_outlined,
    'RM0 Maybank: Your TAC for Third Party Transfer of RM50.00 to account ending 1234 is 482913. Valid for 3 minutes. Do not share TAC with anyone.',
  ),
  (
    'Fake police call',
    Icons.local_police_outlined,
    'This is Inspector Lim from PDRM. Your IC is linked to a money laundering case. A warrant will be issued today. Transfer your savings to this safe account 5123 4567 8901 immediately and do not tell anyone.',
  ),
  (
    'Job task offer',
    Icons.work_outline_rounded,
    'Hi! We are hiring part-time. Simple tasks: like and follow YouTube videos, earn RM300 daily. Add me on Telegram t.me/hr_lisa_job to start.',
  ),
];
