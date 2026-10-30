import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/cases.dart';
import '../engine/models.dart';
import '../engine/report.dart';
import '../local_store.dart';
import 'case_tracker.dart';
import 'emergency/hotlines.dart';
import 'emergency/widgets.dart';
import 'guardian_ui.dart';
import 'kit.dart';
import '../state.dart';
import 'theme.dart';
import 'vault/vault_page.dart';

/// The fast path for someone who has already paid or shared details. Calls
/// come first; the paperwork comes after. Deliberately plain and serious.
class EmergencyPage extends StatefulWidget {
  final Investigation? inv;
  final bool embedded;

  /// Opens a saved case's checklist (from the reminder banner).
  final String? caseId;
  const EmergencyPage({super.key, this.inv, this.embedded = false, this.caseId});
  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  final _d = ReportDetails();
  bool _fill = false;

  // One checklist per case, saved on the device and shared with the report
  // page, so progress survives closing the app.
  late final String _caseId = widget.inv != null
      ? caseIdFor(widget.inv!)
      : widget.caseId ?? localStore.latestOpenCase?.id ?? 'case-${DateTime.now().millisecondsSinceEpoch}';
  late final String _caseTitle = widget.inv != null
      ? caseTitleFor(widget.inv)
      : localStore.cases.where((c) => c.id == _caseId).firstOrNull?.title ?? caseTitleFor(null);

  @override
  void initState() {
    super.initState();
    final acct = widget.inv?.artefact.entities.where((e) => e.type == EntityType.bankAccount).firstOrNull;
    if (acct != null) _d.paidTo = acct.value;
  }

  void _call997() {
    dial(nsrcNumber);
    localStore.setStep(localStore.caseFor(_caseId, title: _caseTitle), 'call997', true);
  }

  @override
  Widget build(BuildContext context) {
    final body = PageBody(
      padding: EdgeInsets.fromLTRB(16, 8, 16, widget.embedded ? 110 : 32),
      children: [
        Reveal(child: _Header(onCall: _call997)),
        const SizedBox(height: 16),
        Reveal(index: 1, child: _scriptCard(context)),
        const SizedBox(height: 12),
        GuardianAlertButton(inv: widget.inv, emergency: true),
        const SizedBox(height: 4),
        Reveal(index: 2, child: CaseChecklist(caseId: _caseId, title: _caseTitle)),
        const SizedBox(height: 16),
        Reveal(index: 3, child: _ReportEntry(onOpen: _openReport)),
        const SizedBox(height: 12),
        const Reveal(index: 4, child: VaultCard()),
        const SizedBox(height: 16),
        const HotlineList(),
        const SizedBox(height: 16),
        const _OtherHelp(),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Emergency help')), body: body);
  }

  /// "Prepare my report" goes to the Report tab, pre-filled with this check
  /// and what was typed into the call script.
  void _openReport() {
    if (!widget.embedded) Navigator.of(context).popUntil((r) => r.isFirst);
    appState.openReport(inv: widget.inv, lostMoney: true);
  }

  Widget _scriptCard(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final script = callScript(_d, widget.inv);
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.record_voice_over_outlined, color: K.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('What to say on the call', style: t.titleMedium)),
          const Pill('Read it out', color: K.primary),
        ]),
        const SizedBox(height: 4),
        Text('For 997 or your bank. Fill in the blanks so you do not have to think on the phone.', style: t.bodySmall),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: K.surfaceLow,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            border: Border(left: BorderSide(color: K.primary, width: 3)),
          ),
          child: ScriptText(script, style: t.bodyMedium?.copyWith(height: 1.6, color: K.onSurface)),
        ),
        AnimatedSize(
          duration: K.medium,
          curve: K.curve,
          alignment: Alignment.topCenter,
          child: !_fill
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(children: [
                    _field('How much did you send?', 'RM 1,500', (v) => _d.amount = v, initial: _d.amount),
                    _field('When?', 'Today 3:20pm', (v) => _d.when = v, initial: _d.when),
                    _field('From which bank?', 'Maybank', (v) => _d.paidFromBank = v, initial: _d.paidFromBank),
                    _field('To which account?', 'Account number', (v) => _d.paidTo = v, initial: _d.paidTo),
                    Row(children: [
                      const Icon(Icons.lock_outline_rounded, size: 14, color: K.outline),
                      const SizedBox(width: 6),
                      Expanded(child: Text('Stays on this phone.', style: t.labelSmall?.copyWith(color: K.outline))),
                    ]),
                  ]),
                ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(_fill ? Icons.expand_less_rounded : Icons.edit_outlined, size: 18),
              label: Text(_fill ? 'Done' : 'Fill in blanks'),
              onPressed: () => setState(() => _fill = !_fill),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.content_copy_rounded, size: 18),
              label: const Text('Copy script'),
              onPressed: () => copyText(context, script, 'Call script'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _field(String label, String hint, void Function(String) on, {String initial = ''}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          initialValue: initial,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
          onChanged: (v) => setState(() => on(v)),
        ),
      );
}

class _Header extends StatelessWidget {
  final VoidCallback onCall;
  const _Header({required this.onCall});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: const BoxDecoration(color: emergencyRed, borderRadius: BorderRadius.all(Radius.circular(20))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.emergency_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text('EMERGENCY', style: t.labelMedium?.copyWith(color: Colors.white, letterSpacing: 1.2)),
        ]),
        const SizedBox(height: 10),
        Text('Already paid or shared your details?',
            style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Stay calm and act now. The sooner you call, the better the chance the money can be stopped.',
            style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92))),
        const SizedBox(height: 16),
        Material(
          color: Colors.white,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onCall,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: emergencyRed, shape: BoxShape.circle),
                  child: const Icon(Icons.call_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Call 997 now',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: emergencyRed, letterSpacing: -0.3)),
                    Text('National Scam Response Centre', style: t.bodySmall?.copyWith(color: K.onSurface)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: emergencyRed),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.schedule_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text('$nsrcHours. Call within 24 hours of the transfer.',
                textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
          ),
        ]),
      ]),
    );
  }
}

class _ReportEntry extends StatelessWidget {
  final VoidCallback onOpen;
  const _ReportEntry({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: K.primaryContainer, borderRadius: K.r16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.assignment_outlined, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text('Fast report', style: t.titleMedium?.copyWith(color: Colors.white))),
        ]),
        const SizedBox(height: 6),
        Text(
            'Fill a report in 2 minutes, ready for the police, your bank and Kantoi. '
            'Your own details stay hidden, and you check it before anything is shared.',
            style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.88))),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: K.primary),
          icon: const Icon(Icons.description_outlined),
          label: const Text('Prepare my report'),
          onPressed: onOpen,
        ),
      ]),
    );
  }
}

class _OtherHelp extends StatelessWidget {
  const _OtherHelp();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget row(IconData i, String title, String sub, String url) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(i, color: K.primary),
          title: Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(sub, style: t.bodySmall),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: K.outline),
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        );
    return KCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Other official help', style: t.titleMedium),
        row(Icons.local_police_outlined, 'Police report online', 'PDRM e-Reporting', police.target!),
        row(Icons.manage_search_rounded, 'Check an account or number', 'PDRM Semak Mule', semakMule.target!),
        row(Icons.sms_failed_outlined, 'Report scam SMS, calls or sites', 'MCMC complaints', mcmc.target!),
      ]),
    );
  }
}
