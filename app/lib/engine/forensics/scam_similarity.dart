/// Scam similarity: how close a message's wording is to known scam messages
/// compared with genuine ones.
///
/// Character n-grams (3 to 5 letters inside words) with TF-IDF weights and
/// cosine similarity, against the reference messages in scam_corpus.dart.
/// Character n-grams cope with Manglish spelling, typos and mixed languages
/// ("bank in", "bankin", "bank-in" share most of their n-grams), which
/// fixed keyword rules miss. Runs on the device in a few milliseconds.
///
/// It only counts when the message is clearly closer to a scam than to any
/// genuine message, so everyday texts that mention money or codes stay
/// quiet. The thresholds were set on test/data/labelled_messages.csv and
/// holdout_messages.csv (tool/sim_calibrate.py): no genuine message there
/// passes them.
library;

import 'dart:math' as math;

import '../models.dart';
import 'scam_corpus.dart';

/// The nearest scam must be at least this similar...
const simMinScam = 0.25;

/// ...and this much closer than the nearest genuine message.
const simMinMargin = 0.15;

final _url = RegExp(
    r'(https?://\S+|www\.\S+|\b[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|my|net|org|xyz|top|info|link|site|online|shop|club|vip|cc|io|co|me|app|live|store|icu|buzz|life|fun|asia|biz|click)\b\S*)');
final _digit = RegExp(r'\p{Nd}', unicode: true);
final _notWord = RegExp(r'[^\p{L}\p{N}\p{M}\s]', unicode: true);
final _space = RegExp(r'\s+', unicode: true);

/// Lower case, links as "url", digits as 0, punctuation as spaces.
String simNormalise(String text) {
  var t = text.toLowerCase().replaceAll(_url, ' url ');
  t = t.replaceAll(_digit, '0').replaceAll(_notWord, ' ');
  return t.trim().split(_space).where((w) => w.isNotEmpty).join(' ');
}

Map<String, int> _grams(String text) {
  final out = <String, int>{};
  final norm = simNormalise(text);
  if (norm.isEmpty) return out;
  for (final w in norm.split(' ')) {
    final p = [32, ...w.runes, 32];
    for (var n = 3; n <= 5; n++) {
      if (p.length < n) continue;
      for (var i = 0; i + n <= p.length; i++) {
        final g = String.fromCharCodes(p, i, i + n);
        out[g] = (out[g] ?? 0) + 1;
      }
    }
  }
  return out;
}

class _Index {
  final Map<String, int> df;
  final int n;
  final List<Map<String, double>> scams;
  final List<Map<String, double>> legit;
  _Index(this.df, this.n, this.scams, this.legit);

  Map<String, double> vector(Map<String, int> g) {
    final v = <String, double>{};
    var sum = 0.0;
    g.forEach((k, c) {
      final x = (1 + math.log(c)) * (math.log((1 + n) / (1 + (df[k] ?? 0))) + 1);
      v[k] = x;
      sum += x * x;
    });
    final norm = sum == 0 ? 1.0 : math.sqrt(sum);
    return v.map((k, x) => MapEntry(k, x / norm));
  }
}

_Index? _index;

_Index _build() {
  final grams = [for (final s in scamCorpus) _grams(s.$2), for (final l in legitCorpus) _grams(l)];
  final df = <String, int>{};
  for (final g in grams) {
    for (final k in g.keys) {
      df[k] = (df[k] ?? 0) + 1;
    }
  }
  final idx = _Index(df, grams.length, const [], const []);
  final vecs = grams.map(idx.vector).toList();
  return _Index(df, grams.length, vecs.sublist(0, scamCorpus.length), vecs.sublist(scamCorpus.length));
}

double _cos(Map<String, double> a, Map<String, double> b) {
  if (a.length > b.length) return _cos(b, a);
  var s = 0.0;
  a.forEach((k, x) {
    final y = b[k];
    if (y != null) s += x * y;
  });
  return s;
}

int scamCorpusSize() => scamCorpus.length + legitCorpus.length;

class ScamSimilarity {
  /// Cosine similarity to the closest scam reference (0 to 1).
  final double scam;

  /// Cosine similarity to the closest genuine reference.
  final double legit;

  /// The type of the closest scam reference.
  final String scamType;
  const ScamSimilarity(this.scam, this.legit, this.scamType);

  double get margin => scam - legit;
  bool get matches => scam >= simMinScam && margin >= simMinMargin;

  /// 8 at the threshold, up to 22 for a near copy of a known scam.
  int get weight => 8 + (14 * ((margin - simMinMargin) / 0.30).clamp(0.0, 1.0)).round();
}

ScamSimilarity scamSimilarity(String text) {
  final idx = _index ??= _build();
  final q = idx.vector(_grams(text));
  if (q.isEmpty) return const ScamSimilarity(0, 0, '');
  var best = 0.0, bestAt = 0;
  for (var i = 0; i < idx.scams.length; i++) {
    final c = _cos(q, idx.scams[i]);
    if (c > best) {
      best = c;
      bestAt = i;
    }
  }
  var legit = 0.0;
  for (final v in idx.legit) {
    legit = math.max(legit, _cos(q, v));
  }
  return ScamSimilarity(best, legit, scamCorpus[bestAt].$1);
}

/// A finding when the wording is much closer to known scams than to
/// genuine messages.
Finding? scamSimilarityFinding(String text) {
  final s = scamSimilarity(text);
  if (!s.matches) return null;
  final pct = (s.scam * 100).round();
  final type = s.scamType.isEmpty ? 'scam' : s.scamType[0].toLowerCase() + s.scamType.substring(1);
  return Finding(
    category: CueCategory.scamPattern,
    title: 'Worded like a known $type',
    explanation: 'The wording is $pct% similar to known $type messages, and much less like genuine ones. '
        'Scammers reuse the same scripts with small changes.',
    weight: s.weight,
    tool: 'Scam similarity',
  );
}
