import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'file_out.dart';
import 'theme.dart';

class ReportPage extends StatefulWidget {
  final Investigation inv;
  final Situation initial;
  const ReportPage({super.key, required this.inv, this.initial = Situation.onlyReceived});
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  late Situation _situation = widget.initial;
  late ContactPlatform _platform = platformFor(widget.inv.artefact.source);
  final _details = ReportDetails();
  late final List<PiiMatch> _pii = findPii(widget.inv.artefact.text, ownValues: appState.ownDetails);
  // Indexes of matches kept visible. The scammer's own numbers stay visible by
  // default because they are the evidence; the user's details are masked.
  late final Set<int> _keep = {
    for (var i = 0; i < _pii.length; i++)
      if (_pii[i].type == PiiType.phone || _pii[i].type == PiiType.bankAccount || _pii[i].type == PiiType.email) i
  };
  final List<EvidenceImage> _images = [];
  bool _approved = false;
  bool _busy = false;

  late final String _caseId = caseIdFor(widget.inv);
  late final String _caseTitle = caseTitleFor(widget.inv);

  String get _maskedText => redact(widget.inv.artefact.text, _pii, keep: _keep);
  String get _report => buildReport(widget.inv, _maskedText, _details, _situation);

  @override
  void initState() {
    super.initState();
    final acct = widget.inv.artefact.entities.where((e) => e.type == EntityType.bankAccount).firstOrNull;
    if (acct != null) _details.paidTo = acct.value;
    _details.contactMethod = platformLabels[_platform]!;
  }

  void _changed(VoidCallback f) => setState(() {
        f();
        _approved = false;
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final money = _situation == Situation.lostMoney;
    var n = 0;
    String step(String s) => '${++n}. $s';
    return Scaffold(
      appBar: AppBar(title: const Text('Report this scam')),
      body: PageBody(children: [
        Text('Kantoi has filled in the report for you. Check it, then approve. Nothing is sent without your tap.',
            style: t.bodyLarge),
        SectionTitle(step('What happened?')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in Situation.values)
            ChoiceChip(label: Text(situationLabels[s]!), selected: _situation == s, onSelected: (_) => _changed(() => _situation = s)),
        ]),
        SectionTitle(step('Where did they contact you?')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in ContactPlatform.values)
            ChoiceChip(
              label: Text(platformLabels[p]!),
              selected: _platform == p,
              onSelected: (_) => _changed(() {
                _platform = p;
                _details.contactMethod = platformLabels[p]!;
              }),
            ),
        ]),
        if (money) ...[
          SectionTitle(step('Transaction details')),
          Text('Only what you know. Leave the rest empty.', style: t.bodySmall),
          const SizedBox(height: 8),
          _field('Amount', 'RM 1,500', (v) => _details.amount = v),
          _field('Date and time', 'Today 3:20pm', (v) => _details.when = v),
          _field('Your bank', 'Maybank', (v) => _details.paidFromBank = v),
          _field('Paid to (account number)', '', (v) => _details.paidTo = v, initial: _details.paidTo),
          _field("Scammer's bank", 'CIMB', (v) => _details.scammerBank = v),
          _field('Transaction reference', 'From your banking app receipt', (v) => _details.transactionRef = v),
        ],
        SectionTitle(step('Privacy check')),
        if (_pii.isEmpty)
          Text('No personal details found in the message.', style: t.bodyMedium)
        else
          Card(
            child: Column(children: [
              for (var i = 0; i < _pii.length; i++)
                SwitchListTile(
                  value: !_keep.contains(i),
                  onChanged: (v) => _changed(() => v ? _keep.remove(i) : _keep.add(i)),
                  title: Text('${piiLabel(_pii[i].type)}: ${_pii[i].value}'),
                  subtitle: Text(_keep.contains(i)
                      ? (_pii[i].type == PiiType.phone || _pii[i].type == PiiType.bankAccount
                          ? "Shown. If this is the scammer's, it's evidence"
                          : 'Shown in the report')
                      : 'Hidden as ${mask(_pii[i])}'),
                  secondary: Icon(_keep.contains(i) ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
            ]),
          ),
        SectionTitle(step('Evidence screenshots'),
            trailing: TextButton.icon(onPressed: _addImages, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Add'))),
        if (_images.isEmpty)
          Text('Optional. Add screenshots of the chat, the payment receipt or the scammer\'s profile. They go into the PDF.',
              style: t.bodySmall)
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, img) in _images.indexed)
              Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(img.bytes,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                          width: 96, height: 96, alignment: Alignment.center, color: Colors.black12, child: const Icon(Icons.broken_image_outlined))),
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
        SectionTitle(step('Your report')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(_report, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.45)),
          ),
        ),
        const SizedBox(height: 16),
        if (!_approved)
          FilledButton.icon(
            icon: const Icon(Icons.verified_rounded),
            label: const Text('I have checked it. Approve report'),
            onPressed: () => setState(() => _approved = true),
          )
        else ...[
          Row(children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF15803D)),
            const SizedBox(width: 8),
            Expanded(child: Text('Approved. Send it through these channels, in this order:', style: t.titleSmall)),
          ]),
          const SizedBox(height: 12),
          _ShareToMap(inv: widget.inv, hidden: {for (var i = 0; i < _pii.length; i++) if (!_keep.contains(i)) _pii[i].value}),
          for (final (i, c) in channelsFor(_situation, platform: _platform).indexed)
            ChannelCard(
              index: i + 1,
              channel: c,
              report: _report,
              details: _details,
              inv: widget.inv,
              fields: reportPack(c, widget.inv, _details, _situation, _maskedText),
              caseId: _caseId,
              caseTitle: _caseTitle,
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_rounded),
              label: Text(useShareSheet
                  ? 'Share PDF${_images.isEmpty ? '' : ' and screenshots'}'
                  : 'Save PDF for the police station'),
              onPressed: _busy ? null : _pdf,
            ),
            OutlinedButton.icon(icon: const Icon(Icons.save_alt_rounded), label: const Text('Save report as text'), onPressed: _save),
          ]),
        ],
        const SectionTitle('Your progress'),
        CaseChecklist(caseId: _caseId, title: _caseTitle, compact: true),
      ]),
    );
  }

  Widget _field(String label, String hint, void Function(String) on, {String initial = ''}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          initialValue: initial,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onChanged: (v) => _changed(() => on(v)),
        ),
      );

  Future<void> _addImages() async {
    final files = await openFiles(acceptedTypeGroups: const [
      XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg'],
          mimeTypes: ['image/png', 'image/jpeg'],
          uniformTypeIdentifiers: ['public.image']),
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
        inv: widget.inv,
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

  Future<void> _save() async {
    final msg = await saveOrShare(
        [(name: 'kantoi-scam-report.txt', bytes: Uint8List.fromList(utf8.encode(_report)), mime: 'text/plain')],
        subject: 'Scam report');
    if (mounted) showSnack(context, msg);
  }
}

/// The case checklist step each channel completes.
String? _stepFor(Channel c) => switch (c.id) {
      'nsrc' => 'call997',
      'bank' => 'callBank',
      'police' => 'police',
      'semakmule' => null,
      _ => 'platform',
    };

class ChannelCard extends StatelessWidget {
  final int index;
  final Channel channel;
  final String report;
  final ReportDetails details;
  final Investigation? inv;

  /// The report pack: each form field, in the order the channel asks for it.
  final List<PackField> fields;
  final String? caseId;
  final String caseTitle;
  const ChannelCard({
    super.key,
    required this.index,
    required this.channel,
    required this.report,
    required this.details,
    this.inv,
    this.fields = const [],
    this.caseId,
    this.caseTitle = 'My scam case',
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final stepId = _stepFor(channel);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 14, child: Text('$index', style: const TextStyle(fontSize: 13))),
              const SizedBox(width: 10),
              Expanded(child: Text(channel.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              if (caseId != null && stepId != null)
                ListenableBuilder(
                  listenable: localStore,
                  builder: (context, _) {
                    final c = localStore.caseFor(caseId!, title: caseTitle);
                    final done = c.done.containsKey(stepId);
                    return FilterChip(
                      label: Text(done ? 'Done' : 'Mark done'),
                      selected: done,
                      onSelected: (v) => localStore.setStep(c, stepId, v),
                    );
                  },
                ),
            ]),
            const SizedBox(height: 6),
            Text(channel.why),
            const SizedBox(height: 6),
            for (final s in channel.steps) Text('• $s', style: t.bodyMedium),
            if (channel.id == 'nsrc' || channel.id == 'bank') ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                child: SelectableText('What to say:\n${callScript(details, inv)}'),
              ),
            ],
            if (fields.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Copy each answer into the form, in this order:', style: t.labelLarge),
              const SizedBox(height: 4),
              for (final f in fields) _FieldRow(f),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (channel.kind == ChannelKind.call && channel.target != null)
                FilledButton.icon(
                  icon: const Icon(Icons.call_rounded),
                  label: Text('Call ${channel.target}'),
                  onPressed: () => launchUrl(Uri.parse('tel:${channel.target}')),
                ),
              if (channel.kind != ChannelKind.call && channel.target != null)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: report));
                    launchUrl(Uri.parse(channel.target!), mode: LaunchMode.externalApplication);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Report copied. Paste it into the form that just opened.')));
                  },
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy full report'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: report));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report copied.')));
                },
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not enough evidence in this message to add it to the scam map.')));
        return;
      }
    } else {
      intel.removeReport(widget.inv);
    }
    setState(() => _on = v);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: CheckboxListTile(
            value: _on,
            onChanged: (v) => _set(v ?? false),
            title: const Text("Add the scammer's links, numbers and accounts to the Kantoi scam map"),
            subtitle: const Text('Helps link this scam to others. Your hidden personal details are never added. You can untick this later.'),
          ),
        ),
      );
}

class _FieldRow extends StatelessWidget {
  final PackField f;
  const _FieldRow(this.f);
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.label, style: t.labelMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
            Text(f.value, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
          ]),
        ),
        IconButton(
          tooltip: 'Copy ${f.label.toLowerCase()}',
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: f.value));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${f.label} copied.')));
          },
        ),
      ]),
    );
  }
}
