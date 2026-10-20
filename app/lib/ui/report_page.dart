import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/attribution/intel_store.dart';
import '../engine/cases.dart';
import '../engine/models.dart';
import '../engine/pdf_report.dart';
import '../engine/redaction.dart';
import '../engine/report.dart';
import '../local_store.dart';
import '../state.dart';
import 'case_tracker.dart';
import 'emergency/hotlines.dart';
import 'emergency/widgets.dart';
import 'file_out.dart';
import 'kit.dart';
import 'theme.dart';

/// The fast report generator: one incident sheet, laid out for whoever the
/// user is reporting to, with a copy button on every line, a PDF and a
/// privacy switch. Nothing leaves the phone until the user taps share.
class ReportPage extends StatefulWidget {
  /// The checked message this report is about. Without one, the user can
  /// pick a recent check or describe what happened.
  final Investigation? inv;
  final Situation initial;
  final String? caseId;
  final String? caseTitle;

  /// Details already typed on the Emergency page.
  final ReportDetails? details;
  const ReportPage({super.key, this.inv, this.initial = Situation.onlyReceived, this.caseId, this.caseTitle, this.details});
  @override
  State<ReportPage> createState() => _ReportPageState();
}

String _fmt(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}

class _ReportPageState extends State<ReportPage> {
  late Situation _situation = widget.initial;
  late Investigation? _inv = widget.inv;
  late ContactPlatform _platform = platformFor(_inv?.artefact.source);
  late Channel _to = _situation == Situation.onlyReceived ? mcmc : police;
  final _details = ReportDetails();
  List<PiiMatch> _pii = const [];
  Set<int> _keep = {};
  bool _mask = true;
  bool _choose = false;
  final List<EvidenceImage> _images = [];
  bool _busy = false;
  final DateTime _prepared = DateTime.now();

  late final String _caseId = widget.inv != null ? caseIdFor(widget.inv!) : widget.caseId ?? 'case-${_prepared.millisecondsSinceEpoch}';
  late final String _caseTitle = widget.inv != null ? caseTitleFor(widget.inv) : widget.caseTitle ?? caseTitleFor(null);

  String get _text => _inv?.artefact.text ?? '';
  String get _maskedText => _mask ? redact(_text, _pii, keep: _keep) : _text;
  String get _report => buildReport(_inv, _maskedText, _details, _situation);

  @override
  void initState() {
    super.initState();
    final d = widget.details;
    if (d != null) {
      _details
        ..amount = d.amount
        ..when = d.when
        ..paidFromBank = d.paidFromBank
        ..paidTo = d.paidTo
        ..transactionRef = d.transactionRef
        ..scammerBank = d.scammerBank;
    }
    _useInv(_inv);
  }

  void _useInv(Investigation? inv) {
    _inv = inv;
    _pii = inv == null ? const [] : findPii(inv.artefact.text, ownValues: appState.ownDetails);
    // The scammer's own numbers stay visible by default because they are the
    // evidence; the user's details are masked.
    _keep = {
      for (var i = 0; i < _pii.length; i++)
        if (_pii[i].type == PiiType.phone || _pii[i].type == PiiType.bankAccount || _pii[i].type == PiiType.email) i
    };
    final acct = inv?.artefact.entities.where((e) => e.type == EntityType.bankAccount).firstOrNull;
    if (acct != null && _details.paidTo.isEmpty) _details.paidTo = acct.value;
    if (inv != null) _platform = platformFor(inv.artefact.source);
    _details.contactMethod = platformLabels[_platform]!;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final money = _situation == Situation.lostMoney;
    final recent = appState.history.where((i) => i.verdict.level.index >= RiskLevel.suspicious.index).take(5).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Report generator')),
      body: PageBody(children: [
        KCard(
          color: K.surfaceHigh,
          borderColor: Colors.transparent,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.assignment_outlined, color: K.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  'Kantoi has filled in what it knows. Check each line, then copy it into the form or share the PDF. '
                  'Nothing is sent until you tap share.',
                  style: t.bodyMedium?.copyWith(color: K.onSurface)),
            ),
          ]),
        ),
        const SectionTitle('Who are you reporting to?'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final c in authorities)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(_authorityIcon(c), size: 18, color: _to == c ? Colors.white : K.primary),
                  label: Text(authorityLabel(c)),
                  selected: _to == c,
                  showCheckmark: false,
                  selectedColor: K.primary,
                  labelStyle: TextStyle(color: _to == c ? Colors.white : K.onSurface, fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _to = c),
                ),
              ),
          ]),
        ),
        if (widget.inv == null) ...[
          const SectionTitle('Which message is it about?'),
          if (recent.isEmpty)
            Text('No risky message checked yet. Describe what happened below, or check the message on the Check tab first.',
                style: t.bodySmall)
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: const Text('None, I will describe it'), selected: _inv == null, onSelected: (_) => setState(() => _useInv(null))),
              for (final i in recent)
                ChoiceChip(
                  label: Text('${i.verdict.scamType}, ${_fmt(i.artefact.receivedAt)}'),
                  selected: _inv == i,
                  onSelected: (_) => setState(() => _useInv(i)),
                ),
            ]),
        ],
        const SectionTitle('What happened?'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in Situation.values)
            ChoiceChip(label: Text(situationLabels[s]!), selected: _situation == s, onSelected: (_) => setState(() => _situation = s)),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<ContactPlatform>(
          initialValue: _platform,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Where did they contact you?', isDense: true),
          items: [for (final p in ContactPlatform.values) DropdownMenuItem(value: p, child: Text(platformLabels[p]!))],
          onChanged: (p) => setState(() {
            _platform = p ?? ContactPlatform.other;
            _details.contactMethod = platformLabels[_platform]!;
          }),
        ),
        if (_inv == null) ...[
          const SizedBox(height: 10),
          _field('Their number, profile or link', 'e.g. +60 11-2345 6789', (v) => _details.scammerContact = v),
          _field('What happened, in your words', 'Short is fine', (v) => _details.story = v, lines: 3),
        ],
        if (money) ...[
          const SectionTitle('Transaction'),
          Text('Only what you know. Leave the rest empty.', style: t.bodySmall),
          const SizedBox(height: 8),
          _field('Amount', 'RM 1,500', (v) => _details.amount = v, initial: _details.amount),
          _field('Date and time', 'Today 3:20pm', (v) => _details.when = v, initial: _details.when),
          _field('Your bank', 'Maybank', (v) => _details.paidFromBank = v, initial: _details.paidFromBank),
          _field('Paid to (account number)', '', (v) => _details.paidTo = v, initial: _details.paidTo),
          _field("Scammer's bank", 'CIMB', (v) => _details.scammerBank = v, initial: _details.scammerBank),
          _field('Transaction reference', 'From your banking app receipt', (v) => _details.transactionRef = v,
              initial: _details.transactionRef),
        ],
        const SizedBox(height: 12),
        _privacyCard(t),
        SectionTitle('Evidence screenshots',
            trailing: TextButton.icon(onPressed: _addImages, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Add'))),
        if (_images.isEmpty)
          Text('Optional. Screenshots of the chat, the payment receipt or their profile go into the PDF.', style: t.bodySmall)
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, img) in _images.indexed)
              Stack(children: [
                ClipRRect(
                  borderRadius: K.r8,
                  child: Image.memory(img.bytes,
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                          width: 88, height: 88, alignment: Alignment.center, color: K.surfaceMid, child: const Icon(Icons.broken_image_outlined))),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => setState(() => _images.removeAt(i)),
                  ),
                ),
              ]),
          ]),
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: K.fast,
          child: KeyedSubtree(key: ValueKey(_to.id), child: _sheet(t)),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(useShareSheet ? 'Share PDF report' : 'Save PDF report'),
          onPressed: _busy ? null : _pdf,
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.content_copy_rounded, size: 18),
              label: const Text('Copy all'),
              onPressed: () => copyText(context, _report, 'Report'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Share text'),
              onPressed: _saveText,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('See the full report text', style: t.titleSmall),
            children: [
              KCard(child: SelectableText(_report, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.45))),
            ],
          ),
        ),
        if (_inv != null) _ShareToMap(inv: _inv!, hidden: {for (var i = 0; i < _pii.length; i++) if (_mask && !_keep.contains(i)) _pii[i].value}),
        const SectionTitle('Your progress'),
        CaseChecklist(caseId: _caseId, title: _caseTitle, compact: true),
      ]),
    );
  }

  Widget _privacyCard(TextTheme t) => KCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: K.surfaceHigh, borderRadius: K.r8),
              child: const Icon(Icons.privacy_tip_outlined, color: K.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mask my personal data', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    _pii.isEmpty
                        ? 'Your name, IC and account numbers are hidden in the report. None were found in this message.'
                        : 'Hides your name, IC and account numbers in the report. The scammer\'s numbers stay, as evidence.',
                    style: t.bodySmall),
              ]),
            ),
            Switch(value: _mask, onChanged: (v) => setState(() => _mask = v)),
          ]),
          if (_mask && _pii.isNotEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: Icon(_choose ? Icons.expand_less_rounded : Icons.tune_rounded, size: 18),
                label: Text(_choose ? 'Done' : 'Choose what to hide (${_pii.length} found)'),
                onPressed: () => setState(() => _choose = !_choose),
              ),
            ),
            if (_choose)
              for (var i = 0; i < _pii.length; i++)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: !_keep.contains(i),
                  onChanged: (v) => setState(() => v ? _keep.remove(i) : _keep.add(i)),
                  title: Text('${piiLabel(_pii[i].type)}: ${_pii[i].value}'),
                  subtitle: Text(_keep.contains(i)
                      ? (_pii[i].type == PiiType.phone || _pii[i].type == PiiType.bankAccount
                          ? "Shown. If this is the scammer's, it's evidence"
                          : 'Shown in the report')
                      : 'Hidden as ${mask(_pii[i])}'),
                ),
          ],
        ]),
      );

  Widget _sheet(TextTheme t) {
    final fields = reportPack(_to, _inv, _details, _situation, _maskedText);
    final v = _inv?.verdict;
    final stepId = switch (_to.id) { 'nsrc' => 'call997', 'bank' => 'callBank', 'police' => 'police', _ => 'platform' };
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const PulseDot(color: K.red, size: 7),
          const SizedBox(width: 4),
          Expanded(child: Text('Incident sheet', style: t.titleLarge)),
          Pill('For ${authorityLabel(_to)}', color: K.primary),
        ]),
        const SizedBox(height: 4),
        Text('Laid out in the order ${_to.name} asks for it.', style: t.bodySmall),
        const SizedBox(height: 12),
        CopyRow(label: 'Prepared', value: _fmt(_prepared), icon: Icons.schedule_rounded),
        CopyRow(label: 'Situation', value: situationLabels[_situation]!, icon: Icons.report_outlined),
        if (v != null) CopyRow(label: 'Kantoi check', value: '${v.scamType}: ${riskLabel(v.level)}, risk ${v.score}/100', icon: Icons.shield_outlined),
        for (final f in fields)
          CopyRow(
            label: f.label,
            value: f.value,
            mono: f.label.contains('account') || f.label.contains('phone') || f.label.contains('link') || f.label.contains('reference'),
          ),
        if (fields.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Fill in the details above and they appear here.', style: t.bodySmall),
          ),
        const Divider(height: 24),
        Text('Next steps', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (final (i, s) in _to.steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 20, child: Text('${i + 1}.', style: t.bodyMedium?.copyWith(color: K.outline))),
              Expanded(child: Text(s, style: t.bodyMedium)),
            ]),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _action(),
          ListenableBuilder(
            listenable: localStore,
            builder: (context, _) {
              final c = localStore.caseFor(_caseId, title: _caseTitle);
              final done = c.done.containsKey(stepId);
              return FilterChip(
                label: Text(done ? 'Done' : 'Mark as done'),
                selected: done,
                onSelected: (v) => localStore.setStep(c, stepId, v),
              );
            },
          ),
        ]),
      ]),
    );
  }

  Widget _action() => switch (_to.id) {
        'nsrc' => FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: emergencyRed, minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.call_rounded),
            label: const Text('Call 997'),
            onPressed: () => dial(nsrcNumber),
          ),
        'bank' => FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Bank fraud lines'),
            onPressed: () => showHotlineSheet(context),
          ),
        _ => FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(_to.id == 'police' ? 'Open e-Reporting' : 'Open complaint form'),
            onPressed: () {
              copyText(context, _report, 'Report');
              launchUrl(Uri.parse(_to.target!), mode: LaunchMode.externalApplication);
            },
          ),
      };

  Widget _field(String label, String hint, void Function(String) on, {String initial = '', int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          initialValue: initial,
          minLines: lines,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
          onChanged: (v) => setState(() => on(v)),
        ),
      );

  Future<void> _addImages() async {
    final files = await openFiles(acceptedTypeGroups: const [
      XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg'], mimeTypes: ['image/png', 'image/jpeg']),
    ]);
    for (final f in files) {
      final bytes = await f.readAsBytes();
      if (mounted) setState(() => _images.add(EvidenceImage(f.name, bytes)));
    }
  }

  Future<void> _pdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await buildPdfReport(
        inv: _inv,
        scamText: _maskedText,
        details: _details,
        situation: _situation,
        scamCase: localStore.caseFor(_caseId, title: _caseTitle),
        images: _images,
      );
      final msg = await saveOrShare([
        (name: 'kantoi-scam-report.pdf', bytes: bytes, mime: 'application/pdf'),
        if (useShareSheet)
          for (final img in _images)
            (name: img.name, bytes: img.bytes, mime: img.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg'),
      ], subject: 'Scam report');
      if (mounted) showSnack(context, msg);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not make the PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveText() async {
    final msg = await saveOrShare(
        [(name: 'kantoi-scam-report.txt', bytes: Uint8List.fromList(utf8.encode(_report)), mime: 'text/plain')],
        subject: 'Scam report');
    if (mounted) showSnack(context, msg);
  }
}

IconData _authorityIcon(Channel c) => switch (c.id) {
      'police' => Icons.local_police_outlined,
      'nsrc' => Icons.support_agent_rounded,
      'bank' => Icons.account_balance_outlined,
      _ => Icons.cell_tower_rounded,
    };

/// Consent to add the scammer's details from this report to the Kantoi scam
/// map on this device. Off until the user ticks it.
class _ShareToMap extends StatefulWidget {
  final Investigation inv;
  final Set<String> hidden;
  const _ShareToMap({required this.inv, required this.hidden});
  @override
  State<_ShareToMap> createState() => _ShareToMapState();
}

class _ShareToMapState extends State<_ShareToMap> {
  late bool _on = intel.hasReport(widget.inv);

  void _set(bool v) {
    if (v) {
      final r = intel.addCommunityReport(widget.inv, exclude: widget.hidden, ownValues: appState.ownDetails);
      if (r == null) {
        showSnack(context, 'Not enough evidence in this message to add it to the scam map.');
        return;
      }
    } else {
      intel.removeReport(widget.inv);
    }
    setState(() => _on = v);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: KCard(
          padding: EdgeInsets.zero,
          child: CheckboxListTile(
            value: _on,
            onChanged: (v) => _set(v ?? false),
            title: const Text("Add the scammer's links, numbers and accounts to the scam map on this phone"),
            subtitle: const Text('Helps link this scam to others on the Trace tab. Your hidden details are never added. You can untick this later.'),
          ),
        ),
      );
}
