import 'package:flutter/material.dart';

import '../awareness/coach.dart';
import '../awareness/drills.dart';
import '../awareness/explainers.dart';
import '../engine/models.dart';
import 'explainer_card.dart';
import 'theme.dart';

const _red = Color(0xFFDC2626);
const _green = Color(0xFF15803D);
const _amber = Color(0xFFB45309);

/// The training banner on every drill screen.
class PracticeBanner extends StatelessWidget {
  const PracticeBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _amber.withValues(alpha: 0.6)),
        ),
        child: const Row(children: [
          Icon(Icons.school_rounded, color: _amber),
          SizedBox(width: 10),
          Expanded(
            child: Text('Practice. This is not a real message.', style: TextStyle(fontWeight: FontWeight.w800, color: _amber)),
          ),
        ]),
      );
}

/// Short practice rounds: tap the suspicious words, say Scam or Genuine, see
/// exactly what you missed.
class DrillPage extends StatefulWidget {
  final Set<CueCategory> focus;

  /// Start with this drill instead of letting the coach pick.
  final Drill? first;
  const DrillPage({super.key, this.focus = const {}, this.first});
  @override
  State<DrillPage> createState() => _DrillPageState();
}

class _DrillPageState extends State<DrillPage> {
  Drill? _drill;
  List<Token> _tokens = const [];
  final _tapped = <int>{};
  DrillResult? _result;
  int _round = 0;

  @override
  void initState() {
    super.initState();
    coach.load().then((_) {
      if (mounted) _next();
    });
  }

  void _next() {
    final d = _round == 0 && widget.first != null ? widget.first! : coach.next(focus: widget.focus);
    setState(() {
      _drill = d;
      _tokens = tokenize(d.full);
      _tapped.clear();
      _result = null;
      _round++;
    });
  }

  void _answer(bool scam) {
    final before = coach.level;
    final r = grade(_drill!, _tapped.map((i) => _tokens[i]), saidScam: scam);
    coach.record(r);
    setState(() => _result = r);
    if (coach.level != before) {
      final up = coach.level.index > before.index;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(up
              ? 'Well done! Moving up to ${drillLevelLabel(coach.level)} messages.'
              : 'Let\'s practise some ${drillLevelLabel(coach.level).toLowerCase()} messages again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _drill;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : PageBody(children: [
              const PracticeBanner(),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Chip(label: Text('Level: ${drillLevelLabel(d.level)}'), visualDensity: VisualDensity.compact),
                Chip(
                  avatar: const Icon(Icons.local_fire_department_rounded, size: 18, color: _amber),
                  label: Text('Streak ${coach.streak}'),
                  visualDensity: VisualDensity.compact,
                ),
                Text('Round $_round', style: t.bodySmall),
              ]),
              const SizedBox(height: 12),
              Text(
                _result == null
                    ? 'Tap the words that look suspicious, then choose Scam or Genuine.'
                    : 'Here is how you did.',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _message(d),
              const SizedBox(height: 16),
              if (_result == null) ..._choices(d) else _Feedback(result: _result!, onNext: _next),
            ]),
    );
  }

  List<Widget> _choices(Drill d) => [
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _red),
              icon: const Icon(Icons.gpp_bad_rounded),
              label: const Text('Scam'),
              onPressed: () => _answer(true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _green),
              icon: const Icon(Icons.verified_user_rounded),
              label: const Text('Genuine'),
              onPressed: () => _answer(false),
            ),
          ),
        ]),
        if (_tapped.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => setState(_tapped.clear), child: Text('Clear ${_tapped.length} marked word(s)')),
          ),
      ];

  Widget _message(Drill d) {
    final scheme = Theme.of(context).colorScheme;
    final r = _result;
    Color? bg(int i) {
      final tok = _tokens[i];
      bool hit(Iterable<DrillCue> cues) => cues.any((c) {
            final s = d.span(c);
            return s != null && tok.$1 < s.$2 && tok.$2 > s.$1;
          });
      if (r == null) return _tapped.contains(i) ? _amber.withValues(alpha: 0.3) : null;
      if (hit(r.missed)) return _red.withValues(alpha: 0.22);
      if (hit(r.found)) return _green.withValues(alpha: 0.25);
      if (hit(d.legitCues)) return _green.withValues(alpha: 0.12);
      if (_tapped.contains(i)) return scheme.outlineVariant.withValues(alpha: 0.5);
      return null;
    }

    bool missed(int i) =>
        r != null &&
        r.missed.any((c) {
          final s = d.span(c);
          return s != null && _tokens[i].$1 < s.$2 && _tokens[i].$2 > s.$1;
        });

    Widget word(int i, {bool bold = false}) {
      final tok = _tokens[i];
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: r != null ? null : () => setState(() => _tapped.contains(i) ? _tapped.remove(i) : _tapped.add(i)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          decoration: BoxDecoration(
            color: bg(i),
            borderRadius: BorderRadius.circular(6),
            border: missed(i) ? const Border(bottom: BorderSide(color: _red, width: 2)) : null,
          ),
          child: Text(d.full.substring(tok.$1, tok.$2),
              style: TextStyle(fontSize: 16, height: 1.3, fontWeight: bold ? FontWeight.w700 : null)),
        ),
      );
    }

    final senderEnd = d.sender.length;
    final senderIdx = [for (var i = 0; i < _tokens.length; i++) if (_tokens[i].$1 < senderEnd) i];
    final bodyIdx = [for (var i = 0; i < _tokens.length; i++) if (_tokens[i].$1 > senderEnd) i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(switch (d.channel) {
              Channel.sms => Icons.sms_outlined,
              Channel.whatsapp => Icons.chat_outlined,
              Channel.email => Icons.email_outlined,
              Channel.telegram => Icons.send_outlined,
            }, size: 18, color: scheme.outline),
            const SizedBox(width: 6),
            Text('${channelLabel(d.channel)} from', style: TextStyle(color: scheme.outline)),
          ]),
          Wrap(children: [for (final i in senderIdx) word(i, bold: true)]),
          const Divider(height: 20),
          Wrap(runSpacing: 2, children: [for (final i in bodyIdx) word(i)]),
        ]),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  final DrillResult result;
  final VoidCallback onNext;
  const _Feedback({required this.result, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = result.drill;
    final right = result.verdictRight;
    final c = right ? _green : _red;
    final headline = switch ((right, d.isScam)) {
      (true, true) => 'Correct. This is a scam.',
      (true, false) => 'Correct. This one is genuine.',
      (false, true) => 'Careful. This one is a scam.',
      (false, false) => 'This one is actually genuine.',
    };
    Widget cueRow(DrillCue cue, Color col, IconData icon) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: col, size: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('"${cue.quote}"', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${cueLabel(cue.category)}: ${cue.why}', style: t.bodyMedium),
              ]),
            ),
          ]),
        );
    final explainer = explainerById(d.explainerId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        color: c.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.withValues(alpha: 0.5))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(right ? Icons.check_circle_rounded : Icons.cancel_rounded, color: c, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(headline, style: t.titleLarge?.copyWith(color: c, fontWeight: FontWeight.w800))),
            ]),
            if (d.isScam) ...[
              const SizedBox(height: 6),
              Text('You spotted ${result.found.length} of ${d.riskCues.length} warning signs.', style: t.bodyLarge),
            ],
            const SizedBox(height: 8),
            Text(d.lesson, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.4)),
          ]),
        ),
      ),
      if (result.missed.isNotEmpty) ...[
        const SectionTitle('Signs you missed'),
        for (final cue in result.missed) cueRow(cue, _red, Icons.error_outline_rounded),
      ],
      if (result.found.isNotEmpty) ...[
        const SectionTitle('Signs you spotted'),
        for (final cue in result.found) cueRow(cue, _green, Icons.check_circle_outline_rounded),
      ],
      if (d.legitCues.isNotEmpty) ...[
        SectionTitle(d.isScam ? 'Looks normal' : 'Why it is genuine'),
        for (final cue in d.legitCues) cueRow(cue, _green, Icons.verified_outlined),
      ],
      if (result.falseTaps.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          d.isScam
              ? 'Some words you marked are normal on their own. Focus on requests for money, codes, links and pressure.'
              : 'Words you marked are normal here. Not every message about money or codes is a scam.',
          style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(icon: const Icon(Icons.arrow_forward_rounded), label: const Text('Next practice'), onPressed: onNext),
      const SizedBox(height: 8),
      if (explainer != null && explainer.id != 'general')
        OutlinedButton.icon(
          icon: Icon(explainerIcon(explainer.id)),
          label: Text(explainer.genuine ? 'How to tell a genuine message' : 'Learn: ${explainer.name}'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExplainerPage(e: explainer))),
        ),
      TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Finish for now')),
    ]);
  }
}
