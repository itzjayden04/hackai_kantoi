// Prints how the built-in engine (network and AI off) scores one message.
//   dart run tool/explain.dart "message text"
//   dart run tool/explain.dart --file messages.txt   (one message per line)
import 'dart:io';

import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';

Future<void> main(List<String> args) async {
  final texts = args.isNotEmpty && args.first == '--file'
      ? File(args[1]).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList()
      : [args.join(' ')];
  for (final t in texts) {
    final inv = await investigate(t, options: const InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false));
    stdout.writeln('${inv.verdict.score} ${inv.verdict.level.name} (${inv.verdict.scamType}): ${t.length > 60 ? t.substring(0, 60) : t}');
    for (final f in inv.findings) {
      stdout.writeln('  ${f.weight.toString().padLeft(4)}  ${f.category.name}  ${f.title}  [${f.tool}]');
    }
  }
}
