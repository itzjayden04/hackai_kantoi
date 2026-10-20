import 'consistency.dart';
import 'cues.dart';
import 'entities.dart';
import 'fingerprint.dart';
import 'models.dart';
import 'rhythm.dart';

/// Hook for the attribution database: given the scammer's account numbers,
/// phone numbers, wallets and profile links, returns how many earlier reports
/// mention any of them. The integrator wires this to the attribution lookup;
/// while it is null the "Linked reports" check is skipped.
Future<int> Function(List<String> identifiers)? linkedReportCounter;

class ChatMessage {
  final DateTime? time;
  final String sender;
  final String text;
  final bool fromMe;
  const ChatMessage({this.time, required this.sender, required this.text, required this.fromMe});

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        time: DateTime.tryParse(j['time'] as String? ?? ''),
        sender: j['sender'] as String? ?? '',
        text: j['text'] as String? ?? '',
        fromMe: j['fromMe'] as bool? ?? false,
      );
}

// "12/03/2026, 21:14 - Ali: hello" (Android) and "[12/03/2026, 9:14:05 PM] Ali: hello" (iOS).
final _waLine = RegExp(
    r'^\[?(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4}),?\s+(\d{1,2}):(\d{2})(?::\d{2})?\s*([APap]\.?[Mm]\.?)?\]?\s*(?:-\s*)?([^:]{1,60}):\s?(.*)$');

/// Parses a WhatsApp ".txt" export. Lines that don't start a new message are
/// joined to the previous one. [me] is the user's own display name, if known,
/// so their own messages are not scored.
List<ChatMessage> parseChatExport(String raw, {String? me}) {
  final msgs = <({DateTime? t, String s, StringBuffer b})>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final m = _waLine.firstMatch(line.replaceAll('‎', ''));
    if (m != null) {
      var d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      if (mo > 12) (d, mo) = (mo, d);
      var h = int.parse(m.group(4)!);
      final ap = m.group(6)?.toLowerCase();
      if (ap != null && ap.startsWith('p') && h < 12) h += 12;
      if (ap != null && ap.startsWith('a') && h == 12) h = 0;
      DateTime? t;
      try {
        t = DateTime(y, mo, d, h, int.parse(m.group(5)!));
      } catch (_) {}
      msgs.add((t: t, s: m.group(7)!.trim(), b: StringBuffer(m.group(8)!)));
    } else if (msgs.isNotEmpty && line.trim().isNotEmpty) {
      msgs.last.b.write('\n$line');
    } else if (line.contains(':')) {
      final i = line.indexOf(':');
      msgs.add((t: null, s: line.substring(0, i).trim(), b: StringBuffer(line.substring(i + 1).trim())));
    }
  }
  final senders = <String, int>{};
  for (final m in msgs) {
    senders[m.s] = (senders[m.s] ?? 0) + 1;
  }
  return msgs
      .where((m) => !m.b.toString().contains('end-to-end encrypted'))
      .map((m) => ChatMessage(
            time: m.t,
            sender: m.s,
            text: m.b.toString(),
            fromMe: me != null && m.s.toLowerCase() == me.toLowerCase(),
          ))
      .toList();
}

class RelSignal {
  final String group;
  final String title;
  final String detail;
  final int weight;
  final int? messageIndex;
  const RelSignal(this.group, this.title, this.detail, this.weight, [this.messageIndex]);
  Map<String, dynamic> toJson() =>
      {'group': group, 'title': title, 'detail': detail, 'weight': weight, 'messageIndex': messageIndex};
}

class TimelinePoint {
  final int index;
  final DateTime? time;
  final int score;
  final String? turningPoint;
  const TimelinePoint(this.index, this.time, this.score, [this.turningPoint]);
  Map<String, dynamic> toJson() =>
      {'index': index, 'time': time?.toIso8601String(), 'score': score, 'turningPoint': turningPoint};
}

class RelationshipReport {
  final int score;
  final RiskLevel level;

  /// One plain line, e.g. "This chat follows the pattern of an investment
  /// scam. You have never met this person, and the first money request came
  /// 9 days after first contact."
  final String headline;
  final List<RelSignal> signals;
  final List<TimelinePoint> timeline;
  final int? daysKnown;
  final int? daysToFirstMoneyAsk;

  /// The scam pattern the chat is consistent with, or null if none.
  final String? patternType;

  /// One safe next step.
  final String nextStep;

  /// Indexes of the three or four messages that matter most.
  final List<int> keyMessages;

  /// The other person's account numbers, phone numbers, wallets and profile
  /// links, from the chat and from what the user pasted. Used for linked
  /// reports and attribution.
  final List<String> identifiers;

  /// What Kantoi did, including anything sent off the device.
  final List<LogStep> log;
  const RelationshipReport({
    required this.score,
    required this.level,
    required this.headline,
    required this.signals,
    required this.timeline,
    this.daysKnown,
    this.daysToFirstMoneyAsk,
    this.patternType,
    this.nextStep = '',
    this.keyMessages = const [],
    this.identifiers = const [],
    this.log = const [],
  });
  Map<String, dynamic> toJson() => {
        'score': score,
        'level': level.name,
        'label': riskLabel(level),
        'headline': headline,
        'signals': signals.map((s) => s.toJson()).toList(),
        'timeline': timeline.map((t) => t.toJson()).toList(),
        'daysKnown': daysKnown,
        'daysToFirstMoneyAsk': daysToFirstMoneyAsk,
        'patternType': patternType,
        'nextStep': nextStep,
        'keyMessages': keyMessages,
        'identifiers': identifiers,
        'log': log.map((s) => s.toJson()).toList(),
      };
}

/// The answer to "Has money been asked for or sent?".
enum MoneyAnswer { unknown, no, asked, sent }

const moneyLabels = {
  MoneyAnswer.no: 'No',
  MoneyAnswer.asked: 'They asked, I have not paid',
  MoneyAnswer.sent: 'Yes, I have sent money',
  MoneyAnswer.unknown: 'Not sure',
};

final _bareNumber = RegExp(r'(?<![\d+])\d[\d\s-]{6,22}\d(?!\d)');

/// Account numbers, phone numbers, wallets, emails, handles and profile links
/// in [text]. A bare run of 8 to 17 digits counts too, because people paste
/// an account number on its own.
List<String> extractIdentifiers(String text) {
  final out = <String>[];
  void add(String v) {
    final t = v.trim();
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }

  final ents = extractEntities(text);
  for (final e in ents) {
    if (e.type != EntityType.amount) add(e.value);
  }
  for (final m in _bareNumber.allMatches(text)) {
    if (ents.any((e) => m.start < e.end && m.end > e.start)) continue;
    final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8 && digits.length <= 17) add(digits);
  }
  return out;
}

/// Which messages are the other person's. If none are marked as the user's
/// and there are exactly two senders, the one who wrote first is "them".
bool Function(ChatMessage) theirMessages(List<ChatMessage> msgs) {
  final senders = msgs.map((m) => m.sender).toSet();
  final anyMine = msgs.any((m) => m.fromMe);
  final theirName = !anyMine && senders.length == 2 ? msgs.first.sender : null;
  return (m) => anyMine ? !m.fromMe : (theirName == null || m.sender == theirName);
}

RiskLevel levelFor(int score) => score >= 65
    ? RiskLevel.danger
    : score >= 40
        ? RiskLevel.suspicious
        : score >= 18
            ? RiskLevel.caution
            : RiskLevel.safe;

/// Maps an open-ended evidence total onto 0-99 so a few strong signals score
/// high but no amount of evidence claims certainty.
int squash(num raw) => (100 * (1 - 1 / (1 + raw / 35))).round().clamp(0, 99);

/// How the user first met this contact, from the questionnaire or the
/// extension's prompt.
enum Origin { unknown, inPerson, friendIntro, wrongNumber, datingApp, socialMedia, telegramGroup }

const originLabels = {
  Origin.unknown: "I'm not sure",
  Origin.inPerson: 'Met in person',
  Origin.friendIntro: 'Introduced by someone I know',
  Origin.wrongNumber: 'They messaged me out of the blue',
  Origin.datingApp: 'Dating app',
  Origin.socialMedia: 'Social media (Facebook, Instagram, TikTok)',
  Origin.telegramGroup: 'Telegram or WhatsApp group',
};

const _originWeight = {
  Origin.unknown: 0,
  Origin.inPerson: -20,
  Origin.friendIntro: -10,
  Origin.wrongNumber: 18,
  Origin.datingApp: 12,
  Origin.socialMedia: 12,
  Origin.telegramGroup: 14,
};

final _wrongNumber = RegExp(
    r"\b(wrong (number|person|chat)|salah (nombor|orang)|sorry,? (who is this|is this not)|got your (number|contact) from|added you by mistake|is this (mr|ms|miss|mrs|encik|puan)\b)",
    caseSensitive: false);

/// Scores a conversation for how closely the other person's behaviour follows
/// a scam script rather than a genuine relationship. Only the other person's
/// messages are scored.
RelationshipReport analyzeConversation(List<ChatMessage> msgs,
    {Origin origin = Origin.unknown,
    bool? metOnVideo,
    MoneyAnswer money = MoneyAnswer.unknown,
    List<String> identifiers = const [],
    List<RelSignal> extraSignals = const [],
    List<LogStep> log = const []}) {
  final signals = <RelSignal>[];
  final timeline = <TimelinePoint>[];
  var raw = 0.0;
  final seen = <CueCategory>{};

  void addSignal(RelSignal s) {
    signals.add(s);
    raw += s.weight;
  }

  // A "wrong number" opener is the classic start of a pig-butchering script,
  // so infer the origin when the user hasn't told us.
  if (origin == Origin.unknown && msgs.take(4).any((m) => !m.fromMe && _wrongNumber.hasMatch(m.text))) {
    addSignal(const RelSignal('Origin', 'Started with a "wrong number" message',
        'Many investment and romance scams open by pretending to message the wrong person.', 18));
  }
  final ow = _originWeight[origin]!;
  if (ow != 0) {
    addSignal(RelSignal('Origin', originLabels[origin]!,
        ow > 0 ? 'Most relationship scams start with a stranger reaching out online.' : 'Knowing them offline lowers the risk.', ow));
  }
  if (metOnVideo == true) {
    addSignal(const RelSignal('Origin', 'Verified on live video or in person', 'You have seen them for real.', -15));
  } else if (metOnVideo == false) {
    addSignal(const RelSignal('Origin', 'Never seen on live video', 'You have never verified who they are.', 10));
  }

  final first = msgs.where((m) => m.time != null).map((m) => m.time!).fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
  final last = msgs.where((m) => m.time != null).map((m) => m.time!).fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
  final daysKnown = first != null && last != null ? last.difference(first).inDays : null;
  int? daysToMoney;

  // If no message is marked as the user's, treat the sender who wrote first as
  // the other party only when there are exactly two senders.
  final isTheirs = theirMessages(msgs);

  const groupFor = {
    CueCategory.romance: 'Escalation',
    CueCategory.investment: 'Script',
    CueCategory.payment: 'Money',
    CueCategory.secrecy: 'Control',
    CueCategory.channelSwitch: 'Control',
    CueCategory.urgency: 'Control',
    CueCategory.fear: 'Control',
    CueCategory.credentials: 'Money',
    CueCategory.impersonation: 'Script',
    CueCategory.reward: 'Script',
    CueCategory.authority: 'Script',
    CueCategory.aiManipulation: 'Script',
  };

  for (var i = 0; i < msgs.length; i++) {
    final m = msgs[i];
    String? turning;
    if (isTheirs(m)) {
      final cues = detectCues(m.text).where((f) => f.isRisk);
      for (final c in cues) {
        if (seen.add(c.category)) {
          final g = groupFor[c.category] ?? 'Script';
          addSignal(RelSignal(g, c.title, '"${m.text.substring(c.start ?? 0, c.end ?? 0)}": ${c.explanation}', c.weight, i));
          if (c.category == CueCategory.payment || c.category == CueCategory.credentials) {
            turning ??= 'First money request';
            if (first != null && m.time != null && daysToMoney == null) {
              daysToMoney = m.time!.difference(first).inDays;
            }
          } else if (c.category == CueCategory.romance) {
            turning ??= 'Affection escalates';
          } else if (c.category == CueCategory.investment) {
            turning ??= 'Investment or job pitch';
          } else if (c.category == CueCategory.channelSwitch) {
            turning ??= 'Asks to move apps';
          } else if (c.category == CueCategory.secrecy) {
            turning ??= 'Asks for secrecy';
          }
        } else {
          raw += 0.5;
        }
      }
    }
    if (i == 0) turning = 'First contact';
    timeline.add(TimelinePoint(i, m.time, squash(raw.clamp(0, 999)), turning));
  }

  // What the user told us about money.
  if (money == MoneyAnswer.asked) {
    addSignal(const RelSignal('Money', 'They have asked you for money', 'You said they have asked you for money.', 10));
  } else if (money == MoneyAnswer.sent) {
    addSignal(const RelSignal('Money', 'You have already sent money',
        'You said you have already sent money. Scammers usually ask again, with a new reason each time.', 14));
  }

  // Texting rhythm, story consistency and (for long histories) the
  // person's own writing style. All on the device.
  for (final s in rhythmSignals(textingRhythm(msgs, isTheirs))) {
    addSignal(s);
  }
  final local = findContradictions(msgs, isTheirs).map((c) => c.toSignal()).toList();
  for (final s in local) {
    addSignal(s);
  }
  final known = knownContactSignals(msgs, isTheirs);
  for (final s in known) {
    addSignal(s);
  }
  for (final s in extraSignals) {
    // Skip an AI contradiction the on-device check already found.
    if (s.group == 'Consistency' && local.any((l) => l.title == s.title)) continue;
    addSignal(s);
  }
  final hijack = known.any((s) => s.weight >= 20);

  // Combinations that matter more than their parts.
  if (seen.contains(CueCategory.romance) && (seen.contains(CueCategory.investment) || seen.contains(CueCategory.payment))) {
    addSignal(const RelSignal('Script', 'Romance leading to money',
        'Affection followed by an investment tip or money request is the pattern of "pig-butchering" love and investment scams.', 18));
  }
  if (daysToMoney != null && daysToMoney <= 30 && !hijack) {
    addSignal(RelSignal('Timeline', 'Money came up fast',
        'The first money-related request came $daysToMoney day(s) after you started talking.', 12));
  } else if (daysKnown != null && daysKnown > 365 && !seen.contains(CueCategory.payment)) {
    addSignal(RelSignal('Timeline', 'Long, ordinary history', 'You have talked for $daysKnown days with no money requests.', -12));
  }

  final score = squash(raw.clamp(0, 999));
  final level = levelFor(score);
  if (timeline.isNotEmpty) {
    final lastPoint = timeline.removeLast();
    timeline.add(TimelinePoint(lastPoint.index, lastPoint.time, score, lastPoint.turningPoint));
  }
  final job = signals.any((s) => s.title == 'Easy-money job offer');
  final String? pattern;
  if (level.index < RiskLevel.caution.index) {
    pattern = null;
  } else if (hijack) {
    pattern = 'a hijacked or cloned account';
  } else if (seen.contains(CueCategory.romance) && seen.contains(CueCategory.investment)) {
    pattern = 'a love and investment scam';
  } else if (job) {
    pattern = 'a job scam';
  } else if (seen.contains(CueCategory.investment)) {
    pattern = 'an investment scam';
  } else if (seen.contains(CueCategory.romance)) {
    pattern = 'a love scam';
  } else if (seen.contains(CueCategory.payment) || seen.contains(CueCategory.credentials)) {
    pattern = 'a money scam';
  } else {
    pattern = null;
  }
  final allIds = <String>[...identifiers];
  for (final m in msgs.where(isTheirs)) {
    for (final id in extractIdentifiers(m.text)) {
      if (!allIds.contains(id)) allIds.add(id);
    }
  }
  final keys = <int>[];
  for (final s in [...signals]..sort((a, b) => b.weight.compareTo(a.weight))) {
    if (s.weight > 0 && s.messageIndex != null && !keys.contains(s.messageIndex)) keys.add(s.messageIndex!);
    if (keys.length == 4) break;
  }
  keys.sort();
  return RelationshipReport(
    score: score,
    level: level,
    headline: relationshipHeadline(level, pattern, metOnVideo, daysToMoney),
    signals: signals,
    timeline: timeline,
    daysKnown: daysKnown,
    daysToFirstMoneyAsk: daysToMoney,
    patternType: pattern,
    nextStep: relationshipNextStep(level, hijack: hijack, paid: money == MoneyAnswer.sent),
    keyMessages: keys,
    identifiers: allIds.take(20).toList(),
    log: log,
  );
}

/// The one line the user sees first.
String relationshipHeadline(RiskLevel level, String? pattern, bool? metOnVideo, int? daysToMoney) {
  if (level == RiskLevel.safe) return 'No scam pattern found in this conversation.';
  final first = pattern == null
      ? (level == RiskLevel.caution
          ? 'A few things to watch, but no clear scam pattern yet.'
          : 'This chat has several warning signs of a scam script.')
      : level == RiskLevel.caution
          ? 'This chat shows early signs of $pattern.'
          : 'This chat follows the pattern of $pattern.';
  final facts = <String>[
    if (metOnVideo == false) 'You have never met this person',
    if (metOnVideo == true) 'You have met this person',
    if (daysToMoney != null)
      daysToMoney == 0
          ? 'the first money request came on the first day'
          : 'the first money request came $daysToMoney day${daysToMoney == 1 ? '' : 's'} after first contact',
  ];
  if (facts.isEmpty) return first;
  final joined = facts.length == 2 ? '${facts[0]}, and ${facts[1]}' : facts.first;
  return '$first ${joined[0].toUpperCase()}${joined.substring(1)}.';
}

/// One safe next step for the result card.
String relationshipNextStep(RiskLevel level, {bool hijack = false, bool paid = false}) {
  if (hijack) {
    return 'Call them on a number you already know, not this chat. Do not send money until you have spoken to them. '
        'If you have paid, press the red button.';
  }
  return switch (level) {
    RiskLevel.danger || RiskLevel.suspicious =>
      'Ask for a live video call. Do not send ${paid ? 'more' : 'any'} money. If you have paid, press the red button.',
    RiskLevel.caution => 'Ask for a live video call before you trust them with money or personal details.',
    RiskLevel.safe => 'No action needed. Check again if they ever ask for money.',
  };
}

class Question {
  final String id;
  final String text;
  final List<(String, int)> options;
  const Question(this.id, this.text, this.options);
}

/// The short questionnaire for people who cannot export a chat.
const questionnaire = <Question>[
  Question('origin', 'How did you first meet this person?', [
    ('In person', -20),
    ('Introduced by someone I know', -10),
    ('They messaged me out of the blue', 18),
    ('Dating app', 12),
    ('Social media', 12),
    ('Telegram or WhatsApp group', 14),
  ]),
  Question('age', 'How long ago did you first talk?', [
    ('Less than a week', 10),
    ('1 to 4 weeks', 8),
    ('1 to 6 months', 4),
    ('More than 6 months', -4),
  ]),
  Question('seen', 'Have you met in person or on a live video call?', [
    ('Yes', -15),
    ('No, but they say they will soon', 10),
    ('No, they always have an excuse', 18),
  ]),
  Question('story', 'Has their story changed (job, location, why they cannot meet)?', [
    ('No', 0),
    ('A little', 6),
    ('Yes, it does not add up', 14),
  ]),
  Question('secret', 'Have they asked you to keep things secret or move to another app?', [
    ('No', 0),
    ('Moved to another app', 8),
    ('Asked me to keep it secret', 14),
  ]),
  Question('pitch', 'Have they talked about investments, crypto or an easy-money job?', [
    ('No', 0),
    ('Yes, they mentioned it', 12),
    ('Yes, they showed me their profits', 18),
  ]),
  Question('money', 'Have they asked you for money or a fee?', [
    ('No', 0),
    ('Yes, for an emergency or gift', 16),
    ('Yes, to invest or unlock my earnings', 22),
  ]),
  Question('route', 'Where were you asked to pay?', [
    ('Not asked to pay', 0),
    ('Their own bank account', 6),
    ("Someone else's account or a company I don't know", 16),
    ('Crypto or gift cards', 18),
  ]),
  Question('feel', 'How do you feel when you say no or hesitate?', [
    ('Fine', 0),
    ('Rushed', 8),
    ('Guilty or afraid', 12),
  ]),
];

RelationshipReport scoreQuestionnaire(Map<String, int> answers,
    {List<String> identifiers = const [], List<RelSignal> extraSignals = const [], List<LogStep> log = const []}) {
  final signals = <RelSignal>[];
  var raw = 0;
  for (final q in questionnaire) {
    final a = answers[q.id];
    if (a == null) continue;
    final (label, w) = q.options[a];
    raw += w;
    if (w != 0) signals.add(RelSignal('Your answers', q.text, label, w));
  }
  for (final s in extraSignals) {
    raw += s.weight;
    signals.add(s);
  }
  final score = squash(raw.clamp(0, 999));
  final level = levelFor(score);
  final pitch = (answers['pitch'] ?? 0) > 0, dating = (answers['origin'] ?? 0) == 3;
  final String? pattern;
  if (level.index < RiskLevel.caution.index) {
    pattern = null;
  } else if (dating && pitch) {
    pattern = 'a love and investment scam';
  } else if (pitch) {
    pattern = 'an investment scam';
  } else if ((answers['money'] ?? 0) > 0) {
    pattern = 'a money scam';
  } else {
    pattern = null;
  }
  final seen = answers['seen'];
  final first = relationshipHeadline(level, pattern, seen == null ? null : seen == 0, null);
  return RelationshipReport(
    score: score,
    level: level,
    headline: '$first Based on your answers only, so a chat export would give a more certain result.',
    signals: signals,
    timeline: const [],
    patternType: pattern,
    nextStep: relationshipNextStep(level, paid: (answers['route'] ?? 0) > 0),
    identifiers: identifiers,
    log: log,
  );
}
