/// Measures Kantoi's built-in engine on a labelled set of messages, with the
/// network and AI switched off, so results are repeatable on any machine.
library;

import 'investigator.dart';
import 'llm.dart';
import 'models.dart';

class LabelledMessage {
  final bool scam;
  final String text;
  final String lang;
  final String type;
  const LabelledMessage(this.scam, this.text, {this.lang = '', this.type = ''});
}

/// Splits CSV into rows, handling quoted fields with commas, quotes and
/// line breaks.
List<List<String>> parseCsv(String csv) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < csv.length; i++) {
    final c = csv[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < csv.length && csv[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < csv.length && csv[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  row.add(field.toString());
  if (row.any((f) => f.isNotEmpty)) rows.add(row);
  return rows;
}

/// Kantoi's own format: a header row "label,lang,type,text", where label is
/// "scam" or "legit".
List<LabelledMessage> parseLabelledCsv(String csv) {
  final rows = parseCsv(csv);
  if (rows.isEmpty) return const [];
  final head = rows.first.map((h) => h.trim().toLowerCase()).toList();
  final li = head.indexOf('label'), ti = head.indexOf('text'), gi = head.indexOf('lang'), yi = head.indexOf('type');
  if (li < 0 || ti < 0) throw const FormatException('CSV needs "label" and "text" columns');
  return [
    for (final r in rows.skip(1))
      if (r.length > ti && r.length > li)
        LabelledMessage(
          const {'scam', 'spam', '1', 'true'}.contains(r[li].trim().toLowerCase()),
          r[ti],
          lang: gi >= 0 && r.length > gi ? r[gi] : '',
          type: yi >= 0 && r.length > yi ? r[yi] : '',
        ),
  ];
}

/// The UCI SMS Spam Collection format: one message per line, "ham" or
/// "spam", a tab, then the text.
List<LabelledMessage> parseUciSms(String tsv) => [
      for (final line in tsv.split(RegExp(r'\r?\n')))
        if (line.contains('\t'))
          LabelledMessage(line.substring(0, line.indexOf('\t')).trim().toLowerCase() == 'spam',
              line.substring(line.indexOf('\t') + 1), lang: 'en', type: 'uci'),
    ];

class ThresholdResult {
  final int threshold;
  final int tp, fp, tn, fn;
  const ThresholdResult(this.threshold, this.tp, this.fp, this.tn, this.fn);
  double get precision => tp + fp == 0 ? 0 : tp / (tp + fp);
  double get recall => tp + fn == 0 ? 0 : tp / (tp + fn);
  double get f1 => precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall);
  double get accuracy => (tp + tn) / (tp + fp + tn + fn);
}

class ScoredMessage {
  final LabelledMessage message;
  final int score;
  final RiskLevel level;
  const ScoredMessage(this.message, this.score, this.level);
}

class EvaluationResult {
  final List<ScoredMessage> scored;
  final List<ThresholdResult> thresholds;
  const EvaluationResult(this.scored, this.thresholds);

  ThresholdResult at(int t) => thresholds.firstWhere((r) => r.threshold == t);

  /// Plain-text table for the console and docs.
  String format({int showErrorsAt = 40}) {
    String pct(double x) => '${(x * 100).toStringAsFixed(1)}%';
    final scams = scored.where((s) => s.message.scam).length;
    final b = StringBuffer()
      ..writeln('Messages: ${scored.length} ($scams scam, ${scored.length - scams} genuine)')
      ..writeln()
      ..writeln('Threshold | Precision | Recall | F1     | Accuracy | TP  FP  TN  FN')
      ..writeln('----------|-----------|--------|--------|----------|----------------');
    for (final r in thresholds) {
      b.writeln('${'>= ${r.threshold}'.padRight(9)} | ${pct(r.precision).padRight(9)} | ${pct(r.recall).padRight(6)} | '
          '${pct(r.f1).padRight(6)} | ${pct(r.accuracy).padRight(8)} | '
          '${'${r.tp}'.padRight(3)} ${'${r.fp}'.padRight(3)} ${'${r.tn}'.padRight(3)} ${r.fn}');
    }
    final r = at(showErrorsAt);
    b
      ..writeln()
      ..writeln('Confusion matrix at score >= $showErrorsAt:')
      ..writeln('                 Predicted scam | Predicted genuine')
      ..writeln('Actual scam      ${'${r.tp}'.padRight(14)} | ${r.fn}')
      ..writeln('Actual genuine   ${'${r.fp}'.padRight(14)} | ${r.tn}');
    final misses = scored.where((s) => s.message.scam && s.score < showErrorsAt).toList();
    final fps = scored.where((s) => !s.message.scam && s.score >= showErrorsAt).toList();
    if (misses.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Missed scams at >= $showErrorsAt:');
      for (final m in misses) {
        b.writeln('  [${m.score}] ${m.message.type}: ${_short(m.message.text)}');
      }
    }
    if (fps.isNotEmpty) {
      b
        ..writeln()
        ..writeln('False alarms at >= $showErrorsAt:');
      for (final m in fps) {
        b.writeln('  [${m.score}] ${m.message.type}: ${_short(m.message.text)}');
      }
    }
    return b.toString();
  }
}

String _short(String s) => s.length > 90 ? '${s.substring(0, 90)}...' : s;

/// The verdict thresholds Kantoi uses (caution 18, suspicious 40, danger 65)
/// plus a few in between.
const defaultThresholds = [10, 18, 30, 40, 50, 65];

Future<EvaluationResult> evaluate(List<LabelledMessage> data, {List<int> thresholds = defaultThresholds}) async {
  const offline = InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false);
  final scored = <ScoredMessage>[];
  for (final m in data) {
    final inv = await investigate(m.text, options: offline);
    scored.add(ScoredMessage(m, inv.verdict.score, inv.verdict.level));
  }
  final results = <ThresholdResult>[];
  for (final t in thresholds) {
    var tp = 0, fp = 0, tn = 0, fn = 0;
    for (final s in scored) {
      final flagged = s.score >= t;
      if (s.message.scam && flagged) tp++;
      if (s.message.scam && !flagged) fn++;
      if (!s.message.scam && flagged) fp++;
      if (!s.message.scam && !flagged) tn++;
    }
    results.add(ThresholdResult(t, tp, fp, tn, fn));
  }
  return EvaluationResult(scored, results);
}
