/// The adaptive practice coach: grades a drill, tracks skill per cue type and
/// picks the next drill so missed cues come back.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../engine/models.dart';
import 'drills.dart';
import 'prefs.dart';

/// A tappable word: its range in the drill's full text.
typedef Token = (int start, int end);

List<Token> tokenize(String text) => [for (final m in RegExp(r'\S+').allMatches(text)) (m.start, m.end)];

bool _overlaps(Token a, (int, int) b) => a.$1 < b.$2 && a.$2 > b.$1;

class DrillResult {
  final Drill drill;
  final bool saidScam;
  final List<DrillCue> found;
  final List<DrillCue> missed;
  final List<Token> falseTaps;
  const DrillResult(this.drill, this.saidScam, this.found, this.missed, this.falseTaps);

  bool get verdictRight => saidScam == drill.isScam;

  /// Right answer, and for a scam at least half of its signs spotted.
  bool get passed => verdictRight && (!drill.isScam || found.length * 2 >= drill.riskCues.length);
}

/// Compares the words the user tapped with the drill's tagged cues.
DrillResult grade(Drill d, Iterable<Token> tapped, {required bool saidScam}) {
  final taps = tapped.toList();
  final found = <DrillCue>[], missed = <DrillCue>[];
  for (final c in d.riskCues) {
    final s = d.span(c);
    if (s == null) continue;
    (taps.any((t) => _overlaps(t, s)) ? found : missed).add(c);
  }
  final riskSpans = d.riskCues.map(d.span).whereType<(int, int)>().toList();
  final falseTaps = taps.where((t) => !riskSpans.any((s) => _overlaps(t, s))).toList();
  return DrillResult(d, saidScam, found, missed, falseTaps);
}

class Skill {
  int hits;
  int misses;
  Skill([this.hits = 0, this.misses = 0]);
  int get seen => hits + misses;
  bool get mastered => hits >= 3 && hits >= misses * 3;
}

/// Everything the coach remembers, stored on this device only.
class Coach extends ChangeNotifier {
  static const _key = 'awareness.coach';
  final Map<CueCategory, Skill> skills = {};
  DrillLevel level = DrillLevel.obvious;
  int streak = 0;
  int bestStreak = 0;
  int done = 0;
  int passed = 0;
  final List<bool> _recent = [];
  final List<String> recentIds = [];

  /// Cue types the user missed recently; drills with them come back first.
  final List<CueCategory> review = [];
  bool _loaded = false;

  Skill skill(CueCategory c) => skills.putIfAbsent(c, Skill.new);

  /// Cue types that drills can test, in a stable order.
  static List<CueCategory> get practised =>
      CueCategory.values.where((c) => drills.any((d) => d.categories.contains(c) || (c == CueCategory.legitimacy && !d.isScam))).toList();

  int get masteredCount => practised.where((c) => skills[c]?.mastered ?? false).length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final j = await readJson(_key);
    if (j != null) fromJson(j);
    notifyListeners();
  }

  void record(DrillResult r) {
    final d = r.drill;
    done++;
    if (d.isScam) {
      for (final c in r.found) {
        skill(c.category).hits++;
      }
      for (final c in r.missed) {
        skill(c.category).misses++;
      }
      // A category counts as learned again only when every cue of it was found.
      final missedCats = r.missed.map((c) => c.category).toSet();
      review.removeWhere((c) => r.found.any((f) => f.category == c) && !missedCats.contains(c));
      for (final c in missedCats) {
        review
          ..remove(c)
          ..insert(0, c);
      }
    } else {
      // Genuine drills train the opposite skill: not over-flagging.
      final s = skill(CueCategory.legitimacy);
      if (r.verdictRight) {
        s.hits++;
        review.remove(CueCategory.legitimacy);
      } else {
        s.misses++;
        review
          ..remove(CueCategory.legitimacy)
          ..insert(0, CueCategory.legitimacy);
      }
    }
    if (review.length > 6) review.removeRange(6, review.length);

    if (r.passed) {
      passed++;
      streak++;
      if (streak > bestStreak) bestStreak = streak;
    } else {
      streak = 0;
    }
    _adjustLevel(r.passed);
    recentIds
      ..remove(d.id)
      ..insert(0, d.id);
    if (recentIds.length > 10) recentIds.removeLast();
    notifyListeners();
    writeJson(_key, toJson());
  }

  void _adjustLevel(bool ok) {
    _recent.insert(0, ok);
    if (_recent.length > 4) _recent.removeLast();
    final i = level.index;
    if (_recent.length >= 4 && _recent.every((x) => x) && i < DrillLevel.values.length - 1) {
      level = DrillLevel.values[i + 1];
      _recent.clear();
    } else if (_recent.take(3).where((x) => !x).length >= 2 && i > 0) {
      level = DrillLevel.values[i - 1];
      _recent.clear();
    }
  }

  /// How much a drill is worth showing next. Higher means more likely.
  double weight(Drill d, {Set<CueCategory> focus = const {}}) {
    final gap = (d.level.index - level.index).abs();
    var w = gap == 0 ? 4.0 : gap == 1 ? 1.0 : 0.25;
    final cats = d.isScam ? d.categories : {CueCategory.legitimacy};
    for (final c in cats) {
      final ri = review.indexOf(c);
      if (ri >= 0) w += 6.0 - ri;
      final s = skills[c];
      if (s != null) w += (s.misses - s.hits * 0.5).clamp(0, 3).toDouble();
      if (focus.contains(c)) w += 5;
    }
    return w;
  }

  Drill next({Random? random, Set<CueCategory> focus = const {}}) {
    final rnd = random ?? Random();
    var pool = drills.where((d) => !recentIds.take(8).contains(d.id)).toList();
    if (pool.isEmpty) pool = drills.toList();
    // Mix in a genuine message about one time in four so users learn not
    // to flag everything.
    final wantGenuine = focus.isEmpty && rnd.nextDouble() < 0.25;
    final genuine = pool.where((d) => !d.isScam).toList();
    if (wantGenuine && genuine.isNotEmpty) pool = genuine;
    final weights = [for (final d in pool) weight(d, focus: focus)];
    final total = weights.fold<double>(0, (a, b) => a + b);
    var roll = rnd.nextDouble() * total;
    for (var i = 0; i < pool.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return pool[i];
    }
    return pool.last;
  }

  Map<String, dynamic> toJson() => {
        'skills': {for (final e in skills.entries) e.key.name: [e.value.hits, e.value.misses]},
        'level': level.name,
        'streak': streak,
        'best': bestStreak,
        'done': done,
        'passed': passed,
        'recent': _recent,
        'recentIds': recentIds,
        'review': review.map((c) => c.name).toList(),
      };

  void fromJson(Map<String, dynamic> j) {
    CueCategory? cat(Object? n) => CueCategory.values.where((c) => c.name == n).firstOrNull;
    skills.clear();
    (j['skills'] as Map? ?? {}).forEach((k, v) {
      final c = cat(k);
      if (c != null && v is List && v.length == 2) skills[c] = Skill(v[0] as int, v[1] as int);
    });
    level = DrillLevel.values.where((l) => l.name == j['level']).firstOrNull ?? DrillLevel.obvious;
    streak = j['streak'] as int? ?? 0;
    bestStreak = j['best'] as int? ?? 0;
    done = j['done'] as int? ?? 0;
    passed = j['passed'] as int? ?? 0;
    _recent
      ..clear()
      ..addAll((j['recent'] as List? ?? []).whereType<bool>());
    recentIds
      ..clear()
      ..addAll((j['recentIds'] as List? ?? []).whereType<String>());
    review
      ..clear()
      ..addAll((j['review'] as List? ?? []).map(cat).whereType<CueCategory>());
  }

  /// For tests and "start over".
  Future<void> reset() async {
    fromJson(const {});
    notifyListeners();
    await writeJson(_key, toJson());
  }

  @override
  String toString() => jsonEncode(toJson());
}

final coach = Coach();
