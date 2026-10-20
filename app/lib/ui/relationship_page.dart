import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../engine/cues.dart';
import '../engine/models.dart';
import '../engine/relationship.dart';
import '../engine/relationship_check.dart';
import '../state.dart';
import 'activity_log.dart';
import 'emergency_page.dart';
import 'feedback_bar.dart';
import 'result_view.dart' show HighlightedText;
import '../intake/chat_export.dart';
import 'theme.dart';

class RelationshipPage extends StatefulWidget {
  const RelationshipPage({super.key});
  @override
  State<RelationshipPage> createState() => _RelationshipPageState();
}

class _RelationshipPageState extends State<RelationshipPage> {
  bool _quiz = false;
  final _chat = TextEditingController();
  List<ChatMessage> _msgs = [];
  String? _me;
  Origin _origin = Origin.unknown;
  bool? _video;
  MoneyAnswer _money = MoneyAnswer.unknown;
  final _ids = TextEditingController();
  final Map<String, int> _answers = {};
  RelationshipReport? _report;
  bool _busy = false;
  List<LogStep> _steps = [];

  List<String> get _senders => _msgs.map((m) => m.sender).toSet().toList();

  void _parse() {
    final msgs = parseAnyChatExport(_chat.text);
    setState(() {
      _msgs = msgs;
      _report = null;
      final s = _senders;
      if (_me == null || !s.contains(_me)) _me = s.length == 2 ? s.last : null;
    });
  }

  Future<void> _analyse() async {
    final msgs = _msgs
        .map((m) => ChatMessage(time: m.time, sender: m.sender, text: m.text, fromMe: m.sender == _me))
        .toList();
    setState(() {
      _busy = true;
      _report = null;
      _steps = [];
    });
    try {
      final r = await checkRelationship(msgs,
          origin: _origin,
          metOnVideo: _video,
          money: _money,
          pastedIdentifiers: _ids.text,
          llm: appState.llm,
          ownDetails: appState.ownDetails, onStep: (s) {
        if (mounted) setState(() => _steps = s);
      });
      if (mounted) setState(() => _report = r);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _quizResult() async {
    final r = await checkQuestionnaire(_answers, pastedIdentifiers: _ids.text);
    if (mounted) setState(() => _report = r);
  }

  Widget _idsField() => TextField(
        controller: _ids,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Optional: account number, phone number or profile link they gave you',
          hintText: 'e.g. 5642 1234 5678 or facebook.com/amanda.lee',
        ),
        onChanged: (_) => setState(() => _report = null),
      );

  Future<void> _open() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Chat export', extensions: ['txt', 'json', 'zip'])
    ]);
    if (f == null) return;
    _chat.text = chatExportText(await f.readAsBytes());
    _parse();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PageBody(children: [
      Text('Can I trust this person?', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('Love, investment and job scams build trust over weeks before asking for money. '
          'Kantoi reads the whole conversation and scores how closely it follows a scam script.',
          style: t.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, icon: Icon(Icons.chat_outlined), label: Text('Check a chat')),
          ButtonSegment(value: true, icon: Icon(Icons.quiz_outlined), label: Text('Answer 9 questions')),
        ],
        selected: {_quiz},
        onSelectionChanged: (s) => setState(() {
          _quiz = s.first;
          _report = null;
        }),
      ),
      const SizedBox(height: 16),
      if (!_quiz) ..._chatForm(t) else ..._quizForm(t),
      if (_busy) ...[const SizedBox(height: 16), const LinearProgressIndicator(), const SizedBox(height: 8), ActivityLog(steps: _steps)],
      if (_report != null) ...[const SizedBox(height: 20), RelationshipResult(report: _report!, messages: _quiz ? const [] : _msgs)],
    ]);
  }

  List<Widget> _chatForm(TextTheme t) => [
        Text('In WhatsApp: open the chat, tap ⋮ → More → Export chat → Without media. Then open or paste it here. '
            'Only check chats you are part of. The chat is read on your device.', style: t.bodySmall),
        const SizedBox(height: 8),
        TextField(
          controller: _chat,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(hintText: '12/10/2026, 21:01 - Amanda: Hi, is this Kevin?'),
          onChanged: (_) => _parse(),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(onPressed: _open, icon: const Icon(Icons.folder_open_rounded), label: const Text('Open chat export')),
          TextButton(
              onPressed: () {
                _chat.text = _sampleChat;
                _parse();
              },
              child: const Text('Use an example chat')),
        ]),
        if (_msgs.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('${_msgs.length} messages found.', style: t.bodyMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _me,
            decoration: const InputDecoration(labelText: 'Which name is you?'),
            items: [for (final s in _senders) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: (v) => setState(() => _me = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<Origin>(
            initialValue: _origin,
            decoration: const InputDecoration(labelText: 'How did you first meet them?'),
            items: [for (final o in Origin.values) DropdownMenuItem(value: o, child: Text(originLabels[o]!))],
            onChanged: (v) => setState(() => _origin = v ?? Origin.unknown),
          ),
          const SizedBox(height: 10),
          Text('Have you met in person or on a live video call?', style: t.bodyMedium),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final (label, v) in [('Yes', true), ('No', false), ('Not sure', null)])
              ChoiceChip(label: Text(label), selected: _video == v, onSelected: (_) => setState(() => _video = v)),
          ]),
          const SizedBox(height: 10),
          Text('Has money been asked for or sent?', style: t.bodyMedium),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in [MoneyAnswer.no, MoneyAnswer.asked, MoneyAnswer.sent, MoneyAnswer.unknown])
              ChoiceChip(label: Text(moneyLabels[v]!), selected: _money == v, onSelected: (_) => setState(() => _money = v)),
          ]),
          const SizedBox(height: 12),
          _idsField(),
          const SizedBox(height: 14),
          FilledButton.icon(
              onPressed: _busy ? null : _analyse, icon: const Icon(Icons.insights_rounded), label: const Text('Check this relationship')),
        ],
      ];

  List<Widget> _quizForm(TextTheme t) => [
        Text("No chat export? Answer honestly. Nothing you choose leaves your device.", style: t.bodySmall),
        for (final q in questionnaire) ...[
          const SizedBox(height: 14),
          Text(q.text, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, o) in q.options.indexed)
              ChoiceChip(
                label: Text(o.$1),
                selected: _answers[q.id] == i,
                onSelected: (_) => setState(() {
                  _answers[q.id] = i;
                  _report = null;
                }),
              ),
          ]),
        ],
        const SizedBox(height: 18),
        _idsField(),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _answers.isEmpty ? null : _quizResult,
          icon: const Icon(Icons.insights_rounded),
          label: Text('See my result (${_answers.length}/${questionnaire.length} answered)'),
        ),
      ];
}

class RelationshipResult extends StatelessWidget {
  final RelationshipReport report;
  final List<ChatMessage> messages;
  const RelationshipResult({super.key, required this.report, this.messages = const []});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = riskColor(report.level);
    final signals = [...report.signals]..sort((a, b) => b.weight.compareTo(a.weight));
    final keyMessages = report.keyMessages.where((i) => i < messages.length).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        color: c.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: c.withValues(alpha: 0.5), width: 1.5)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(riskIcon(report.level), color: c, size: 34),
              const SizedBox(width: 12),
              Expanded(child: Text('Relationship risk: ${riskLabel(report.level)}', style: t.titleLarge?.copyWith(color: c, fontWeight: FontWeight.w800))),
              Text('${report.score}', style: t.headlineMedium?.copyWith(color: c, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            Text(report.headline, style: t.titleMedium),
            if (report.daysToFirstMoneyAsk != null || report.daysKnown != null) ...[
              const SizedBox(height: 8),
              Text(
                  [
                    if (report.daysKnown != null) 'You have talked for ${report.daysKnown} day(s).',
                    if (report.daysToFirstMoneyAsk != null) 'Money first came up on day ${report.daysToFirstMoneyAsk}.',
                  ].join(' '),
                  style: t.bodyMedium),
            ],
            if (report.nextStep.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.arrow_forward_rounded, color: c),
                  const SizedBox(width: 10),
                  Expanded(child: Text(report.nextStep, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.35))),
                ]),
              ),
            ],
            if (report.level.index >= RiskLevel.caution.index) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                icon: const Icon(Icons.emergency_rounded),
                label: const Text('I already paid'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmergencyPage())),
              ),
            ],
            const SizedBox(height: 10),
            Text('These signs are consistent with a scam script. They do not prove who this person is.', style: t.bodySmall),
          ]),
        ),
      ),
      if (keyMessages.isNotEmpty) ...[
        const SectionTitle('The messages that matter most'),
        for (final i in keyMessages) ...[
          Text('${messages[i].sender}${messages[i].time == null ? '' : ', ${_date(messages[i].time!)}'}', style: t.labelMedium),
          const SizedBox(height: 4),
          HighlightedText(text: messages[i].text, findings: detectCues(messages[i].text)),
          const SizedBox(height: 10),
        ],
      ],
      if (report.timeline.length > 2) ...[
        const SectionTitle('How the risk built up'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
            child: SizedBox(height: 200, child: RiskTimeline(points: report.timeline)),
          ),
        ),
      ],
      const SectionTitle('What Kantoi noticed'),
      for (final s in signals.take(10))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(s.weight > 0 ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: s.weight > 0 ? const Color(0xFFDC2626) : const Color(0xFF15803D)),
          title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${s.group} · ${s.detail}'),
        ),
      if (report.identifiers.isNotEmpty) ...[
        const SectionTitle('Their accounts, numbers and links'),
        Text('Kept as evidence for a report. Check any account number on Semak Mule before paying.', style: t.bodySmall),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final id in report.identifiers) Chip(label: SelectableText(id))]),
      ],
      if (report.log.isNotEmpty) ...[
        const SectionTitle('How Kantoi checked'),
        ActivityLog(steps: report.log),
      ],
      const SizedBox(height: 12),
      FeedbackBar(key: ObjectKey(report), relationship: report),
    ]);
  }

  static String _date(DateTime t) => '${t.day}/${t.month}/${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Line chart of the conversation's risk, message by message, with turning
/// points labelled.
class RiskTimeline extends StatelessWidget {
  final List<TimelinePoint> points;
  const RiskTimeline({super.key, required this.points});
  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _TimelinePainter(points, Theme.of(context).colorScheme, Theme.of(context).textTheme.labelSmall!),
        size: Size.infinite,
      );
}

class _TimelinePainter extends CustomPainter {
  final List<TimelinePoint> pts;
  final ColorScheme scheme;
  final TextStyle label;
  _TimelinePainter(this.pts, this.scheme, this.label);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0, bottom = 20.0, top = 8.0;
    final w = size.width - left, h = size.height - bottom - top;
    double x(int i) => left + (pts.length == 1 ? 0 : i / (pts.length - 1) * w);
    double y(int s) => top + h - s / 100 * h;
    final grid = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1;
    for (final v in [0, 40, 65, 100]) {
      canvas.drawLine(Offset(left, y(v)), Offset(size.width, y(v)), grid);
      _text(canvas, '$v', Offset(0, y(v) - 7), label.copyWith(color: scheme.outline));
    }
    // Danger band.
    canvas.drawRect(Rect.fromLTRB(left, y(100), size.width, y(65)), Paint()..color = riskColor(RiskLevel.danger).withValues(alpha: 0.06));
    final path = Path()..moveTo(x(0), y(pts.first.score));
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(x(i), y(pts[i].score));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = scheme.primary
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);
    var lastLabelX = -100.0;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      if (p.turningPoint == null) continue;
      final c = riskColor(levelFor(p.score));
      canvas.drawCircle(Offset(x(i), y(p.score)), 5, Paint()..color = c);
      if (x(i) - lastLabelX > 70) {
        _text(canvas, p.turningPoint!, Offset(x(i) + 6, y(p.score) - 18), label.copyWith(color: c, fontWeight: FontWeight.w700));
        lastLabelX = x(i);
      }
    }
    _text(canvas, 'Messages over time →', Offset(left, size.height - 14), label.copyWith(color: scheme.outline));
  }

  void _text(Canvas c, String s, Offset o, TextStyle st) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)..layout(maxWidth: 140);
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => old.pts != pts;
}

const _sampleChat = '''01/10/2026, 21:01 - Amanda: Hi, sorry is this Kevin? I think I saved the wrong number
01/10/2026, 21:05 - Me: No sorry, wrong number
01/10/2026, 21:06 - Amanda: Haha maybe it's fate then. I'm Amanda, I work in Singapore in finance
02/10/2026, 08:15 - Amanda: Good morning! Did you sleep well?
03/10/2026, 22:10 - Amanda: Good night my dear, talking to you is the best part of my day
05/10/2026, 19:30 - Me: Want to video call this weekend?
05/10/2026, 19:32 - Amanda: My camera is broken, I will fix it soon ok
06/10/2026, 20:00 - Amanda: My uncle is an analyst, he gives me tips. I made 30% profit this week on a crypto trading platform
06/10/2026, 20:02 - Amanda: Add me on Telegram, it's safer to talk there
08/10/2026, 19:00 - Amanda: You can start small. Just deposit RM3000 first, guaranteed returns. Don't tell your family, they won't understand
10/10/2026, 18:00 - Amanda: Your profit is RM9000 now! To withdraw your profit you need to pay the tax first, RM2000 to this account 5642 1234 5678 Maybank
''';
