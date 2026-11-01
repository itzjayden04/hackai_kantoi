import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../engine/models.dart';
import '../../engine/report.dart' show semakMule;
import '../../engine/taxonomy.dart';
import '../../history/history_log.dart';
import '../../report/report_store.dart';
import '../../report/scam_report.dart';
import '../../state.dart';
import '../check/check_format.dart' show sourceLabel;
import '../emergency/hotlines.dart';
import '../emergency/widgets.dart';
import '../kit.dart';
import '../report_page.dart';
import '../theme.dart';

enum _View { home, type, form, review, done }

/// The Report tab: pick what happened, fill a short step-by-step form
/// (pre-filled from the last check), review, then send the masked details to
/// Kantoi and open the official channels. The old fast report generator
/// (PDF and per-agency forms) opens from the review step.
class ReportTab extends StatefulWidget {
  const ReportTab({super.key});
  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
  _View _view = _View.home;
  ScamGroup? _group;
  ScamReport? _r;
  Investigation? _inv;
  int _step = 0;
  bool _allReports = false;

  @override
  void initState() {
    super.initState();
    appState.backHandlers[tabReport] = _back;
    appState.reportRequest.addListener(_onRequest);
    reportStore.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRequest());
  }

  @override
  void dispose() {
    if (appState.backHandlers[tabReport] == _back) appState.backHandlers.remove(tabReport);
    appState.reportRequest.removeListener(_onRequest);
    reportStore.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onRequest() {
    final req = appState.reportRequest.value;
    if (req == null) return;
    appState.reportRequest.value = null;
    final r = req.report ?? (req.inv != null ? ScamReport.fromCheck(req.inv!, id: _newId()) : ScamReport(id: _newId()));
    if (req.lostMoney) r.lostMoney = true;
    _start(r, inv: req.inv);
  }

  String _newId() => 'rep-${DateTime.now().millisecondsSinceEpoch}';

  void _start(ScamReport r, {Investigation? inv}) {
    setState(() {
      _r = r;
      _inv = inv;
      _group = r.scamKind?.group;
      _step = 0;
      _view = r.kind == null ? _View.type : _View.form;
    });
  }

  bool _back() {
    switch (_view) {
      case _View.home:
        return false;
      case _View.type:
        setState(() => _view = _View.home);
      case _View.form:
        if (_step > 0) {
          setState(() => _step--);
        } else {
          _saveDraft();
          setState(() => _view = _View.type);
        }
      case _View.review:
        setState(() => _view = _View.form);
      case _View.done:
        setState(() => _view = _View.home);
    }
    return true;
  }

  Future<void> _close() async {
    await _saveDraft();
    if (mounted) setState(() => _view = _View.home);
  }

  Future<void> _saveDraft() async {
    final r = _r;
    if (r == null || r.status == ReportStatus.sent) return;
    // Nothing typed yet: no point keeping an empty draft.
    if (r.kind == null && r.attackers.isEmpty && r.description.trim().isEmpty) return;
    await reportStore.save(r);
  }

  void _openForms() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReportPage(inv: _inv, initial: _r!.situation, details: _r!.toDetails(), caseId: _r!.id, caseTitle: _r!.title)));

  @override
  Widget build(BuildContext context) {
    final child = switch (_view) {
      _View.home => _home(context),
      _View.type => _typePicker(context),
      _View.form => _form(context),
      _View.review => _review(context),
      _View.done => _done(context),
    };
    return AnimatedSwitcher(
      duration: K.medium,
      switchInCurve: K.curve,
      transitionBuilder: (c, a) => FadeTransition(
          opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a), child: c)),
      child: KeyedSubtree(key: ValueKey('$_view$_step'), child: child),
    );
  }

  // ---------------------------------------------------------------- home

  Widget _home(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final last = appState.history.where((i) => i.verdict.level.index >= RiskLevel.suspicious.index).firstOrNull;
    final mine = reportStore.reports;
    final draft = mine.where((r) => r.status == ReportStatus.draft).firstOrNull;
    final shown = _allReports ? mine : mine.take(3).toList();
    return PageBody(padding: const EdgeInsets.fromLTRB(16, 8, 16, 110), children: [
      const Align(alignment: Alignment.centerLeft, child: Pill('Community reports', color: K.secondary, icon: Icons.shield_outlined)),
      const SizedBox(height: 10),
      Text('Report a scam', style: t.headlineMedium),
      const SizedBox(height: 4),
      Text('Help stop scammers and protect others. Takes about 2 minutes.', style: t.bodyMedium?.copyWith(color: K.secondary)),
      const SizedBox(height: 20),
      if (last != null) Reveal(child: _FromLastCheck(inv: last, onReport: () => _start(ScamReport.fromCheck(last, id: _newId()), inv: last))),
      if (draft != null) ...[
        const SizedBox(height: 12),
        KCard(
          color: K.surfaceLow,
          onTap: () => _start(draft),
          child: Row(children: [
            const TintIcon(Icons.edit_note_rounded, background: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Finish your draft', style: t.labelMedium?.copyWith(color: K.primary)),
                Text(draft.title, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: K.outline),
          ]),
        ),
      ],
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: Text(last == null ? 'What happened?' : 'Or choose what happened', style: t.titleMedium)),
        Text('Pick a category', style: t.labelMedium?.copyWith(color: K.secondary)),
      ]),
      const SizedBox(height: 12),
      for (final (i, g) in ScamGroup.values.indexed) ...[
        Reveal(
          index: i + 1,
          child: KCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            onTap: () => setState(() {
              _group = g;
              _r = ScamReport(id: _newId());
              _inv = null;
              _view = _View.type;
            }),
            child: Row(children: [
              TintIcon(groupIcon(g), color: K.primaryContainer, background: K.surfaceMid, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(groupLabel(g), style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text(groupExample(g), style: t.bodySmall?.copyWith(color: K.secondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: K.outline),
            ]),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (mine.isNotEmpty) ...[
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Text('My reports', style: t.titleMedium)),
          if (mine.length > 3)
            TextButton(
              onPressed: () => setState(() => _allReports = !_allReports),
              child: Text(_allReports ? 'Show less' : 'View all (${mine.length})'),
            ),
        ]),
        const SizedBox(height: 6),
        KCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final (i, r) in shown.indexed) ...[
              if (i > 0) const Divider(indent: 16, endIndent: 16),
              _MyReportRow(
                r: r,
                onTap: () => setState(() {
                  _r = r;
                  _inv = null;
                  _view = r.status == ReportStatus.sent ? _View.review : _View.form;
                  _step = 0;
                }),
              ),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 20),
      KCard(
        color: K.surfaceMid,
        onTap: () => dial(nsrcNumber),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const TintIcon(Icons.phone_in_talk_rounded, color: Colors.white, background: K.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Just lost money?', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text.rich(TextSpan(style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant), children: const [
                TextSpan(text: 'Call the National Scam Response Centre at '),
                TextSpan(text: '997', style: TextStyle(fontWeight: FontWeight.w800, color: K.primary)),
                TextSpan(text: ' straight away. Open 24 hours. Tap to call.'),
              ])),
            ]),
          ),
        ]),
      ),
    ]);
  }

  // ---------------------------------------------------------------- type

  Widget _typePicker(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _r ??= ScamReport(id: _newId());
    final groups = _group == null ? ScamGroup.values : [_group!];
    return Column(children: [
      _Header(title: 'Report type', onBack: _back, onClose: _close),
      Expanded(
        child: PageBody(children: [
          if (_group != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: K.surfaceMid, borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(groupIcon(_group!), size: 16, color: K.primary),
                  const SizedBox(width: 6),
                  Text(groupLabel(_group!), style: t.labelMedium?.copyWith(color: K.onSurface)),
                  const Icon(Icons.chevron_right_rounded, size: 16, color: K.outline),
                  Text('Type', style: t.labelMedium?.copyWith(color: K.secondary, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          const SizedBox(height: 14),
          Text(_group == null ? 'What kind of scam?' : 'What kind?', style: t.headlineMedium),
          const SizedBox(height: 4),
          Text('Pick the closest one. You can change it later.', style: t.bodyMedium?.copyWith(color: K.secondary)),
          const SizedBox(height: 18),
          for (final g in groups) ...[
            if (_group == null) SectionLabel(groupLabel(g)),
            for (final k in kindsIn(g)) ...[
              _Choice(
                selected: r.kind == k.code,
                title: k.label,
                subtitle: k.example,
                onTap: () => setState(() => r.kind = k.code),
              ),
              const SizedBox(height: 10),
            ],
            if (_group == null) const SizedBox(height: 8),
          ],
          const SizedBox(height: 6),
          _InfoCard(
            icon: Icons.verified_user_outlined,
            title: 'Not completely sure?',
            body: _inv != null
                ? 'Kantoi already guessed the type from the message you checked. Pick the closest one and change it on the review page if needed.'
                : 'Pick the closest one. The type only decides which official forms Kantoi fills in for you, and you can change it on the review page.',
          ),
        ]),
      ),
      _BottomBar(
        primary: 'Next',
        onPrimary: r.kind == null
            ? null
            : () => setState(() {
                  _view = _View.form;
                  _step = 0;
                }),
        note: 'Saved only on this phone until you submit',
      ),
    ]);
  }

  // ---------------------------------------------------------------- form

  static const _steps = ['Who contacted you', 'What happened', 'Money lost', 'Evidence'];
  static const _short = ['Contact', 'Incident', 'Loss', 'Evidence'];

  Widget _form(BuildContext context) {
    final r = _r!;
    final last = _step == _steps.length - 1;
    return Column(children: [
      _Header(title: r.scamKind?.label ?? 'Report form', onBack: _back, onClose: _close),
      Expanded(
        child: PageBody(children: [
          _Stepper(step: _step, names: _steps, short: _short, onJump: (i) => setState(() => _step = i)),
          const SizedBox(height: 12),
          for (var i = 0; i < _step; i++) ...[
            _DoneStep(step: i + 1, title: _short[i], summary: _summary(r, i), onTap: () => setState(() => _step = i)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          KCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: switch (_step) {
              0 => _WhoStep(r: r, onChanged: _refresh),
              1 => _WhatStep(r: r, onChanged: _refresh),
              2 => _MoneyStep(r: r, onChanged: _refresh),
              _ => _EvidenceStep(r: r, onChanged: _refresh),
            },
          ),
          if (_step == 2 && r.lostMoney == true) ...[
            const SizedBox(height: 14),
            const _InfoCard(
              icon: Icons.bolt_rounded,
              title: 'The first hours matter most',
              body: "If you paid in the last 24 hours, call your bank's fraud line and 997 now. "
                  'The sooner they know, the better the chance of stopping the money.',
            ),
          ],
        ]),
      ),
      _BottomBar(
        secondary: _step == 0 ? 'Save draft' : 'Back',
        secondaryIcon: _step == 0 ? Icons.bookmark_border_rounded : Icons.arrow_back_rounded,
        onSecondary: () async {
          if (_step == 0) {
            await _saveDraft();
            if (context.mounted) showKToast(context, title: 'Draft saved', body: 'Finish it any time from the Report tab.');
            setState(() => _view = _View.home);
          } else {
            setState(() => _step--);
          }
        },
        primary: last ? 'Review' : 'Next',
        primaryNote: last ? null : _short[_step + 1],
        onPrimary: () async {
          await _saveDraft();
          setState(() {
            if (!last) {
              _step++;
            } else {
              _view = _View.review;
            }
          });
        },
      ),
    ]);
  }

  String _summary(ScamReport r, int step) => switch (step) {
        0 => [
            if (r.channel != null) contactChannelLabel(r.channel!),
            if (r.attackers.isNotEmpty) r.attackers.first.masked,
            if (r.impersonated.isNotEmpty) "as '${r.impersonated}'",
          ].join(' · '),
        1 => [
            if (r.incidentAt != null) _date(r.incidentAt!),
            if (r.description.trim().isNotEmpty) r.description.trim(),
          ].join(' · '),
        2 => r.lostMoney == true ? 'Lost ${r.amountText}' : (r.lostMoney == false ? 'No money lost' : 'Not answered'),
        _ => '',
      };

  // ---------------------------------------------------------------- review

  Widget _review(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _r!;
    final sent = r.status == ReportStatus.sent;
    void edit(int step) => setState(() {
          _view = _View.form;
          _step = step;
        });
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13);
    return Column(children: [
      _Header(title: sent ? 'Your report' : 'Review', onBack: _back, onClose: _close),
      Expanded(
        child: PageBody(children: [
          if (!sent) ...[
            Row(children: [
              const Icon(Icons.verified_user_outlined, size: 16, color: K.primary),
              const SizedBox(width: 6),
              Text('LAST STEP · CHECK AND SEND', style: t.labelSmall?.copyWith(color: K.primary, letterSpacing: 0.8)),
            ]),
            const SizedBox(height: 6),
          ],
          Text(sent ? 'Your report' : 'Review your report', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text(sent ? 'Sent ${_date(r.updated)}.' : 'Check the details before sending. Only masked details ever leave this phone.',
              style: t.bodyMedium?.copyWith(color: K.secondary)),
          const SizedBox(height: 16),
          if (r.missing.isNotEmpty && !sent) ...[
            KCard(
              color: K.tertiaryFixed.withValues(alpha: 0.6),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: K.tertiaryContainer),
                const SizedBox(width: 10),
                Expanded(child: Text('Still missing: ${r.missing.join(', ')}.', style: t.bodyMedium?.copyWith(color: K.tertiaryContainer))),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          KCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: r.lostMoney == true ? K.error : K.primary, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(r.scamKind?.label ?? 'Scam report', style: t.titleMedium)),
                if (r.lostMoney == true) const Pill('Money lost', color: K.error),
              ]),
              const SizedBox(height: 14),
              _ReviewBlock(title: 'Who contacted you', onEdit: sent ? null : () => edit(0), rows: [
                ('Channel', r.channel == null ? '' : contactChannelLabel(r.channel!), null),
                for (final a in r.attackers) (identifierLabel(a.type), a.value, null),
                ('Pretending to be', r.impersonated, null),
                for (final l in r.links) ('Link', l, mono.copyWith(color: K.error)),
              ]),
              _ReviewBlock(title: 'Money', onEdit: sent ? null : () => edit(2), rows: [
                (
                  'Money lost',
                  r.lostMoney == null ? '' : (r.lostMoney! ? 'Yes · ${r.amountText}' : 'No'),
                  r.lostMoney == true ? t.titleMedium?.copyWith(color: K.error, fontWeight: FontWeight.w700) : null,
                ),
                if (r.lostMoney == true) ...[
                  ('Paid by', r.payment == null ? '' : paymentLabel(r.payment!), null),
                  ('Reference', r.transactionRef, mono),
                ],
                ('When', r.incidentAt == null ? '' : _date(r.incidentAt!), null),
              ]),
              _ReviewBlock(
                title: 'What happened',
                onEdit: sent ? null : () => edit(1),
                rows: const [],
                child: r.description.trim().isEmpty
                    ? Text('Not written yet', style: t.bodyMedium?.copyWith(color: K.outline))
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: Colors.white, borderRadius: K.r8),
                        child: Text('"${r.description.trim()}"', style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                      ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Icon(Icons.photo_library_outlined, color: K.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Evidence screenshots (${r.screenshots.length})', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            if (!sent) TextButton.icon(onPressed: () => edit(3), icon: const Icon(Icons.add_circle_outline_rounded, size: 18), label: const Text('Add')),
          ]),
          const SizedBox(height: 6),
          if (r.screenshots.isEmpty)
            Text('None attached. Screenshots make a police report much stronger.', style: t.bodySmall)
          else
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: r.screenshots.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _Thumb(r.screenshots[i]),
              ),
            ),
          const SizedBox(height: 16),
          KCard(
            color: K.surfaceLow,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const TintIcon(Icons.lock_outline_rounded, color: Colors.white, background: K.primary, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Only masked details leave this phone', style: t.titleSmall?.copyWith(color: K.primary, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                      'Kantoi gets the scam type, masked numbers (like 012-***-4567), website names and the amount. '
                      'Your name, the message text, screenshots and transaction numbers stay here.',
                      style: t.bodySmall?.copyWith(color: K.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('Send to', style: t.titleMedium),
          const SizedBox(height: 8),
          KCard(
            child: Row(children: [
              const TintIcon(Icons.hub_outlined, color: K.primary, background: K.surfaceMid),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Kantoi scam database', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Warns other Kantoi users about this number, account or website. Sent when you are online.', style: t.bodySmall),
                ]),
              ),
              Switch(value: r.shareWithKantoi, onChanged: sent ? null : (v) => setState(() => r.shareWithKantoi = v)),
            ]),
          ),
          const SizedBox(height: 20),
          SectionLabel('Official helplines', note: r.lostMoney == true ? 'Act within 24 hours' : null, noteColor: K.error),
          Row(children: [
            Expanded(child: _HelpTile(icon: Icons.phone_in_talk_rounded, color: K.error, title: 'Call 997', sub: 'NSRC, 24 hours', onTap: () => dial(nsrcNumber))),
            const SizedBox(width: 8),
            Expanded(
              child: _HelpTile(
                icon: Icons.manage_search_rounded,
                color: K.primary,
                title: 'Semak Mule',
                sub: 'PDRM check',
                onTap: () => launchUrl(Uri.parse(semakMule.target!), mode: LaunchMode.externalApplication),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: _HelpTile(
                    icon: Icons.account_balance_outlined, color: K.primary, title: 'My bank', sub: 'Fraud lines', onTap: () => showHotlineSheet(context))),
          ]),
          const SizedBox(height: 20),
          if (!sent) ...[
            FilledButton.icon(icon: const Icon(Icons.send_rounded), label: const Text('Submit report'), onPressed: r.ready ? _submit : null),
            const SizedBox(height: 10),
          ],
          Row(children: [
            if (!sent) ...[
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.bookmark_border_rounded, size: 18),
                  label: const Text('Save draft'),
                  onPressed: () async {
                    await _saveDraft();
                    setState(() => _view = _View.home);
                  },
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Police forms + PDF'),
                onPressed: _openForms,
              ),
            ),
          ]),
          const SizedBox(height: 90),
        ]),
      ),
    ]);
  }

  Future<void> _submit() async {
    final r = _r!;
    await reportStore.submit(r);
    await historyLog.add(HistoryEntry(HistoryType.report, r.title,
        detail: r.lostMoney == true ? 'Lost ${r.amountText}' : '', result: 'sent', at: DateTime.now(), ref: r.id));
    setState(() => _view = _View.done);
  }

  // ---------------------------------------------------------------- done

  Widget _done(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _r!;
    final same = r.attackers.isEmpty
        ? 0
        : reportStore.reports
            .where((x) => x.status == ReportStatus.sent && x.attackers.any((a) => r.attackers.any((b) => identifierCode(a) == identifierCode(b))))
            .length;
    final lost = r.lostMoney == true;
    final steps = <(String, String, bool)>[
      if (lost) ("Call your bank's fraud line now", 'Ask them to freeze the receiving account and flag the ${r.amountText} payment.', false),
      if (lost) ('Call 997 within 24 hours', 'The National Scam Response Centre can work with the banks to trace and hold the money.', true),
      ('Make a police report', 'Open "Police forms + PDF" for a ready-made report you can bring to the station.', false),
      ('Keep the screenshots', 'Do not delete the chat or the bank slip. The police may ask for them.', false),
      ('Block the scammer', 'Block them on the app they used so they cannot reach you again.', false),
    ];
    return Column(children: [
      _Header(title: 'Report done', onBack: _back),
      Expanded(
        child: PageBody(padding: const EdgeInsets.fromLTRB(16, 8, 16, 110), children: [
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: K.medium,
              curve: Curves.elasticOut,
              builder: (_, s, c) => Transform.scale(scale: s, child: c),
              child: Container(
                width: 112,
                height: 112,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: K.primaryFixed.withValues(alpha: 0.6), shape: BoxShape.circle),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(color: K.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 44),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(r.shareWithKantoi ? 'Report sent' : 'Report saved', textAlign: TextAlign.center, style: t.headlineMedium),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(style: t.bodyLarge?.copyWith(color: K.onSurfaceVariant), children: [
              const TextSpan(text: 'Thank you. '),
              if (same > 1) ...[
                const TextSpan(text: 'You have now reported this number '),
                TextSpan(text: '$same times', style: const TextStyle(fontWeight: FontWeight.w800, color: K.primary)),
                const TextSpan(text: '. '),
              ],
              TextSpan(
                  text: r.shareWithKantoi
                      ? 'The masked details join the Kantoi scam database as soon as you are online.'
                      : 'Your report is kept on this phone only.'),
            ]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: K.surfaceMid, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.verified_user_outlined, size: 16, color: K.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Ref ${reportRef(r)} · ${r.shareWithKantoi ? 'masked copy queued' : 'on this phone'}',
                      textAlign: TextAlign.center, style: t.labelMedium?.copyWith(color: K.primary)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 22),
          KCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.checklist_rounded, color: K.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('What to do next', style: t.titleMedium)),
                const Pill('In order', color: K.secondary),
              ]),
              const SizedBox(height: 12),
              for (final (i, s) in steps.indexed) ...[
                _NextStep(n: i + 1, title: s.$1, body: s.$2, urgent: s.$3),
                const SizedBox(height: 8),
              ],
            ]),
          ),
          const SizedBox(height: 18),
          if (lost) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: K.error),
              icon: const Icon(Icons.phone_in_talk_rounded),
              label: const Text('Call 997 (NSRC)'),
              onPressed: () => dial(nsrcNumber),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(icon: const Icon(Icons.description_outlined, size: 18), label: const Text('Police forms + PDF'), onPressed: _openForms),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back to Check'),
            onPressed: () {
              setState(() => _view = _View.home);
              appState.tab.value = tabCheck;
            },
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.lock_outline_rounded, size: 14, color: K.outline),
            const SizedBox(width: 6),
            Flexible(child: Text('Screenshots and your name never left this phone', style: t.labelSmall?.copyWith(color: K.outline))),
          ]),
        ]),
      ),
    ]);
  }
}

/// Short reference shown to the user, made from the report's own id.
String reportRef(ScamReport r) {
  final d = r.id.replaceAll(RegExp(r'\D'), '');
  final tail = d.length >= 4 ? d.substring(d.length - 4) : d.padLeft(4, '0');
  return '#KT-${r.created.year}-$tail';
}

String _date(DateTime t) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${t.day} ${m[t.month - 1]} ${t.year}, $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

IconData groupIcon(ScamGroup g) => switch (g) {
      ScamGroup.identity => Icons.badge_outlined,
      ScamGroup.finance => Icons.trending_up_rounded,
      ScamGroup.commerce => Icons.shopping_bag_outlined,
      ScamGroup.cyber => Icons.link_off_rounded,
      ScamGroup.social => Icons.favorite_border_rounded,
    };

Color groupColor(ScamGroup g) => switch (g) {
      ScamGroup.identity => K.primaryContainer,
      ScamGroup.finance => K.green,
      ScamGroup.commerce => K.orange,
      ScamGroup.cyber => K.red,
      ScamGroup.social => const Color(0xFFBE185D),
    };

/// Top bar for the report steps: back, title and a close button that keeps a
/// draft.
class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback? onClose;
  const _Header({required this.title, required this.onBack, this.onClose});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Row(children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Back'),
          const SizedBox(width: 4),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (onClose != null) IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded), tooltip: 'Close and keep a draft'),
        ]),
      );
}

class _FromLastCheck extends StatelessWidget {
  final Investigation inv;
  final VoidCallback onReport;
  const _FromLastCheck({required this.inv, required this.onReport});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = kindOf(inv);
    final who = ScamReport.fromCheck(inv, id: 'peek').attackers.firstOrNull;
    final mins = DateTime.now().difference(inv.artefact.receivedAt).inMinutes;
    final ago = mins < 1 ? 'just now' : mins < 60 ? '$mins min ago' : mins < 1440 ? '${mins ~/ 60} h ago' : '${mins ~/ 1440} d ago';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        borderRadius: K.r16,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [K.surfaceMid, K.surfaceLow]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: K.primaryFixed, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const PulseDot(color: K.primary, size: 6),
                const SizedBox(width: 6),
                Flexible(child: Text('From your last check · $ago', style: t.labelMedium?.copyWith(color: K.primary), overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          const Spacer(),
          const Icon(Icons.bolt_rounded, color: K.outline),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          riskPill(inv.verdict.level),
          const SizedBox(width: 10),
          Text('Confidence ${inv.verdict.confidence}%', style: t.labelMedium?.copyWith(color: K.secondary)),
        ]),
        const SizedBox(height: 8),
        Text(k?.label ?? inv.verdict.scamType, style: t.titleLarge),
        if (who != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: const BoxDecoration(color: K.surfaceHigh, borderRadius: K.r12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.person_outline_rounded, size: 18, color: K.secondary),
                  const SizedBox(width: 8),
                  Flexible(child: Text(who.masked, style: const TextStyle(fontFamily: 'monospace', fontSize: 13), overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Seen in ${sourceLabel(inv.artefact)}', style: t.bodySmall?.copyWith(color: K.secondary))),
          ]),
        ],
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: K.primary),
          onPressed: onReport,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Report this'), SizedBox(width: 8), Icon(Icons.arrow_forward_rounded, size: 20)]),
        ),
      ]),
    );
  }
}

class _MyReportRow extends StatelessWidget {
  final ScamReport r;
  final VoidCallback onTap;
  const _MyReportRow({required this.r, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sent = r.status == ReportStatus.sent;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          TintIcon(sent ? Icons.mark_chat_read_outlined : Icons.edit_note_rounded, background: K.surfaceMid, square: true, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(_date(r.updated), style: t.bodySmall),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: sent ? K.primaryFixed : K.surfaceMid, borderRadius: BorderRadius.circular(99)),
            child: Text(sent ? (r.shareWithKantoi ? 'Sent to Kantoi' : 'Sent') : 'Draft',
                style: t.labelMedium?.copyWith(color: sent ? K.primary : K.secondary)),
          ),
          const Icon(Icons.chevron_right_rounded, color: K.outline),
        ]),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _Choice({required this.selected, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: K.fast,
      decoration: BoxDecoration(
        color: selected ? K.surfaceLow : Colors.white,
        borderRadius: K.r16,
        border: Border.all(color: selected ? K.primary : Colors.transparent, width: 1.5),
        boxShadow: selected ? null : K.shadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: K.r16,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(
                duration: K.fast,
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(color: selected ? K.primary : K.surfaceMid, shape: BoxShape.circle),
                child: selected ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: t.titleMedium?.copyWith(color: selected ? K.primary : K.onSurface)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: t.bodyMedium?.copyWith(color: K.secondary)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _InfoCard({required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: K.surfaceMid, borderRadius: K.r16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TintIcon(icon, color: Colors.white, background: K.primary, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleSmall?.copyWith(color: K.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}

/// White card at the top of the form: "STEP 2 OF 4 · WHAT HAPPENED", four
/// bars (green done, navy current) and the step names, each one tappable.
class _Stepper extends StatelessWidget {
  final int step;
  final List<String> names;
  final List<String> short;
  final ValueChanged<int> onJump;
  const _Stepper({required this.step, required this.names, required this.short, required this.onJump});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Color c(int i) => i < step ? K.green : (i == step ? K.primaryContainer : K.surfaceHigh);
    return KCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('STEP ${step + 1} OF ${names.length} · ${names[step].toUpperCase()}',
            style: t.labelMedium?.copyWith(color: K.primary, letterSpacing: 0.8, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(children: [
          for (var i = 0; i < names.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: i < step ? () => onJump(i) : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedContainer(duration: K.medium, height: 6, decoration: BoxDecoration(color: c(i), borderRadius: BorderRadius.circular(99))),
                  const SizedBox(height: 8),
                  Text('${i + 1}. ${short[i]}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelSmall?.copyWith(
                          color: i < step ? K.green : (i == step ? K.primary : K.outline), fontWeight: i == step ? FontWeight.w700 : FontWeight.w500)),
                ]),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final String primary;
  final String? primaryNote;
  final VoidCallback? onPrimary;
  final String? secondary;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;
  final String? note;
  const _BottomBar(
      {required this.primary, this.primaryNote, this.onPrimary, this.secondary, this.secondaryIcon, this.onSecondary, this.note});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        decoration: const BoxDecoration(
          color: K.surface,
          boxShadow: [BoxShadow(color: Color(0x0F0B1C30), blurRadius: 12, offset: Offset(0, -2))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            if (secondary != null) ...[
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), side: BorderSide.none),
                  onPressed: onSecondary,
                  icon: Icon(secondaryIcon ?? Icons.arrow_back_rounded, size: 18),
                  label: Text(secondary!),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onPrimary,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(primary),
                  if (primaryNote != null) Flexible(child: Text(' · $primaryNote', overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ]),
              ),
            ),
          ]),
          if (note != null) ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline_rounded, size: 14, color: K.outline),
              const SizedBox(width: 6),
              Flexible(child: Text(note!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: K.outline))),
            ]),
          ],
        ]),
      );
}

class _DoneStep extends StatelessWidget {
  final int step;
  final String title;
  final String summary;
  final VoidCallback onTap;
  const _DoneStep({required this.step, required this.title, required this.summary, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: K.surfaceLow,
      borderRadius: K.r12,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: K.green.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: K.green, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Step $step · $title', style: t.labelSmall?.copyWith(color: K.secondary)),
                Text(summary.isEmpty ? 'Done' : summary,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            TextButton(onPressed: onTap, child: const Text('Edit')),
          ]),
        ),
      ),
    );
  }
}

/// One tinted block on the review card with an Edit link and label/value rows.
class _ReviewBlock extends StatelessWidget {
  final String title;
  final VoidCallback? onEdit;
  final List<(String, String, TextStyle?)> rows;
  final Widget? child;
  const _ReviewBlock({required this.title, required this.onEdit, required this.rows, this.child});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final shown = rows.where((r) => r.$2.trim().isNotEmpty).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: const BoxDecoration(color: K.surfaceLow, borderRadius: K.r12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title.toUpperCase(), style: t.labelSmall?.copyWith(color: K.secondary, letterSpacing: 0.8))),
          if (onEdit != null)
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
            )
          else
            const SizedBox(height: 36),
        ]),
        if (shown.isEmpty && child == null) Text('Not filled in', style: t.bodyMedium?.copyWith(color: K.outline)),
        for (final (k, v, style) in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 118, child: Text(k, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant))),
              Expanded(child: Text(v, textAlign: TextAlign.right, style: style ?? t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
            ]),
          ),
        ?child,
      ]),
    );
  }
}

class _HelpTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _HelpTile({required this.icon, required this.color, required this.title, required this.sub, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return KCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      onTap: onTap,
      child: Column(children: [
        TintIcon(icon, color: color, size: 40),
        const SizedBox(height: 8),
        Text(title, style: t.labelLarge, textAlign: TextAlign.center),
        Text(sub, style: t.labelSmall?.copyWith(color: color == K.error ? K.error : K.secondary), textAlign: TextAlign.center),
      ]),
    );
  }
}

class _NextStep extends StatelessWidget {
  final int n;
  final String title;
  final String body;
  final bool urgent;
  const _NextStep({required this.n, required this.title, required this.body, this.urgent = false});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = urgent ? K.error : (n == 1 ? K.primary : K.secondary);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: urgent ? K.errorContainer.withValues(alpha: 0.6) : K.surfaceLow, borderRadius: K.r12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 16, backgroundColor: c, child: Text('$n', style: t.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              if (urgent) const Pill('Urgent', color: K.error, solid: true),
            ]),
            const SizedBox(height: 4),
            Text(body, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}

/// Screenshot preview that stays on the phone.
class _Thumb extends StatelessWidget {
  final String path;
  final VoidCallback? onRemove;
  const _Thumb(this.path, {this.onRemove});
  @override
  Widget build(BuildContext context) {
    final name = path.split(RegExp(r'[\\/]')).last;
    return ClipRRect(
      borderRadius: K.r12,
      child: SizedBox(
        width: 104,
        height: 132,
        child: Stack(fit: StackFit.expand, children: [
          Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: 300,
            errorBuilder: (_, _, _) => Container(color: K.surfaceMid, child: const Icon(Icons.image_outlined, color: K.outline)),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(6)),
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ),
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: K.onSurface.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(99)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.phone_android_rounded, size: 10, color: Colors.white),
                SizedBox(width: 3),
                Text('On phone', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'Remove',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Pill choice used for channels and payment methods: navy with a tick when
/// picked, soft blue otherwise.
class _Pick extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pick(this.label, {required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: selected ? K.primaryContainer : K.surfaceMid,
        borderRadius: K.r12,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedPadding(
            duration: K.fast,
            padding: EdgeInsets.fromLTRB(selected ? 12 : 16, 12, 16, 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (selected) ...[const Icon(Icons.check_rounded, size: 18, color: Colors.white), const SizedBox(width: 6)],
              Flexible(child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: selected ? Colors.white : K.onSurface))),
            ]),
          ),
        ),
      );
}

Widget _q(BuildContext context, String s, {String? tag, Color? tagColor}) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Row(children: [
        Expanded(child: Text(s, style: Theme.of(context).textTheme.titleMedium)),
        if (tag != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: (tagColor ?? K.secondary).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
            child: Text(tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tagColor ?? K.secondary)),
          ),
      ]),
    );

Widget _hint(BuildContext context, String s) =>
    Padding(padding: const EdgeInsets.only(top: 6), child: Text(s, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: K.secondary)));

class _WhoStep extends StatefulWidget {
  final ScamReport r;
  final VoidCallback onChanged;
  const _WhoStep({required this.r, required this.onChanged});
  @override
  State<_WhoStep> createState() => _WhoStepState();
}

class _WhoStepState extends State<_WhoStep> {
  IdentifierType _type = IdentifierType.phone;
  final _id = TextEditingController();
  final _link = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    _link.dispose();
    super.dispose();
  }

  void _addId() {
    final v = _id.text.trim();
    if (v.isEmpty) return;
    setState(() {
      widget.r.attackers.add(AttackerId(_type, v));
      _id.clear();
    });
    widget.onChanged();
  }

  void _addLink() {
    final v = _link.text.trim();
    if (v.isEmpty) return;
    setState(() {
      widget.r.links.add(v);
      _link.clear();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _q(context, 'How did they contact you?', tag: 'Required', tagColor: K.error),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in ContactChannel.values)
          _Pick(contactChannelLabel(c), selected: r.channel == c, onTap: () {
            setState(() => r.channel = c);
            widget.onChanged();
          }),
      ]),
      _q(context, 'Their number, email, account or profile'),
      for (final (i, a) in r.attackers.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: const BoxDecoration(color: K.surfaceLow, borderRadius: K.r12),
            child: Row(children: [
              const Icon(Icons.person_outline_rounded, size: 18, color: K.secondary),
              const SizedBox(width: 8),
              Text('${identifierLabel(a.type)}  ', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: K.secondary)),
              Expanded(child: Text(a.value, style: const TextStyle(fontFamily: 'monospace', fontSize: 14), overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  setState(() => r.attackers.removeAt(i));
                  widget.onChanged();
                },
              ),
            ]),
          ),
        ),
      Container(
        padding: const EdgeInsets.only(left: 6),
        decoration: const BoxDecoration(color: K.surfaceLow, borderRadius: K.r12),
        child: Row(children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: K.r8),
            child: DropdownButton<IdentifierType>(
              value: _type,
              underline: const SizedBox.shrink(),
              borderRadius: K.r12,
              items: [for (final t in IdentifierType.values) DropdownMenuItem(value: t, child: Text(identifierLabel(t).split(' ').first))],
              onChanged: (t) => setState(() => _type = t ?? _type),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _id,
              decoration: const InputDecoration(hintText: 'e.g. 012-345 6789', isDense: true, fillColor: Colors.transparent, focusedBorder: InputBorder.none),
              onSubmitted: (_) => _addId(),
            ),
          ),
          IconButton(onPressed: _addId, icon: const Icon(Icons.add_circle_rounded, color: K.primary), tooltip: 'Add'),
        ]),
      ),
      _q(context, 'Who were they pretending to be?', tag: 'Optional'),
      TextFormField(
        initialValue: r.impersonated,
        decoration: const InputDecoration(hintText: 'e.g. Maybank, Pos Laju, PDRM, your son', prefixIcon: Icon(Icons.theater_comedy_outlined, size: 20)),
        onChanged: (v) {
          r.impersonated = v;
          widget.onChanged();
        },
      ),
      _q(context, 'Link, website or app they sent', tag: 'Optional'),
      for (final (i, l) in r.links.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(color: K.errorContainer.withValues(alpha: 0.4), borderRadius: K.r12),
            child: Row(children: [
              const Icon(Icons.link_rounded, size: 18, color: K.error),
              const SizedBox(width: 8),
              Expanded(child: Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: K.error), overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  setState(() => r.links.removeAt(i));
                  widget.onChanged();
                },
              ),
            ]),
          ),
        ),
      TextField(
        controller: _link,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: 'https://…',
          prefixIcon: const Icon(Icons.link_rounded, size: 20),
          suffixIcon: IconButton(onPressed: _addLink, icon: const Icon(Icons.add_circle_rounded, color: K.primary), tooltip: 'Add'),
        ),
        onSubmitted: (_) => _addLink(),
      ),
    ]);
  }
}

class _WhatStep extends StatelessWidget {
  final ScamReport r;
  final VoidCallback onChanged;
  const _WhatStep({required this.r, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: r.incidentAt ?? now, firstDate: DateTime(now.year - 5), lastDate: now);
    if (d == null || !context.mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(r.incidentAt ?? now));
    r.incidentAt = DateTime(d.year, d.month, d.day, tm?.hour ?? 0, tm?.minute ?? 0);
    onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _q(context, 'When did this happen?'),
        Material(
          color: K.surfaceLow,
          borderRadius: K.r12,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _pick(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(children: [
                const Icon(Icons.calendar_month_outlined, color: K.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(r.incidentAt == null ? 'Pick date and time' : _date(r.incidentAt!),
                      style: TextStyle(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                          color: r.incidentAt == null ? K.outline : K.onSurface)),
                ),
                TextButton(onPressed: () => _pick(context), child: Text(r.incidentAt == null ? 'Pick' : 'Change')),
              ]),
            ),
          ),
        ),
        _q(context, 'What happened? In your own words'),
        TextFormField(
          initialValue: r.description,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
              hintText: 'How it started, what they said, what you did, and when you realised it was a scam.', alignLabelWithHint: true),
          onChanged: (v) {
            r.description = v;
            onChanged();
          },
        ),
        _hint(context, 'This stays on your phone and goes into your police report PDF. Kantoi never uploads it.'),
      ]);
}

class _MoneyStep extends StatefulWidget {
  final ScamReport r;
  final VoidCallback onChanged;
  const _MoneyStep({required this.r, required this.onChanged});
  @override
  State<_MoneyStep> createState() => _MoneyStepState();
}

class _MoneyStepState extends State<_MoneyStep> {
  late final _amount = TextEditingController(text: widget.r.amountMinor == null ? '' : widget.r.amountText.replaceAll(RegExp(r'[^\d.,]'), ''));
  late final _ref = TextEditingController(text: widget.r.transactionRef);

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  Widget _yesNo(bool v, String label) {
    final on = widget.r.lostMoney == v;
    return Expanded(
      child: GestureDetector(
        onTap: () => _set(() => widget.r.lostMoney = v),
        child: AnimatedContainer(
          duration: K.fast,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? K.primaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (on) ...[const Icon(Icons.check_rounded, color: Colors.white, size: 18), const SizedBox(width: 6)],
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: on ? Colors.white : K.secondary)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _q(context, 'Did you lose money?', tag: 'Required', tagColor: K.error),
      Text('If you did, Kantoi puts the bank and 997 steps first.', style: t.bodySmall?.copyWith(color: K.secondary)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: K.surfaceMid, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [_yesNo(false, 'No'), const SizedBox(width: 4), _yesNo(true, 'Yes')]),
      ),
      if (r.lostMoney == true) ...[
        _q(context, 'How much did you transfer or lose?'),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          decoration: const BoxDecoration(color: K.surfaceLow, borderRadius: K.r12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: K.r8, boxShadow: K.shadow),
              child: DropdownButton<String>(
                value: r.currency,
                underline: const SizedBox.shrink(),
                borderRadius: K.r12,
                style: const TextStyle(fontWeight: FontWeight.w700, color: K.onSurface, fontFamily: 'Inter', fontSize: 15),
                items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (c) => _set(() {
                  r.currency = c ?? r.currency;
                  r.amountMinor = ScamReport.parseAmount(_amount.text, r.currency);
                }),
              ),
            ),
            const SizedBox(width: 12),
            if (r.currency == 'MYR') const Text('RM', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: K.outline)),
            Expanded(
              child: TextField(
                controller: _amount,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                decoration: const InputDecoration(
                    hintText: '0.00', fillColor: Colors.transparent, focusedBorder: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                onChanged: (v) => _set(() => r.amountMinor = ScamReport.parseAmount(v, r.currency)),
              ),
            ),
          ]),
        ),
        _hint(context, 'The total you sent across all payments.'),
        _q(context, 'How did you pay?'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in PaymentMethod.values) _Pick(paymentLabel(p), selected: r.payment == p, onTap: () => _set(() => r.payment = p)),
        ]),
        _q(context, 'Transaction or reference number', tag: 'Optional'),
        TextField(
          controller: _ref,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'From your bank slip or wallet',
            suffixIcon: IconButton(
              tooltip: 'Paste',
              icon: const Icon(Icons.content_paste_rounded, size: 20),
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                final v = d?.text?.trim() ?? '';
                if (v.isEmpty) return;
                _ref.text = v;
                r.transactionRef = v;
              },
            ),
          ),
          onChanged: (v) => r.transactionRef = v,
        ),
        _hint(context, 'Helps the bank and police find the payment. It stays on this phone.'),
      ],
    ]);
  }
}

class _EvidenceStep extends StatefulWidget {
  final ScamReport r;
  final VoidCallback onChanged;
  const _EvidenceStep({required this.r, required this.onChanged});
  @override
  State<_EvidenceStep> createState() => _EvidenceStepState();
}

class _EvidenceStepState extends State<_EvidenceStep> {
  Future<void> _add() async {
    final files = await openFiles(acceptedTypeGroups: const [XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'webp'])]);
    if (files.isEmpty) return;
    setState(() => widget.r.screenshots.addAll(files.map((f) => f.path)));
    widget.onChanged();
  }

  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  Widget _tick(String label, bool v, ValueChanged<bool> on) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: v ? K.surfaceMid : K.surfaceLow,
          borderRadius: K.r12,
          clipBehavior: Clip.antiAlias,
          child: CheckboxListTile(
            value: v,
            onChanged: (x) => _set(() => on(x ?? false)),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _q(context, 'Screenshots', tag: '${r.screenshots.length} added'),
      Text('Chat, bank slip or the website. They stay on this phone and go into your PDF report. Kantoi never uploads them.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: K.secondary)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (i, s) in r.screenshots.indexed) _Thumb(s, onRemove: () => _set(() => r.screenshots.removeAt(i))),
        Material(
          color: K.surfaceLow,
          borderRadius: K.r12,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _add,
            child: const SizedBox(
              width: 104,
              height: 132,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_photo_alternate_outlined, color: K.primary, size: 28),
                SizedBox(height: 6),
                Text('Add screenshots', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: K.primary)),
              ]),
            ),
          ),
        ),
      ]),
      _q(context, 'Already reported to', tag: 'Optional'),
      _tick('Police (PDRM)', r.reportedToPolice, (v) => r.reportedToPolice = v),
      _tick('My bank', r.reportedToBank, (v) => r.reportedToBank = v),
      _tick('997 (NSRC)', r.reportedTo997, (v) => r.reportedTo997 = v),
      if (r.reportedToPolice || r.reportedToBank || r.reportedTo997) ...[
        const SizedBox(height: 4),
        const FieldLabel('Their reference number (optional)'),
        TextFormField(
          initialValue: r.officialRef,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(hintText: 'e.g. police report number'),
          onChanged: (v) => r.officialRef = v,
        ),
      ],
    ]);
  }
}
