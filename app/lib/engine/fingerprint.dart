/// Language fingerprint for known contacts: compares how someone writes now
/// with how they have always written, to spot a hijacked or cloned account.
library;

import 'cues.dart';
import 'models.dart';
import 'relationship.dart';

class StyleProfile {
  final int messages;
  final double avgLength;
  final double emojiPerMessage;
  final double malayShare; // of Malay + English words
  final double chineseShare; // of all letters
  final Map<String, int> greetings;
  final double exclaimPerMessage;
  final double lowercaseStartShare;
  final double fullStopEndShare;
  const StyleProfile({
    required this.messages,
    required this.avgLength,
    required this.emojiPerMessage,
    required this.malayShare,
    required this.chineseShare,
    required this.greetings,
    required this.exclaimPerMessage,
    required this.lowercaseStartShare,
    required this.fullStopEndShare,
  });
}

const _malay = {
  'saya', 'aku', 'awak', 'kau', 'tak', 'nak', 'dah', 'lah', 'boleh', 'dengan', 'untuk', 'ini', 'itu', 'apa', 'mana',
  'sudah', 'belum', 'ada', 'jom', 'makan', 'kat', 'sini', 'sana', 'je', 'kita', 'kami', 'dia', 'tu', 'ni', 'pun',
  'tapi', 'sebab', 'macam', 'nanti', 'balik', 'rumah', 'esok', 'semalam', 'terima', 'kasih', 'tolong', 'baik', 'ya',
  'tidak', 'mak', 'abah', 'adik', 'kakak', 'abang', 'duit', 'kerja', 'pergi', 'datang', 'sikit', 'banyak', 'lagi',
};
const _english = {
  'the', 'you', 'i', 'is', 'are', 'and', 'to', 'of', 'have', 'what', 'my', 'your', 'this', 'that', 'will', 'can', 'it',
  'for', 'with', 'not', 'do', 'be', 'me', 'we', 'was', 'please', 'need', 'now', 'just', 'how', 'when', 'if', 'so',
  'today', 'tomorrow', 'money', 'send', 'help', 'thanks', 'thank', 'okay', 'know', 'want', 'go', 'come',
};
const _greetingWords = {
  'hi', 'hello', 'hey', 'helo', 'hai', 'salam', 'assalamualaikum', 'morning', 'gm', 'yo', 'oi', 'weh', 'woi', 'bro',
  'sis', 'dear', 'darling', 'babe', 'sayang', 'mum', 'mom', 'ma', 'mak', 'dad', 'abah', 'kak', 'abang', 'bang', 'boss',
  'dude', 'eh',
};

bool _isEmoji(int r) =>
    (r >= 0x1F300 && r <= 0x1FAFF) || (r >= 0x2600 && r <= 0x27BF) || (r >= 0x1F000 && r <= 0x1F2FF);

StyleProfile profileOf(List<String> texts) {
  if (texts.isEmpty) {
    return const StyleProfile(
        messages: 0, avgLength: 0, emojiPerMessage: 0, malayShare: 0, chineseShare: 0, greetings: {},
        exclaimPerMessage: 0, lowercaseStartShare: 0, fullStopEndShare: 0);
  }
  var len = 0, emoji = 0, malay = 0, english = 0, cjk = 0, letters = 0, exclaim = 0, lower = 0, stop = 0, startable = 0;
  final greet = <String, int>{};
  for (final t in texts) {
    len += t.length;
    for (final r in t.runes) {
      if (_isEmoji(r)) emoji++;
      if (r >= 0x4E00 && r <= 0x9FFF) cjk++;
      if (r >= 0x4E00 && r <= 0x9FFF || (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) letters++;
      if (r == 0x21) exclaim++;
    }
    final words = RegExp(r"[a-zA-Z']+").allMatches(t.toLowerCase()).map((m) => m.group(0)!).toList();
    for (final w in words) {
      if (_malay.contains(w)) malay++;
      if (_english.contains(w)) english++;
    }
    if (words.isNotEmpty && _greetingWords.contains(words.first)) greet[words.first] = (greet[words.first] ?? 0) + 1;
    final trimmed = t.trim();
    final firstLetter = RegExp(r'[A-Za-z]').firstMatch(trimmed);
    if (firstLetter != null && firstLetter.start == 0) {
      startable++;
      if (trimmed[0] == trimmed[0].toLowerCase()) lower++;
    }
    if (trimmed.endsWith('.')) stop++;
  }
  final n = texts.length;
  return StyleProfile(
    messages: n,
    avgLength: len / n,
    emojiPerMessage: emoji / n,
    malayShare: malay + english == 0 ? 0 : malay / (malay + english),
    chineseShare: letters == 0 ? 0 : cjk / letters,
    greetings: greet,
    exclaimPerMessage: exclaim / n,
    lowercaseStartShare: startable == 0 ? 0 : lower / startable,
    fullStopEndShare: stop / n,
  );
}

/// The plain-English differences between the usual style and the recent one.
List<String> styleChanges(StyleProfile base, StyleProfile recent) {
  final out = <String>[];
  if (base.messages == 0 || recent.messages == 0) return out;
  final ratio = base.avgLength == 0 ? 1 : recent.avgLength / base.avgLength;
  if ((ratio >= 2.2 || ratio <= 0.45) && (recent.avgLength - base.avgLength).abs() >= 25) {
    out.add(ratio > 1 ? 'Messages are much longer than usual' : 'Messages are much shorter than usual');
  }
  if (base.emojiPerMessage >= 0.3 && recent.emojiPerMessage <= base.emojiPerMessage * 0.15) {
    out.add('Stopped using emoji');
  } else if (base.emojiPerMessage < 0.05 && recent.emojiPerMessage >= 0.5) {
    out.add('Suddenly uses lots of emoji');
  }
  if ((recent.malayShare - base.malayShare).abs() >= 0.35) {
    out.add(recent.malayShare > base.malayShare ? 'Switched to Malay from their usual English' : 'Switched to English from their usual Malay');
  }
  if ((recent.chineseShare - base.chineseShare).abs() >= 0.3) out.add('Changed how much Chinese they write');
  final baseGreetCount = base.greetings.values.fold<int>(0, (a, b) => a + b);
  final newGreets = recent.greetings.keys.where((g) => !base.greetings.containsKey(g)).toList();
  if (baseGreetCount >= 3 && newGreets.isNotEmpty) {
    final usual = (base.greetings.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    out.add('Greets you with "${newGreets.first}" instead of the usual "$usual"');
  }
  if ((recent.lowercaseStartShare - base.lowercaseStartShare).abs() >= 0.5 ||
      (recent.fullStopEndShare - base.fullStopEndShare).abs() >= 0.5) {
    out.add('Uses capitals and full stops differently');
  }
  if ((recent.exclaimPerMessage - base.exclaimPerMessage).abs() >= 1.0) out.add('Uses exclamation marks differently');
  return out;
}

/// Known-contact mode. Runs only when there is a long history with this
/// person: at least 30 of their messages over at least 30 days.
List<RelSignal> knownContactSignals(List<ChatMessage> msgs, bool Function(ChatMessage) isTheirs) {
  final theirs = [for (var i = 0; i < msgs.length; i++) if (isTheirs(msgs[i])) i];
  final timed = theirs.where((i) => msgs[i].time != null).toList();
  if (timed.length < 30) return const [];
  final first = msgs[timed.first].time!, last = msgs[timed.last].time!;
  if (last.difference(first).inDays < 30) return const [];

  // Recent = their messages from the last 3 days of the chat, at least 3
  // and at most a third of their messages.
  final cutoff = last.subtract(const Duration(days: 3));
  var recent = timed.where((i) => msgs[i].time!.isAfter(cutoff)).toList();
  if (recent.length < 3) recent = timed.sublist(timed.length - 3);
  if (recent.length > timed.length ~/ 3) recent = recent.sublist(recent.length - timed.length ~/ 3);
  final base = timed.where((i) => i < recent.first).toList();
  if (base.length < 20) return const [];

  final changes = styleChanges(profileOf([for (final i in base) msgs[i].text]), profileOf([for (final i in recent) msgs[i].text]));
  final moneyAsk = <int>[];
  var pressure = false;
  for (final i in recent) {
    final cats = detectCues(msgs[i].text).where((f) => f.isRisk).map((f) => f.category).toSet();
    if (cats.contains(CueCategory.payment) || cats.contains(CueCategory.credentials)) moneyAsk.add(i);
    if (cats.contains(CueCategory.urgency) || cats.contains(CueCategory.secrecy) || cats.contains(CueCategory.impersonation)) {
      pressure = true;
    }
  }
  final days = last.difference(first).inDays;
  if (changes.length >= 2 && moneyAsk.isNotEmpty) {
    return [
      RelSignal(
          'Known contact',
          'Sudden change in writing style, then a money request',
          'Compared with $days days of their usual messages: ${changes.join('; ')}. '
              '${pressure ? 'The recent messages ask for money urgently. ' : 'The recent messages ask for money. '}'
              'This is consistent with a hijacked or cloned account. Call them on a number you already know.',
          30,
          moneyAsk.first),
    ];
  }
  if (changes.length >= 2) {
    return [
      RelSignal('Known contact', 'Writing style changed recently',
          'Compared with their usual messages: ${changes.join('; ')}. Keep an eye out if money comes up.', 4, recent.first),
    ];
  }
  return [
    RelSignal('Known contact', 'Writes like they always have',
        'Their recent messages match $days days of their usual writing style.', -4),
  ];
}
