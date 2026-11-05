import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  /// The call script stays folded until asked for, so the page stays short.
  bool _showScript = false;
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
    final t = Theme.of(context).textTheme;
    // Two parts, like Trace: on the blue wash the title and the call card,
    // then a white sheet with the checklist, the call script and the help.
    final body = ListView(padding: EdgeInsets.zero, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Emergency', style: t.displaySmall?.copyWith(fontSize: 34, height: 40 / 34, fontWeight: FontWeight.w400, color: Colors.white)),
          const SizedBox(height: 18),
          Reveal(child: _Header(onCall: _call997)),
        ]),
      ),
      Container(
        constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height * 0.6),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(36))),
        padding: EdgeInsets.fromLTRB(20, 24, 20, widget.embedded ? 110 : 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Reveal(index: 1, child: CaseChecklist(caseId: _caseId, title: _caseTitle)),
          const SizedBox(height: 16),
          Reveal(index: 2, child: _scriptCard(context)),
          const SizedBox(height: 28),
          const _Heading(
            'Report and protect',
            info: 'Prepare my report fills in the police, bank and MCMC forms for you.\n\n'
                'The safe word vault keeps a secret word your family can ask for, so a fake "family member" on the phone is caught.',
          ),
          Reveal(
            index: 3,
            child: KGroup(children: [
              Tooltip(
                message: 'Go to Report',
                child: KGroupRow(
                  icon: Icons.flag_outlined,
                  leading: const TintIcon(Icons.flag_outlined, background: K.surfaceMid, size: 44),
                  label: 'Prepare my report',
                  subtitle: 'For police and your bank',
                  trailing: Icons.north_east_rounded,
                  trailingColor: K.blue,
                  onTap: _openReport,
                ),
              ),
              const VaultCard(row: true),
            ]),
          ),
          GuardianAlertButton(inv: widget.inv, emergency: true),
          const SizedBox(height: 28),
          const _Heading(
            'Official help',
            info: 'Government services. Each opens in your browser.\n\n'
                'Police report: make a police report online (PDRM e-Reporting).\n'
                'Check account: see if a bank account or phone number is linked to scams (PDRM Semak Mule).\n'
                'Report SMS: report a scam SMS, call or website (MCMC complaints).',
          ),
          const _OtherHelp(),
        ]),
      ),
    ]);
    if (widget.embedded) return body;
    // Opened on its own (from a check or a reminder): the same blue wash
    // behind a see-through bar with a back arrow.
    return SkyBackground(
      deep: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(automaticallyImplyLeading: false, foregroundColor: Colors.white, systemOverlayStyle: SystemUiOverlayStyle.light),
        body: body,
      ),
    );
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
      color: const Color(0xFFF6F7F9),
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: K.r12,
            onTap: () => setState(() => _showScript = !_showScript),
            child: Row(
              children: [
                const TintIcon(Icons.record_voice_over_outlined, background: Colors.white, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text('What to say on the call', style: t.titleMedium)),
                Icon(_showScript || _fill ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: K.outline),
              ],
            ),
          ),
          AnimatedSize(
            duration: K.medium,
            curve: K.curve,
            alignment: Alignment.topCenter,
            child: !(_showScript || _fill)
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(color: K.surfaceLow, borderRadius: K.r12),
                      child: ScriptText(script, style: t.bodyMedium?.copyWith(height: 1.6, color: K.onSurface)),
                    ),
                  ),
          ),
          AnimatedSize(
            duration: K.medium,
            curve: K.curve,
            alignment: Alignment.topCenter,
            child: !_fill
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: [
                        _field('How much did you send?', 'RM 1,500', (v) => _d.amount = v, initial: _d.amount),
                        _field('When?', 'Today 3:20pm', (v) => _d.when = v, initial: _d.when),
                        _field('From which bank?', 'Maybank', (v) => _d.paidFromBank = v, initial: _d.paidFromBank),
                        _field('To which account?', 'Account number', (v) => _d.paidTo = v, initial: _d.paidTo),
                        Row(
                          children: [
                            const Icon(Icons.lock_outline_rounded, size: 14, color: K.outline),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('Stays on this phone.', style: t.labelSmall?.copyWith(color: K.outline)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
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
            ],
          ),
        ],
      ),
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

class _Header extends StatefulWidget {
  final VoidCallback onCall;
  const _Header({required this.onCall});
  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  bool _banks = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // A frosted card on the blue wash: the question, the red call bar, the
    // bank hotlines and the 24-hour reminder.
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0x8CFFFFFF),
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        border: Border.all(color: const Color(0xB3FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: emergencyRed, shape: BoxShape.circle),
                child: const Icon(Icons.warning_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text('Scammed right now?', style: t.headlineSmall?.copyWith(fontSize: 22, color: K.onSurface))),
            ],
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              gradient: const LinearGradient(colors: [Color(0xFFC0281F), emergencyRed]),
              boxShadow: [BoxShadow(color: emergencyRed.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                onTap: widget.onCall,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 26),
                      const SizedBox(width: 14),
                      Expanded(child: Text('Call 997 now', style: t.titleLarge?.copyWith(fontSize: 21, fontWeight: FontWeight.w400, color: Colors.white))),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: const Color(0xE6FFFFFF),
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _banks = !_banks),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_outlined, color: K.onSurface),
                    const SizedBox(width: 14),
                    Expanded(child: Text('Call my bank', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w400))),
                    AnimatedRotation(
                      turns: _banks ? 0.5 : 0,
                      duration: K.fast,
                      child: const Icon(Icons.expand_more_rounded, color: K.onSurface),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: K.medium,
            curve: K.curve,
            alignment: Alignment.topCenter,
            child: _banks ? const Padding(padding: EdgeInsets.only(top: 10), child: HotlineList()) : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.schedule_rounded, size: 15, color: emergencyRed),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Call within 24 hours of the transfer.',
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: emergencyRed),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A section heading on the white sheet: dark title with its "i".
class _Heading extends StatelessWidget {
  final String text;
  final String info;
  const _Heading(this.text, {required this.info});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Flexible(child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20))),
          const SizedBox(width: 6),
          InfoButton(title: text, message: info),
        ]),
      );
}

/// The official sites as one grouped card: a blue icon, the name, and an
/// arrow; each opens in the browser.
class _OtherHelp extends StatelessWidget {
  const _OtherHelp();

  @override
  Widget build(BuildContext context) {
    Widget row(IconData i, String title, String sub, String url) => Tooltip(
          message: '$title ($sub), opens in your browser',
          child: KGroupRow(
            icon: i,
            leading: SizedBox(width: 44, height: 32, child: Icon(i, color: K.blue, size: 26)),
            label: title,
            trailing: Icons.north_east_rounded,
            trailingColor: K.blue,
            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        );
    return KGroup(children: [
      row(Icons.local_police_outlined, 'Police report', 'PDRM', police.target!),
      row(Icons.manage_search_rounded, 'Check account', 'Semak Mule', semakMule.target!),
      row(Icons.sms_failed_outlined, 'Report SMS', 'MCMC', mcmc.target!),
    ]);
  }
}
