import '../cues.dart';
import '../models.dart';
import '../url_analyzer.dart' show StepLogger;
import 'homoglyphs.dart';
import 'mixed_language.dart';
import 'scam_scripts.dart';

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
  final plain = unmaskText(text);
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
        start: f.start,
        end: f.end,
        tool: 'Obfuscation check',
      ));
      revealed++;
    }
  }
  final words = findDisguisedWords(text);
  ob
    ..result = words.isEmpty
        ? 'No disguised words'
        : 'Disguised: ${words.take(3).map((w) => '"${w.raw}" reads "${w.reads}"').join(', ')}'
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

  return TextForensics(out, stage?.$1, scan.languages);
}
