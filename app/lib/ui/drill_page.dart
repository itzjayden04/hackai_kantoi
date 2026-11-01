import 'package:flutter/material.dart';

import '../awareness/coach.dart';
import '../awareness/drills.dart';
import '../awareness/explainers.dart';
import '../engine/models.dart';
import '../history/history_log.dart';
import 'explainer_card.dart' show explainerIcon;
import 'kit.dart';
import 'learn/learn_widgets.dart';
import 'learn/scam_story.dart';
import 'theme.dart';

/// The training banner on every drill screen.
class PracticeBanner extends StatelessWidget {
  const PracticeBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: K.amber.withValues(alpha: 0.1), borderRadius: K.r8),
        child: const Row(children: [
          Icon(Icons.school_outlined, color: K.amber, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text('Practice. This is not a real message.',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF92400E), fontSize: 13)),
          ),
        ]),
      );
}

/// A short quiz: tap the suspicious words, say Scam or Genuine, see exactly
/// what you missed. A round has [rounds] questions, then a personal score.
class DrillPage extends StatefulWidget {
  static const defaultRounds = 5;
  final Set<CueCategory> focus;

  /// Start with this drill instead of letting the coach pick.
  final Drill? first;
  final int rounds;
  const DrillPage({super.key, this.focus = const {}, this.first, this.rounds = defaultRounds});
  @override
  State<DrillPage> createState() => _DrillPageState();
}

class _DrillPageState extends State<DrillPage> {
  Drill? _drill;
  List<Token> _tokens = const [];
  final _tapped = <int>{};
  DrillResult? _result;
  int _round = 0;
  final _results = <DrillResult>[];
  bool _summary = false;

  @override
  void initState() {
    super.initState();
    coach.load().then((_) {
      if (mounted) _next();
    });
  }

  void _next() {
    if (_round >= widget.rounds) {
      setState(() => _summary = true);
      historyLog.add(HistoryEntry(HistoryType.learn, 'Spot-the-scam quiz',
          detail: '${_results.length} questions', result: 'Quiz $_score/${_results.length}', at: DateTime.now()));
      return;
    }
    final d = _round == 0 && widget.first != null ? widget.first! : coach.next(focus: widget.focus);
    setState(() {
      _drill = d;
      _tokens = tokenize(d.full);
      _tapped.clear();
      _result = null;
      _round++;
    });
  }

  void _again() {
    setState(() {
      _round = 0;
      _results.clear();
      _summary = false;
    });
    _next();
  }

  void _answer(bool scam) {
    final before = coach.level;
    final r = grade(_drill!, _tapped.map((i) => _tokens[i]), saidScam: scam);
    coach.record(r);
    setState(() {
      _result = r;
      _results.add(r);
    });
    if (coach.level != before) {
      final up = coach.level.index > before.index;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(up
              ? 'Well done! Moving up to ${drillLevelLabel(coach.level).toLowerCase()} messages.'
              : 'Let\'s practise some ${drillLevelLabel(coach.level).toLowerCase()} messages again.')));
    }
  }

  int get _score => _results.where((r) => r.passed).length;

  @override
  Widget build(BuildContext context) {
    final d = _drill;
    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : AnimatedSwitcher(
              duration: K.medium,
              child: _summary ? _Summary(key: const ValueKey('sum'), results: _results, onAgain: _again) : _question(d),
            ),
    );
  }

  Widget _question(Drill d) {
    final t = Theme.of(context).textTheme;
    return PageBody(key: ValueKey('q$_round'), children: [
      Row(children: [
        Text('Question $_round of ${widget.rounds}', style: t.labelLarge?.copyWith(color: K.onSurface)),
        const Spacer(),
        Icon(Icons.star_rounded, size: 18, color: _score > 0 ? K.amber : K.outlineVariant),
        const SizedBox(width: 4),
        Text('$_score', style: t.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        for (var i = 0; i < widget.rounds; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: K.medium,
              curve: K.curve,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < _results.length
                    ? (_results[i].passed ? K.green : K.red)
                    : i == _round - 1
                        ? K.primary
                        : K.surfaceHigh,
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 14),
      const PracticeBanner(),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: Text(
            _result == null ? 'Tap the words that look suspicious, then choose.' : 'Here is how you did.',
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (_result == null)
          AnimatedSwitcher(
            duration: K.fast,
            child: Pill('${_tapped.length} marked', key: ValueKey(_tapped.length), color: _tapped.isEmpty ? K.outline : K.amber),
          ),
      ]),
      const SizedBox(height: 10),
      _message(d),
      const SizedBox(height: 16),
      AnimatedSwitcher(
        duration: K.medium,
        switchInCurve: K.curve,
        transitionBuilder: (w, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a), child: w),
        ),
        child: _result == null
            ? _choices()
            : _Feedback(
                key: ValueKey(d.id),
                result: _result!,
                last: _round >= widget.rounds,
                onNext: _next,
              ),
      ),
    ]);
  }

  Widget _choices() => Column(key: const ValueKey('choices'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Your verdict', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: K.onSurfaceVariant)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _VerdictTile(label: 'Scam', sub: 'Do not trust it', icon: Icons.gpp_bad_outlined, color: K.red, onTap: () => _answer(true))),
          const SizedBox(width: 12),
          Expanded(
              child: _VerdictTile(label: 'Genuine', sub: 'Looks normal', icon: Icons.verified_user_outlined, color: K.green, onTap: () => _answer(false))),
        ]),
        if (_tapped.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => setState(_tapped.clear), child: Text('Clear ${_tapped.length} marked word(s)')),
          ),
      ]);

  Widget _message(Drill d) {
    final r = _result;
    Color? bg(int i) {
      final tok = _tokens[i];
      bool hit(Iterable<DrillCue> cues) => cues.any((c) {
            final s = d.span(c);
            return s != null && tok.$1 < s.$2 && tok.$2 > s.$1;
          });
      if (r == null) return _tapped.contains(i) ? K.amber.withValues(alpha: 0.28) : null;
      if (hit(r.missed)) return K.red.withValues(alpha: 0.18);
      if (hit(r.found)) return K.green.withValues(alpha: 0.22);
      if (hit(d.legitCues)) return K.green.withValues(alpha: 0.1);
      if (_tapped.contains(i)) return K.outlineVariant.withValues(alpha: 0.5);
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
        child: AnimatedContainer(
          duration: K.fast,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          decoration: BoxDecoration(
            color: bg(i),
            borderRadius: BorderRadius.circular(6),
            border: missed(i) ? const Border(bottom: BorderSide(color: K.red, width: 2)) : null,
          ),
          child: Text(d.full.substring(tok.$1, tok.$2),
              style: TextStyle(fontSize: 16, height: 1.3, color: K.onSurface, fontWeight: bold ? FontWeight.w700 : null)),
        ),
      );
    }

    final senderEnd = d.sender.length;
    final senderIdx = [for (var i = 0; i < _tokens.length; i++) if (_tokens[i].$1 < senderEnd) i];
    final bodyIdx = [for (var i = 0; i < _tokens.length; i++) if (_tokens[i].$1 > senderEnd) i];
    return KCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: K.surfaceMid, shape: BoxShape.circle),
            child: Icon(switch (d.channel) {
              Channel.sms => Icons.sms_outlined,
              Channel.whatsapp => Icons.chat_outlined,
              Channel.email => Icons.email_outlined,
              Channel.telegram => Icons.send_outlined,
            }, size: 18, color: K.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(children: [for (final i in senderIdx) word(i, bold: true)]),
              Text('${channelLabel(d.channel)} · ${drillLevelLabel(d.level)}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: K.outline)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: K.surfaceLow,
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
          ),
          child: Wrap(runSpacing: 2, children: [for (final i in bodyIdx) word(i)]),
        ),
      ]),
    );
  }
}

class _VerdictTile extends StatelessWidget {
  final String label;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _VerdictTile({required this.label, required this.sub, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: K.r16, side: BorderSide(color: color.withValues(alpha: 0.35))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color)),
              Text(sub, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: K.onSurfaceVariant)),
            ]),
          ),
        ),
      );
}

class _Feedback extends StatelessWidget {
  final DrillResult result;
  final bool last;
  final VoidCallback onNext;
  const _Feedback({super.key, required this.result, required this.last, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = result.drill;
    final right = result.verdictRight;
    // Right verdict but most signs missed still counts as a miss, so say so.
    final c = result.passed ? K.green : (right ? K.amber : K.red);
    final headline = switch ((right, d.isScam)) {
      (true, true) when !result.passed => 'Right, it is a scam. Now find the signs.',
      (true, true) => 'Correct. This is a scam.',
      (true, false) => 'Correct. This one is genuine.',
      (false, true) => 'Careful. This one is a scam.',
      (false, false) => 'This one is actually genuine.',
    };
    Widget cueRow(DrillCue cue, Color col, IconData icon) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: col.withValues(alpha: 0.06), borderRadius: const BorderRadius.all(Radius.circular(12))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, color: col, size: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('"${cue.quote}"', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: K.onSurface)),
                  const SizedBox(height: 2),
                  Text('${cueLabel(cue.category)}: ${cue.why}', style: t.bodySmall),
                ]),
              ),
            ]),
          ),
        );
    final explainer = explainerById(d.explainerId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KCard(
        color: c.withValues(alpha: 0.06),
        borderColor: c.withValues(alpha: 0.4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            PopIn(
                child: Icon(result.passed ? Icons.check_circle_rounded : (right ? Icons.error_rounded : Icons.cancel_rounded),
                    color: c, size: 32)),
            const SizedBox(width: 10),
            Expanded(child: Text(headline, style: t.titleLarge?.copyWith(color: c))),
            if (result.passed) PopIn(child: Pill('+1', color: K.amber, icon: Icons.star_rounded)),
          ]),
          if (d.isScam) ...[
            const SizedBox(height: 8),
            Text('You spotted ${result.found.length} of ${d.riskCues.length} warning signs.', style: t.bodyMedium?.copyWith(color: K.onSurface)),
            const SizedBox(height: 6),
            KProgressBar(value: d.riskCues.isEmpty ? 1 : result.found.length / d.riskCues.length, color: c, height: 6),
          ],
          const SizedBox(height: 10),
          Text(d.lesson, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: K.onSurface, height: 1.4)),
        ]),
      ),
      if (result.missed.isNotEmpty) ...[
        const SectionTitle('Signs you missed'),
        for (final cue in result.missed) cueRow(cue, K.red, Icons.error_outline_rounded),
      ],
      if (result.found.isNotEmpty) ...[
        const SectionTitle('Signs you spotted'),
        for (final cue in result.found) cueRow(cue, K.green, Icons.check_circle_outline_rounded),
      ],
      if (d.legitCues.isNotEmpty) ...[
        SectionTitle(d.isScam ? 'Looks normal' : 'Why it is genuine'),
        for (final cue in d.legitCues) cueRow(cue, K.green, Icons.verified_outlined),
      ],
      if (result.falseTaps.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          d.isScam
              ? 'Some words you marked are normal on their own. Focus on requests for money, codes, links and pressure.'
              : 'Words you marked are normal here. Not every message about money or codes is a scam.',
          style: t.bodySmall,
        ),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(
        icon: Icon(last ? Icons.emoji_events_outlined : Icons.arrow_forward_rounded),
        label: Text(last ? 'See my score' : 'Next question'),
        onPressed: onNext,
      ),
      const SizedBox(height: 8),
      if (explainer != null && explainer.id != 'general')
        OutlinedButton.icon(
          icon: Icon(explainerIcon(explainer.id)),
          label: Text(explainer.genuine ? 'How to tell a genuine message' : 'Learn: ${explainer.name}'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScamStoryPage(e: explainer))),
        ),
      TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Finish for now')),
    ]);
  }
}

class _Summary extends StatelessWidget {
  final List<DrillResult> results;
  final VoidCallback onAgain;
  const _Summary({super.key, required this.results, required this.onAgain});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = results.length;
    final ok = results.where((r) => r.passed).length;
    final frac = n == 0 ? 0.0 : ok / n;
    final c = frac >= 0.8 ? K.green : frac >= 0.5 ? K.primary : K.amber;
    final (title, line) = frac >= 0.8
        ? ('Sharp eyes!', 'You are hard to fool. Keep it up with harder messages next time.')
        : frac >= 0.5
            ? ('Good work', 'You caught most of them. Look again at the signs you missed below.')
            : ('Keep practising', 'Scams are made to look real. A few more rounds and the signs start to jump out.');
    return PageBody(children: [
      const SizedBox(height: 16),
      Center(child: PopIn(child: ScoreRing(value: frac, label: '$ok/$n', sub: 'correct', color: c, size: 132))),
      const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: t.headlineSmall),
      const SizedBox(height: 6),
      Text(line, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
      const SizedBox(height: 20),
      KCard(
        child: Column(children: [
          for (final (i, r) in results.indexed)
            Reveal(
              index: i,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(r.passed ? Icons.check_circle_rounded : Icons.cancel_rounded, color: r.passed ? K.green : K.red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${channelLabel(r.drill.channel)} from ${r.drill.sender}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: K.onSurface)),
                  ),
                  Text(r.drill.isScam ? 'Scam' : 'Genuine', style: t.labelMedium?.copyWith(color: K.outline)),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Text('Your score stays on this phone.', textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: K.outline)),
      const SizedBox(height: 16),
      FilledButton.icon(icon: const Icon(Icons.replay_rounded), label: const Text('Practice again'), onPressed: onAgain),
      const SizedBox(height: 8),
      TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Back to Learn')),
    ]);
  }
}
