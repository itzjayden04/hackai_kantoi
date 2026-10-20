/// Texting rhythm: when and how the other person writes. Scam compounds work
/// in shifts from scripts, so their messages tend to arrive at fixed hours,
/// repeat copy-pasted phrases and include long replies typed impossibly fast.
library;

import 'dart:math' as math;

import 'relationship.dart';

class RhythmStats {
  /// Their messages per hour of day (0-23).
  final List<int> hourCounts;
  final int timedMessages;
  final int activeDays;

  /// The shortest block of hours that holds 90% of their messages.
  final int windowStart;
  final int windowLength;

  /// Spread (standard deviation, in hours) of the time of their first message
  /// each day. Small means they "clock in" at the same time.
  final double? firstHourSpread;

  /// Pairs of near-identical messages (index pairs into the chat).
  final List<(int, int)> duplicatePairs;

  /// Long messages that arrived within a minute of the user's message.
  final List<int> fastLongReplies;
  const RhythmStats({
    required this.hourCounts,
    required this.timedMessages,
    required this.activeDays,
    required this.windowStart,
    required this.windowLength,
    required this.firstHourSpread,
    required this.duplicatePairs,
    required this.fastLongReplies,
  });

  bool get enoughForShifts => timedMessages >= 25 && activeDays >= 5;
  bool get looksLikeShift =>
      enoughForShifts && windowLength <= 10 && firstHourSpread != null && firstHourSpread! <= 1.0;

  Map<String, dynamic> toJson() => {
        'hourCounts': hourCounts,
        'windowStart': windowStart,
        'windowLength': windowLength,
        'firstHourSpread': firstHourSpread,
        'duplicatePairs': duplicatePairs.length,
        'fastLongReplies': fastLongReplies.length,
      };
}

/// Character 4-gram shingles of a normalised message.
Set<String> shingles(String text, [int k = 4]) {
  final t = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length < k) return {t};
  return {for (var i = 0; i <= t.length - k; i++) t.substring(i, i + k)};
}

double jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final inter = a.where(b.contains).length;
  return inter / (a.length + b.length - inter);
}

RhythmStats textingRhythm(List<ChatMessage> msgs, bool Function(ChatMessage) isTheirs) {
  final hours = List<int>.filled(24, 0);
  final firstPerDay = <String, int>{};
  var timed = 0;
  for (final m in msgs) {
    if (!isTheirs(m) || m.time == null) continue;
    final t = m.time!;
    timed++;
    hours[t.hour]++;
    final day = '${t.year}-${t.month}-${t.day}';
    final minutes = t.hour * 60 + t.minute;
    if (!firstPerDay.containsKey(day) || minutes < firstPerDay[day]!) firstPerDay[day] = minutes;
  }

  // Shortest circular block of hours holding at least 90% of the messages.
  var bestStart = 0, bestLen = 24;
  if (timed > 0) {
    final need = (timed * 0.9).ceil();
    for (var len = 1; len <= 24 && bestLen == 24; len++) {
      for (var s = 0; s < 24; s++) {
        var sum = 0;
        for (var k = 0; k < len; k++) {
          sum += hours[(s + k) % 24];
        }
        if (sum >= need) {
          bestStart = s;
          bestLen = len;
          break;
        }
      }
    }
  }

  double? spread;
  if (firstPerDay.length >= 5) {
    final v = firstPerDay.values.map((m) => m / 60).toList();
    final mean = v.reduce((a, b) => a + b) / v.length;
    spread = math.sqrt(v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / v.length);
  }

  // Near-duplicate messages: copy-pasted script lines.
  final theirs = <(int, Set<String>, String)>[];
  for (var i = 0; i < msgs.length && theirs.length < 400; i++) {
    final m = msgs[i];
    final norm = m.text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (isTheirs(m) && norm.length >= 25) theirs.add((i, shingles(norm), norm));
  }
  final dups = <(int, int)>[];
  for (var a = 0; a < theirs.length; a++) {
    for (var b = a + 1; b < theirs.length; b++) {
      if (jaccard(theirs[a].$2, theirs[b].$2) >= 0.7) dups.add((theirs[a].$1, theirs[b].$1));
    }
  }

  // Long replies that land within a minute of the user's own message.
  final fast = <int>[];
  for (var i = 1; i < msgs.length; i++) {
    final m = msgs[i], prev = msgs[i - 1];
    if (!isTheirs(m) || isTheirs(prev) || m.time == null || prev.time == null) continue;
    if (m.text.length >= 250 && m.time!.difference(prev.time!).inSeconds.abs() <= 60) fast.add(i);
  }

  return RhythmStats(
    hourCounts: hours,
    timedMessages: timed,
    activeDays: firstPerDay.length,
    windowStart: bestStart,
    windowLength: bestLen,
    firstHourSpread: spread,
    duplicatePairs: dups,
    fastLongReplies: fast,
  );
}

String _hour(int h) {
  final hh = h % 24;
  final suffix = hh < 12 ? 'am' : 'pm';
  final twelve = hh % 12 == 0 ? 12 : hh % 12;
  return '$twelve$suffix';
}

List<RelSignal> rhythmSignals(RhythmStats s) {
  final out = <RelSignal>[];
  if (s.looksLikeShift) {
    out.add(RelSignal(
        'Texting rhythm',
        'Messages arrive in fixed shifts',
        '90% of their messages arrive between ${_hour(s.windowStart)} and ${_hour(s.windowStart + s.windowLength)}, '
            'and they start at about the same time every day. Scam teams often work set shifts.',
        6));
  }
  if (s.duplicatePairs.length >= 2) {
    out.add(RelSignal(
        'Texting rhythm',
        'Copy-paste messages',
        '${s.duplicatePairs.length} pairs of their messages are almost word for word the same. Scripted chats reuse the same lines.',
        8,
        s.duplicatePairs.first.$2));
  }
  if (s.fastLongReplies.length >= 2) {
    out.add(RelSignal(
        'Texting rhythm',
        'Long replies typed too fast',
        '${s.fastLongReplies.length} long replies arrived within a minute of your message. That is faster than most people can type, which suggests a prepared script.',
        7,
        s.fastLongReplies.first));
  }
  if (out.isEmpty && s.enoughForShifts) {
    out.add(const RelSignal('Texting rhythm', 'Natural, irregular rhythm',
        'Their messages come at varied times with no copy-paste lines, like a normal person.', -4));
  }
  return out;
}
