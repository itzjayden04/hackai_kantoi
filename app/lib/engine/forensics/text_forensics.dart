import '../cues.dart';
import '../models.dart';
import '../url_analyzer.dart' show StepLogger;
import 'homoglyphs.dart';
import 'mixed_language.dart';
import 'scam_scripts.dart';
import 'scam_similarity.dart';

final _spaced = RegExp(r'(?<!\p{L})(?:\p{L}[ .\-_*]){2,}\p{L}(?!\p{L})', unicode: true);
final _sep = RegExp(r'[ .\-_*]');

/// Words that matter when written letter by letter ("O T P", "b.a.n.k").
const _spacedKeywords = {
  'otp', 'tac', 'pin', 'kod', 'code', 'password', 'login', 'verify', 'bank', 'akaun', 'account', 'transfer', 'deposit',
  'bayar', 'pay', 'usdt', 'crypto', 'bitcoin', 'telegram', 'whatsapp', 'tng', 'maybank', 'cimb', 'rhb', 'ambank', 'bsn',
  'publicbank', 'hongleong', 'lhdn', 'pdrm', 'polis', 'police', 'gaji', 'komisen', 'commission', 'hadiah', 'prize', 'claim',
};

/// Joins words written letter by letter: "O T P" becomes "OTP".
String collapseSpacedLetters(String text) => text.replaceAllMapped(_spaced, (m) => m[0]!.replaceAll(_sep, ''));

/// (as written, what it reads) for each spaced-out keyword.
List<(String, String)> spacedWords(String text) => [
      for (final m in _spaced.allMatches(text))
        if (_spacedKeywords.contains(m[0]!.replaceAll(_sep, '').toLowerCase())) (m[0]!, m[0]!.replaceAll(_sep, '').toLowerCase()),
    ];

List<Finding> spacedLetterFindings(String text) {
  final out = <Finding>[];
  final seen = <String>{};
  for (final m in _spaced.allMatches(text)) {
    final w = m[0]!.replaceAll(_sep, '').toLowerCase();
    if (!_spacedKeywords.contains(w) || !seen.add(w)) continue;
    out.add(Finding(
      category: CueCategory.obfuscation,
      title: 'Spaced-out letters',
      explanation: '"${m[0]}" is written letter by letter to read as "$w", a trick to slip past spam filters.',
      weight: 8,
      start: m.start,
      end: m.end,
      tool: 'Obfuscation check',
    ));
  }
  return out;
}

class TextForensics {
  final List<Finding> findings;
  final ScriptProgress? script;
  final List<String> languages;
  const TextForensics(this.findings, this.script, this.languages);
}

/// The text path of the forensic analysis, all on the device: disguised
/// spelling, mixed languages and scam-script stage. [existing] are the
/// findings of the main cue rules.
TextForensics analyzeText(String text, {required List<Finding> existing, required StepLogger log}) {
  final out = <Finding>[];

  // 1. Look-alike letters and number swaps, then re-read the text undisguised.
  final ob = log('Obfuscation check', 'Looking for look-alike letters and number swaps');
  out.addAll(disguisedWordFindings(text));
  out.addAll(spacedLetterFindings(text));
  final plain = collapseSpacedLetters(unmaskText(text));
  // Positions only carry over when undoing the disguise kept the length.
  final sameLength = plain.length == text.length;
  var revealed = 0;
  if (plain != text) {
    for (final f in detectCues(plain)) {
      if (!f.isRisk) continue;
      final dup = [...existing, ...out].any((e) => e.title == f.title);
      if (dup) continue;
      out.add(Finding(
        category: f.category,
        title: f.title,
        explanation: '${f.explanation} (Found after undoing the disguised spelling.)',
        weight: f.weight,
        start: sameLength ? f.start : null,
        end: sameLength ? f.end : null,
        tool: 'Obfuscation check',
      ));
      revealed++;
    }
  }
  final words = [...findDisguisedWords(text).map((w) => (w.raw, w.reads)), ...spacedWords(text)];
  ob
    ..result = words.isEmpty
        ? 'No disguised words'
        : 'Disguised: ${words.take(3).map((w) => '"${w.$1}" reads "${w.$2}"').join(', ')}'
            '${revealed > 0 ? '; $revealed more warning sign(s) after undoing it' : ''}'
    ..status = StepStatus.done;

  // 2. Mixed languages.
  final lang = log('Mixed-language reader', 'Reading English, Malay, Chinese and Tamil phrasing');
  final scan = scanLanguages(text, existing: [...existing, ...out]);
  out.addAll(scan.findings);
  lang
    ..result = '${scan.languages.isEmpty ? 'No words recognised' : scan.languages.join(' + ')}'
        '${scan.findings.isEmpty ? '' : '; ${scan.findings.length} extra warning sign(s)'}'
    ..status = StepStatus.done;

  // 3. Which step of a known scam script this is.
  final sc = log('Scam script recogniser', 'Comparing with job task, investment, love, parcel and fake officer scripts');
  final stage = detectScriptStage(plain);
  if (stage != null) out.add(stage.$2);
  sc
    ..result = stage == null
        ? 'Does not follow a known scam script'
        : 'Step ${stage.$1.stage + 1} of ${stage.$1.stages.length} of a ${stage.$1.script}: ${stage.$1.stages[stage.$1.stage]}'
    ..status = StepStatus.done;

  // 4. How close the wording is to known scams (on the undisguised text).
  final simStep = log('Scam similarity', 'Comparing the wording with ${scamCorpusSize()} known scam and genuine messages');
  final sim = scamSimilarity(plain);
  final simFinding = scamSimilarityFinding(plain);
  if (simFinding != null) out.add(simFinding);
  simStep
    ..result = simFinding != null
        ? '${(sim.scam * 100).round()}% like a ${sim.scamType.toLowerCase()} (genuine: ${(sim.legit * 100).round()}%)'
        : 'Not close to known scam wording (scam ${(sim.scam * 100).round()}%, genuine ${(sim.legit * 100).round()}%)'
    ..status = StepStatus.done;

  return TextForensics(out, stage?.$1, scan.languages);
}
