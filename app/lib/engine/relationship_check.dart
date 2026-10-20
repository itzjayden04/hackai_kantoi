/// The full relationship check: everything in [analyzeConversation] (on the
/// device), plus the optional AI consistency check on a masked copy of the
/// other person's messages, plus linked reports from the attribution database.
library;

import 'package:http/http.dart' as http;

import 'consistency.dart';
import 'llm.dart';
import 'models.dart';
import 'redaction.dart';
import 'relationship.dart';

/// How many of their messages at most go to the AI, newest last.
const _aiMessageCap = 150;

Future<RelationshipReport> checkRelationship(
  List<ChatMessage> msgs, {
  Origin origin = Origin.unknown,
  bool? metOnVideo,
  MoneyAnswer money = MoneyAnswer.unknown,
  String pastedIdentifiers = '',
  LlmConfig llm = LlmConfig.defaults,
  Set<String> ownDetails = const {},
  http.Client? httpClient,
  void Function(List<LogStep>)? onStep,
}) async {
  final log = <LogStep>[];
  LogStep step(String tool, String action, {bool sentOffDevice = false}) {
    final s = LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice);
    log.add(s);
    onStep?.call(List.of(log));
    return s;
  }

  void done(LogStep s, String result, [StepStatus status = StepStatus.done]) {
    s
      ..result = result
      ..status = status;
    onStep?.call(List.of(log));
  }

  final isTheirs = theirMessages(msgs);
  final theirIdx = [for (var i = 0; i < msgs.length; i++) if (isTheirs(msgs[i])) i];
  done(step('Chat reader', 'Reading the chat on your device'),
      '${msgs.length} messages, ${theirIdx.length} from the other person');

  final ids = <String>[...extractIdentifiers(pastedIdentifiers)];
  for (final i in theirIdx) {
    for (final id in extractIdentifiers(msgs[i].text)) {
      if (!ids.contains(id)) ids.add(id);
    }
  }

  final extra = <RelSignal>[];

  // AI consistency check, on a masked copy of only their messages.
  if (llm.usable && theirIdx.length >= 3) {
    final used = theirIdx.length > _aiMessageCap ? theirIdx.sublist(theirIdx.length - _aiMessageCap) : theirIdx;
    final shield = step('Privacy shield', 'Masking personal details in their messages before anything is sent');
    var masked = 0;
    final lines = <String>[];
    for (final i in used) {
      final t = msgs[i].text.replaceAll('\n', ' ');
      final pii = findPii(t, ownValues: ownDetails);
      masked += pii.length;
      final r = redact(t, pii);
      lines.add(r.length > 300 ? r.substring(0, 300) : r);
    }
    done(shield, masked == 0 ? 'No personal details found' : 'Masked $masked detail(s)');
    final ai = step('AI consistency check',
        'Sending ${lines.length} of their messages (masked, not yours) to ${llm.displayName} to look for story contradictions',
        sentOffDevice: llm.leavesDevice);
    final client = LlmClient(llm, client: httpClient);
    try {
      final j = await client.completeJson(system: contradictionSystemPrompt, user: contradictionPrompt(lines));
      final found = parseContradictions(j, lines, used);
      extra.addAll(found.map((c) => c.toSignal()));
      final listed = (j['contradictions'] as List?)?.length ?? 0;
      done(ai, found.isEmpty
          ? (listed == 0 ? 'No contradictions found' : 'AI listed $listed, none quoted the chat exactly, so none kept')
          : 'Kept ${found.length} contradiction(s) with exact quotes');
    } catch (e) {
      done(ai, 'AI unavailable, using on-device checks only ($e)', StepStatus.failed);
    } finally {
      client.close();
    }
  } else {
    step('AI consistency check', llm.usable ? 'Skipped: too few messages from them' : 'Skipped: no AI service set up').status =
        StepStatus.skipped;
  }

  extra.addAll(await linkedReports(ids, step, done));

  final scoring = step('Relationship scorer', 'Checking script cues, texting rhythm, story and writing style on your device');
  final r = analyzeConversation(msgs,
      origin: origin, metOnVideo: metOnVideo, money: money, identifiers: ids, extraSignals: extra, log: log);
  done(scoring, '${r.score}/100, ${riskLabel(r.level)}');
  return r;
}

/// The questionnaire, plus linked reports for any pasted identifiers.
Future<RelationshipReport> checkQuestionnaire(Map<String, int> answers, {String pastedIdentifiers = ''}) async {
  final log = <LogStep>[];
  LogStep step(String tool, String action, {bool sentOffDevice = false}) {
    final s = LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice);
    log.add(s);
    return s;
  }

  void done(LogStep s, String result, [StepStatus status = StepStatus.done]) => s
    ..result = result
    ..status = status;

  final ids = extractIdentifiers(pastedIdentifiers);
  final extra = await linkedReports(ids, step, done);
  done(step('Relationship scorer', 'Scoring your answers on your device'), '${answers.length} answer(s)');
  return scoreQuestionnaire(answers, identifiers: ids, extraSignals: extra, log: log);
}

/// Asks the attribution database (through [linkedReportCounter]) whether
/// these identifiers have been reported before.
Future<List<RelSignal>> linkedReports(
  List<String> ids,
  LogStep Function(String tool, String action, {bool sentOffDevice}) step,
  void Function(LogStep, String, [StepStatus]) done,
) async {
  final counter = linkedReportCounter;
  if (counter == null || ids.isEmpty) {
    step('Linked reports', ids.isEmpty ? 'Skipped: no account, number or link to look up' : 'Skipped: scam database not available')
        .status = StepStatus.skipped;
    return const [];
  }
  final s = step('Linked reports', 'Looking up ${ids.length} account number(s), phone number(s) or link(s) in the scam database on your device');
  try {
    final n = await counter(ids);
    done(s, n > 0 ? 'Found in $n earlier report(s)' : 'Not found in earlier reports');
    if (n > 0) {
      return [
        RelSignal('Linked reports', 'Already reported by others',
            'An account, number or link they gave you appears in $n earlier scam report(s).', 25),
      ];
    }
  } catch (e) {
    done(s, 'Lookup failed ($e)', StepStatus.failed);
  }
  return const [];
}
