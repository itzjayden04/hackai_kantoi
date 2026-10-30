import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../engine/models.dart';
import '../../engine/report.dart' show semakMule;
import '../../engine/taxonomy.dart';
import '../../history/history_log.dart';
import '../../report/report_store.dart';
import '../../report/scam_report.dart';
import '../../state.dart';
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
    final r = req.inv != null ? ScamReport.fromCheck(req.inv!, id: _newId()) : ScamReport(id: _newId());
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
      _view = r.kind == null ? (_group == null ? _View.home : _View.type) : _View.form;
      if (r.kind == null && _group == null) _view = _View.type;
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

  Future<void> _saveDraft() async {
    final r = _r;
    if (r == null || r.status == ReportStatus.sent) return;
    await reportStore.save(r);
  }

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
    return PageBody(padding: const EdgeInsets.fromLTRB(16, 8, 16, 110), children: [
      Text('Report a scam', style: t.headlineMedium),
      const SizedBox(height: 4),
      Text('Help stop scammers and protect others. Takes about 2 minutes.', style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
      const SizedBox(height: 16),
      if (last != null) Reveal(child: _FromLastCheck(inv: last, onReport: () => _start(ScamReport.fromCheck(last, id: _newId()), inv: last))),
      if (mine.any((r) => r.status == ReportStatus.draft)) ...[
        const SizedBox(height: 12),
        Builder(builder: (context) {
          final d = mine.firstWhere((r) => r.status == ReportStatus.draft);
          return KCard(
            color: K.surfaceLow,
            onTap: () => _start(d),
            child: Row(children: [
              const Icon(Icons.edit_note_rounded, color: K.primary),
              const SizedBox(width: 12),
              Expanded(child: Text('Finish your draft: ${d.title}', style: t.titleSmall)),
              const Icon(Icons.chevron_right_rounded, color: K.outline),
            ]),
          );
        }),
      ],
      const SizedBox(height: 20),
      Text(last == null ? 'What happened?' : 'Or choose what happened', style: t.titleMedium),
      const SizedBox(height: 10),
      for (final (i, g) in ScamGroup.values.indexed) ...[
        Reveal(
          index: i + 1,
          child: KCard(
            onTap: () => setState(() {
              _group = g;
              _r = ScamReport(id: _newId());
              _inv = null;
              _view = _View.type;
            }),
            child: Row(children: [
              _GroupIcon(g),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(groupLabel(g), style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text(groupExample(g), style: t.bodySmall),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: K.outline),
            ]),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (mine.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('My reports', style: t.titleMedium),
        const SizedBox(height: 8),
        KCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final r in mine.take(6))
              ListTile(
                leading: Icon(Icons.flag_outlined, color: r.status == ReportStatus.sent ? K.primary : K.outline),
                title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_date(r.updated)),
                trailing: Pill(r.status == ReportStatus.sent ? 'Sent' : 'Draft', color: r.status == ReportStatus.sent ? K.primary : K.outline),
                onTap: () {
                  setState(() {
                    _r = r;
                    _inv = null;
                    _view = r.status == ReportStatus.sent ? _View.review : _View.form;
                    _step = 0;
                  });
                },
              ),
          ]),
        ),
      ],
    ]);
  }

  // ---------------------------------------------------------------- type

  Widget _typePicker(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _r ??= ScamReport(id: _newId());
    final groups = _group == null ? ScamGroup.values : [_group!];
    return Column(children: [
      Expanded(
        child: PageBody(children: [
          _BackRow(onBack: _back),
          Text(_group == null ? 'What kind of scam?' : 'What kind?', style: t.headlineMedium),
          const SizedBox(height: 4),
          Text('Pick the closest. You can change it later.', style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
          const SizedBox(height: 16),
          for (final g in groups) ...[
            if (_group == null) Padding(padding: const EdgeInsets.only(top: 8, bottom: 6), child: Text(groupLabel(g), style: t.labelLarge)),
            for (final k in kindsIn(g)) ...[
              _Choice(
                selected: r.kind == k.code,
                title: k.label,
                subtitle: k.example,
                onTap: () => setState(() => r.kind = k.code),
              ),
              const SizedBox(height: 8),
            ],
          ],
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
      ),
    ]);
  }

  // ---------------------------------------------------------------- form

  static const _steps = ['Who contacted you', 'What happened', 'Money', 'Evidence'];

  Widget _form(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _r!;
    return Column(children: [
      Expanded(
        child: PageBody(children: [
          _BackRow(onBack: _back, label: r.scamKind?.label),
          Text('Step ${_step + 1} of ${_steps.length} · ${_steps[_step]}', style: t.labelLarge?.copyWith(color: K.primary)),
          const SizedBox(height: 8),
          KProgressBar(value: (_step + 1) / _steps.length),
          const SizedBox(height: 16),
          for (var i = 0; i < _step; i++) _DoneStep(title: _steps[i], summary: _summary(r, i), onTap: () => setState(() => _step = i)),
          if (_step > 0) const SizedBox(height: 8),
          switch (_step) {
            0 => _WhoStep(r: r, onChanged: _refresh),
            1 => _WhatStep(r: r, onChanged: _refresh),
            2 => _MoneyStep(r: r, onChanged: _refresh),
            _ => _EvidenceStep(r: r, onChanged: _refresh),
          },
        ]),
      ),
      _BottomBar(
        secondary: _step == 0 ? 'Save draft' : 'Back',
        onSecondary: () async {
          if (_step == 0) {
            await _saveDraft();
            if (context.mounted) showKToast(context, title: 'Draft saved', body: 'Finish it any time from the Report tab.');
            setState(() => _view = _View.home);
          } else {
            setState(() => _step--);
          }
        },
        primary: _step == _steps.length - 1 ? 'Review' : 'Next',
        onPrimary: () async {
          await _saveDraft();
          setState(() {
            if (_step < _steps.length - 1) {
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
            if (r.impersonated.isNotEmpty) "pretending to be '${r.impersonated}'",
          ].join(' · '),
        1 => r.incidentAt == null ? 'No date' : _date(r.incidentAt!),
        2 => r.lostMoney == true ? 'Lost ${r.amountText}' : (r.lostMoney == false ? 'No money lost' : 'Not answered'),
        _ => '',
      };

  // ---------------------------------------------------------------- review

  Widget _review(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _r!;
    final sent = r.status == ReportStatus.sent;
    Widget row(String k, String v) => v.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 120, child: Text(k, style: t.bodySmall)),
              Expanded(child: Text(v, style: t.bodyMedium)),
            ]),
          );
    Widget section(String title, int step, List<Widget> rows) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              if (!sent)
                TextButton(
                    onPressed: () => setState(() {
                          _view = _View.form;
                          _step = step;
                        }),
                    child: const Text('Edit')),
            ]),
            ...rows,
            const Divider(height: 16),
          ]),
        );
    return Column(children: [
      Expanded(
        child: PageBody(children: [
          _BackRow(onBack: _back),
          Text(sent ? 'Your report' : 'Review your report', style: t.headlineMedium),
          const SizedBox(height: 12),
          if (r.missing.isNotEmpty && !sent)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: KCard(
                color: const Color(0xFFFFFBEB),
                borderColor: const Color(0xFFFEF3C7),
                child: Text('Still missing: ${r.missing.join(', ')}.', style: t.bodyMedium?.copyWith(color: const Color(0xFF92400E))),
              ),
            ),
          KCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              section('Scam', 0, [row('Type', r.scamKind?.label ?? '')]),
              section('Who contacted you', 0, [
                row('Channel', r.channel == null ? '' : contactChannelLabel(r.channel!)),
                for (final a in r.attackers) row(identifierLabel(a.type), a.value),
                row('Pretending to be', r.impersonated),
                for (final l in r.links) row('Link', l),
              ]),
              section('What happened', 1, [
                row('When', r.incidentAt == null ? '' : _date(r.incidentAt!)),
                row('Description', r.description),
              ]),
              section('Money', 2, [
                row('Lost money', r.lostMoney == null ? '' : (r.lostMoney! ? 'Yes' : 'No')),
                if (r.lostMoney == true) ...[
                  row('Amount', r.amountText),
                  row('Paid by', r.payment == null ? '' : paymentLabel(r.payment!)),
                  row('Reference', r.transactionRef),
                ],
              ]),
              section('Evidence', 3, [
                row('Screenshots', r.screenshots.isEmpty ? 'None' : '${r.screenshots.length} attached (kept on this phone)'),
                row('Already reported to', [if (r.reportedToPolice) 'Police', if (r.reportedToBank) 'Bank', if (r.reportedTo997) '997'].join(', ')),
                row('Official reference', r.officialRef),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          KCard(
            color: K.surfaceLow,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lock_outline_rounded, color: K.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    'Only masked details go to Kantoi: the scam type, masked numbers (like 012-***-4567), website names and the amount. '
                    'Your name, the message text, screenshots and transaction numbers stay on this phone.',
                    style: t.bodyMedium),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: r.shareWithKantoi,
            onChanged: sent ? null : (v) => setState(() => r.shareWithKantoi = v),
            title: const Text('Add to Kantoi scam database'),
            subtitle: const Text('Helps warn others about this number, account or website.'),
          ),
          const SizedBox(height: 8),
          Text('Report to official channels', style: t.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(icon: const Icon(Icons.call_rounded), label: const Text('Call 997 (NSRC)'), onPressed: () => dial(nsrcNumber)),
            OutlinedButton.icon(
                icon: const Icon(Icons.manage_search_rounded),
                label: const Text('PDRM Semak Mule'),
                onPressed: () => launchUrl(Uri.parse(semakMule.target!), mode: LaunchMode.externalApplication)),
            OutlinedButton.icon(
              icon: const Icon(Icons.description_outlined),
              label: const Text('Police, bank & MCMC forms + PDF'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ReportPage(inv: _inv, initial: r.situation, details: r.toDetails(), caseId: r.id, caseTitle: r.title))),
            ),
          ]),
        ]),
      ),
      if (!sent)
        _BottomBar(
          secondary: 'Save draft',
          onSecondary: () async {
            await _saveDraft();
            setState(() => _view = _View.home);
          },
          primary: 'Submit report',
          onPrimary: r.ready ? _submit : null,
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
    return PageBody(padding: const EdgeInsets.fromLTRB(16, 32, 16, 110), children: [
      Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: K.medium,
          curve: Curves.elasticOut,
          builder: (_, s, c) => Transform.scale(scale: s, child: c),
          child: Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: K.green, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 52),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text('Report saved', textAlign: TextAlign.center, style: t.headlineMedium),
      const SizedBox(height: 6),
      Text(
        r.shareWithKantoi
            ? 'Thank you. The masked details join Kantoi\'s scam database as soon as you are online.'
                '${same > 1 ? ' You have reported this number $same times.' : ''}'
            : 'Thank you. Your report is saved on this phone.',
        textAlign: TextAlign.center,
        style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      KCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('What to do next', style: t.titleMedium),
          const SizedBox(height: 8),
          for (final (i, s) in [
            if (r.lostMoney == true) "Call your bank's fraud line now to freeze the transfer.",
            if (r.lostMoney == true) 'Call 997 (National Scam Response Centre) within 24 hours.',
            'Make a police report: open "Police, bank & MCMC forms" for a ready PDF.',
            'Keep the screenshots and chat. Do not delete the conversation.',
            'Block the scammer on the app they used.',
          ].indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 11, backgroundColor: K.surfaceHigh, child: Text('${i + 1}', style: t.labelSmall?.copyWith(color: K.primary))),
                const SizedBox(width: 10),
                Expanded(child: Text(s, style: t.bodyMedium)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      if (r.lostMoney == true)
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: K.red, minimumSize: const Size(0, 52)),
          icon: const Icon(Icons.call_rounded),
          label: const Text('Call 997 now'),
          onPressed: () => dial(nsrcNumber),
        ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ReportPage(inv: _inv, initial: r.situation, details: r.toDetails(), caseId: r.id, caseTitle: r.title))),
        child: const Text('Police, bank & MCMC forms + PDF'),
      ),
      TextButton(
        onPressed: () {
          setState(() => _view = _View.home);
          appState.tab.value = tabCheck;
        },
        child: const Text('Back to Check'),
      ),
    ]);
  }
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

class _GroupIcon extends StatelessWidget {
  final ScamGroup g;
  const _GroupIcon(this.g);
  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: groupColor(g).withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(groupIcon(g), color: groupColor(g)),
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
    return KCard(
      color: K.surfaceLow,
      borderColor: K.primaryContainer.withValues(alpha: 0.3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('From your last check · ${mins < 1 ? 'just now' : mins < 60 ? '$mins min ago' : '${mins ~/ 60} h ago'}',
            style: t.labelMedium?.copyWith(color: K.primary)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          riskPill(inv.verdict.level),
          if (who != null) Pill(who.masked, color: K.onSurfaceVariant, icon: Icons.person_outline_rounded),
        ]),
        const SizedBox(height: 8),
        Text(k?.label ?? inv.verdict.scamType, style: t.titleMedium),
        const SizedBox(height: 12),
        FilledButton.icon(icon: const Icon(Icons.flag_rounded), label: const Text('Report this'), onPressed: onReport),
      ]),
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
        border: Border.all(color: selected ? K.primaryContainer : K.outlineVariant.withValues(alpha: 0.6), width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: K.r16,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: selected ? K.primaryContainer : K.outline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: t.bodySmall),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  final VoidCallback onBack;
  final String? label;
  const _BackRow({required this.onBack, this.label});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Back'),
          if (label != null) Expanded(child: Text(label!, style: Theme.of(context).textTheme.labelLarge, overflow: TextOverflow.ellipsis)),
        ]),
      );
}

class _BottomBar extends StatelessWidget {
  final String primary;
  final VoidCallback? onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;
  const _BottomBar({required this.primary, this.onPrimary, this.secondary, this.onSecondary});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
        decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: K.outlineVariant.withValues(alpha: 0.5)))),
        child: Row(children: [
          if (secondary != null) ...[
            Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: onSecondary, child: Text(secondary!))),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: onPrimary, child: Text(primary)),
          ),
        ]),
      );
}

class _DoneStep extends StatelessWidget {
  final String title;
  final String summary;
  final VoidCallback onTap;
  const _DoneStep({required this.title, required this.summary, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const Icon(Icons.check_circle_rounded, color: K.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$title: ', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              TextSpan(text: summary.isEmpty ? 'done' : summary, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
            ])),
          ),
        ]),
      ),
    );
  }
}

Widget _label(BuildContext context, String s) =>
    Padding(padding: const EdgeInsets.only(top: 12, bottom: 8), child: Text(s, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)));

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
      _label(context, 'How did they contact you?'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in ContactChannel.values)
          ChoiceChip(
            label: Text(contactChannelLabel(c)),
            selected: r.channel == c,
            onSelected: (_) {
              setState(() => r.channel = c);
              widget.onChanged();
            },
          ),
      ]),
      _label(context, 'Their number, email, account or profile'),
      for (final (i, a) in r.attackers.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InputChip(
            avatar: const Icon(Icons.person_outline_rounded, size: 18),
            label: Text('${identifierLabel(a.type)}: ${a.value}'),
            onDeleted: () {
              setState(() => r.attackers.removeAt(i));
              widget.onChanged();
            },
          ),
        ),
      Row(children: [
        DropdownButton<IdentifierType>(
          value: _type,
          underline: const SizedBox.shrink(),
          items: [for (final t in IdentifierType.values) DropdownMenuItem(value: t, child: Text(identifierLabel(t).split(' ').first))],
          onChanged: (t) => setState(() => _type = t ?? _type),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _id,
            decoration: const InputDecoration(hintText: 'e.g. 012-345 6789', isDense: true),
            onSubmitted: (_) => _addId(),
          ),
        ),
        IconButton(onPressed: _addId, icon: const Icon(Icons.add_circle_rounded, color: K.primary), tooltip: 'Add'),
      ]),
      _label(context, 'Who were they pretending to be? (optional)'),
      TextFormField(
        initialValue: r.impersonated,
        decoration: const InputDecoration(hintText: 'e.g. Maybank, Pos Laju, PDRM, your son', isDense: true),
        onChanged: (v) {
          r.impersonated = v;
          widget.onChanged();
        },
      ),
      _label(context, 'Link, website or app they sent (optional)'),
      for (final (i, l) in r.links.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InputChip(
            avatar: const Icon(Icons.link_rounded, size: 18),
            label: Text(l, overflow: TextOverflow.ellipsis),
            onDeleted: () {
              setState(() => r.links.removeAt(i));
              widget.onChanged();
            },
          ),
        ),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'https://…', isDense: true),
            onSubmitted: (_) => _addLink(),
          ),
        ),
        IconButton(onPressed: _addLink, icon: const Icon(Icons.add_circle_rounded, color: K.primary), tooltip: 'Add'),
      ]),
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
        _label(context, 'When did it happen?'),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), alignment: Alignment.centerLeft),
          icon: const Icon(Icons.calendar_today_rounded),
          label: Text(r.incidentAt == null ? 'Pick date and time' : _date(r.incidentAt!)),
          onPressed: () => _pick(context),
        ),
        _label(context, 'What happened? In your own words'),
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

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label(context, 'Did you lose money?'),
      SegmentedButton<bool>(
        segments: const [ButtonSegment(value: true, label: Text('Yes')), ButtonSegment(value: false, label: Text('No'))],
        emptySelectionAllowed: true,
        selected: {?r.lostMoney},
        onSelectionChanged: (s) => _set(() => r.lostMoney = s.firstOrNull),
      ),
      if (r.lostMoney == true) ...[
        _label(context, 'How much?'),
        Row(children: [
          DropdownButton<String>(
            value: r.currency,
            underline: const SizedBox.shrink(),
            items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (c) => _set(() {
              r.currency = c ?? r.currency;
              r.amountMinor = ScamReport.parseAmount(_amount.text, r.currency);
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
              decoration: const InputDecoration(hintText: '3,500.00', isDense: true),
              onChanged: (v) => _set(() => r.amountMinor = ScamReport.parseAmount(v, r.currency)),
            ),
          ),
        ]),
        _label(context, 'How did you pay?'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in PaymentMethod.values)
            ChoiceChip(label: Text(paymentLabel(p)), selected: r.payment == p, onSelected: (_) => _set(() => r.payment = p)),
        ]),
        _label(context, 'Transaction ID or blockchain hash (optional)'),
        TextFormField(
          initialValue: r.transactionRef,
          decoration: const InputDecoration(hintText: 'From your bank receipt or wallet', isDense: true),
          onChanged: (v) => r.transactionRef = v,
        ),
        const SizedBox(height: 12),
        KCard(
          color: const Color(0xFFFEF2F2),
          borderColor: const Color(0xFFFECACA),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: K.red),
            const SizedBox(width: 10),
            Expanded(child: Text('Call your bank and 997 now if you have not. The first hour matters most.', style: Theme.of(context).textTheme.bodyMedium)),
          ]),
        ),
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

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label(context, 'Screenshots (chat, receipt, website)'),
      Text('They stay on this phone and go into your PDF report. Kantoi never uploads them.', style: t.bodySmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (i, s) in r.screenshots.indexed)
          InputChip(
            avatar: const Icon(Icons.image_outlined, size: 18),
            label: Text(s.split(RegExp(r'[\\/]')).last, overflow: TextOverflow.ellipsis),
            onDeleted: () => _set(() => r.screenshots.removeAt(i)),
          ),
        ActionChip(avatar: const Icon(Icons.add_photo_alternate_outlined, size: 18), label: const Text('Add screenshots'), onPressed: _add),
      ]),
      _label(context, 'Already reported to'),
      CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: r.reportedToPolice,
          onChanged: (v) => _set(() => r.reportedToPolice = v ?? false),
          title: const Text('Police (PDRM)')),
      CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: r.reportedToBank,
          onChanged: (v) => _set(() => r.reportedToBank = v ?? false),
          title: const Text('My bank')),
      CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: r.reportedTo997,
          onChanged: (v) => _set(() => r.reportedTo997 = v ?? false),
          title: const Text('997 (NSRC)')),
      if (r.reportedToPolice || r.reportedToBank || r.reportedTo997)
        TextFormField(
          initialValue: r.officialRef,
          decoration: const InputDecoration(labelText: 'Their reference number (optional)', isDense: true),
          onChanged: (v) => r.officialRef = v,
        ),
    ]);
  }
}
