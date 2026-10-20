import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/models.dart';
import '../engine/redaction.dart';
import '../engine/report.dart';
import '../state.dart';
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
  final _details = ReportDetails();
  late final List<PiiMatch> _pii = findPii(widget.inv.artefact.text, ownValues: appState.ownDetails);
  // Indexes of matches kept visible. The scammer's own numbers stay visible by
  // default because they are the evidence; the user's details are masked.
  late final Set<int> _keep = {
    for (var i = 0; i < _pii.length; i++)
      if (_pii[i].type == PiiType.phone || _pii[i].type == PiiType.bankAccount || _pii[i].type == PiiType.email) i
  };
  bool _approved = false;

  String get _maskedText => redact(widget.inv.artefact.text, _pii, keep: _keep);
  String get _report => buildReport(widget.inv, _maskedText, _details, _situation);

  @override
  void initState() {
    super.initState();
    final acct = widget.inv.artefact.entities.where((e) => e.type == EntityType.bankAccount).firstOrNull;
    if (acct != null) _details.paidTo = acct.value;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final money = _situation == Situation.lostMoney;
    return Scaffold(
      appBar: AppBar(title: const Text('Report this scam')),
      body: PageBody(children: [
        Text('Kantoi has filled in the report for you. Check it, then approve. Nothing is sent without your tap.',
            style: t.bodyLarge),
        const SectionTitle('1. What happened?'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in Situation.values)
            ChoiceChip(
              label: Text(situationLabels[s]!),
              selected: _situation == s,
              onSelected: (_) => setState(() {
                _situation = s;
                _approved = false;
              }),
            ),
        ]),
        if (money) ...[
          const SectionTitle('2. Transaction details'),
          Text('Only what you know. Leave the rest empty.', style: t.bodySmall),
          const SizedBox(height: 8),
          _field('Amount', 'RM 1,500', (v) => _details.amount = v),
          _field('Date and time', 'Today 3:20pm', (v) => _details.when = v),
          _field('Your bank', 'Maybank', (v) => _details.paidFromBank = v),
          _field('Paid to (account number)', '', (v) => _details.paidTo = v, initial: _details.paidTo),
          _field('Transaction reference', 'From your banking app receipt', (v) => _details.transactionRef = v),
        ],
        SectionTitle(money ? '3. Privacy check' : '2. Privacy check'),
        if (_pii.isEmpty)
          Text('No personal details found in the message.', style: t.bodyMedium)
        else
          Card(
            child: Column(children: [
              for (var i = 0; i < _pii.length; i++)
                SwitchListTile(
                  value: !_keep.contains(i),
                  onChanged: (v) => setState(() {
                    v ? _keep.remove(i) : _keep.add(i);
                    _approved = false;
                  }),
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
        SectionTitle(money ? '4. Your report' : '3. Your report'),
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
          for (final (i, c) in channelsFor(_situation, source: widget.inv.artefact.source).indexed)
            ChannelCard(index: i + 1, channel: c, report: _report, details: _details, inv: widget.inv),
          const SizedBox(height: 8),
          OutlinedButton.icon(icon: const Icon(Icons.save_alt_rounded), label: const Text('Save report as a file'), onPressed: _save),
        ],
      ]),
    );
  }

  Widget _field(String label, String hint, void Function(String) on, {String initial = ''}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          initialValue: initial,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onChanged: (v) => setState(() {
            on(v);
            _approved = false;
          }),
        ),
      );

  Future<void> _save() async {
    final loc = await getSaveLocation(suggestedName: 'kantoi-scam-report.txt');
    if (loc == null) return;
    await XFile.fromData(Uint8List.fromList(utf8.encode(_report)), mimeType: 'text/plain').saveTo(loc.path);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report saved.')));
  }
}

class ChannelCard extends StatelessWidget {
  final int index;
  final Channel channel;
  final String report;
  final ReportDetails details;
  final Investigation? inv;
  const ChannelCard({super.key, required this.index, required this.channel, required this.report, required this.details, this.inv});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
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
                label: const Text('Copy report'),
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
