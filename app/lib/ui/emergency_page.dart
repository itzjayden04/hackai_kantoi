import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/models.dart';
import '../engine/report.dart';
import 'guardian_ui.dart';
import 'report_page.dart';
import 'theme.dart';

/// The fast path for someone who has already paid or shared details. Calls
/// come first; the paperwork comes after.
class EmergencyPage extends StatefulWidget {
  final Investigation? inv;
  final bool embedded;
  const EmergencyPage({super.key, this.inv, this.embedded = false});
  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  final _d = ReportDetails();
  final _done = <String>{};

  static const _steps = [
    ('call997', 'Call 997 (National Scam Response Centre)', 'Every minute counts. They can work with banks to freeze the money.'),
    ('callBank', 'Call your bank', 'Use the number on the back of your card. Ask them to block your account and card.'),
    ('passwords', 'Change your passwords', 'Banking app first, then email. Log out of all other devices.'),
    ('stop', 'Stop all contact with the scammer', 'Do not pay any "recovery fee". Recovery offers are a second scam.'),
    ('police', 'Make a police report within 24 hours', 'Your bank will ask for it. Kantoi prepares it for you below.'),
  ];

  @override
  void initState() {
    super.initState();
    final acct = widget.inv?.artefact.entities.where((e) => e.type == EntityType.bankAccount).firstOrNull;
    if (acct != null) _d.paidTo = acct.value;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const red = Color(0xFFDC2626);
    final body = PageBody(children: [
      Text("Act now. You're not alone.", style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text('If you transferred money or shared a code in the last few hours, call first. Kantoi will help with the rest.',
          style: t.bodyLarge),
      const SizedBox(height: 16),
      SizedBox(
        height: 72,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: red, textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          icon: const Icon(Icons.call_rounded, size: 30),
          label: const Text('Call 997 now'),
          onPressed: () {
            launchUrl(Uri.parse('tel:997'));
            setState(() => _done.add('call997'));
          },
        ),
      ),
      const SizedBox(height: 6),
      Text('On a computer? Dial 997 from your phone.', style: t.bodySmall, textAlign: TextAlign.center),
      const SizedBox(height: 10),
      GuardianAlertButton(inv: widget.inv, emergency: true),
      const SectionTitle('What to say on the call'),
      _field('How much did you send?', 'RM 1,500', (v) => _d.amount = v),
      _field('When?', 'Today 3:20pm', (v) => _d.when = v),
      _field('From which bank?', 'Maybank', (v) => _d.paidFromBank = v),
      _field('To which account?', '', (v) => _d.paidTo = v, initial: _d.paidTo),
      Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(callScript(_d, widget.inv), style: t.bodyLarge?.copyWith(height: 1.5)),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: callScript(_d, widget.inv)));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call script copied.')));
              },
            ),
          ]),
        ),
      ),
      SectionTitle('Your checklist', trailing: Text('${_done.length} of ${_steps.length} done', style: t.bodySmall)),
      Card(
        child: Column(children: [
          for (final s in _steps)
            CheckboxListTile(
              value: _done.contains(s.$1),
              onChanged: (v) => setState(() => v == true ? _done.add(s.$1) : _done.remove(s.$1)),
              title: Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(s.$3),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      if (widget.inv != null)
        FilledButton.icon(
          icon: const Icon(Icons.description_rounded),
          label: const Text('Prepare my full report'),
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => ReportPage(inv: widget.inv!, initial: Situation.lostMoney))),
        )
      else
        Text('To prepare a full report, check the scam message on the Check tab first, then tap "I already paid".',
            style: t.bodySmall),
    ]);
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('I already paid or shared details')), body: body);
  }

  Widget _field(String label, String hint, void Function(String) on, {String initial = ''}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          initialValue: initial,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onChanged: (v) => setState(() => on(v)),
        ),
      );
}
