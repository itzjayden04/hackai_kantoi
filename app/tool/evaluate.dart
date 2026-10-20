// Measures Kantoi's built-in checks (network and AI off) on labelled messages
// and prints precision, recall, F1 and a confusion matrix per threshold.
//
// From the app folder:
//   dart run tool/evaluate.dart                         # synthetic Malaysian set
//   dart run tool/evaluate.dart --uci path/to/SMSSpamCollection
//   dart run tool/evaluate.dart --csv my_set.csv        # columns label,lang,type,text
//   dart run tool/evaluate.dart --errors-at 65          # list mistakes at another threshold
//
// The UCI SMS Spam Collection is not bundled; download it from
// https://archive.ics.uci.edu/dataset/228/sms+spam+collection and pass the
// unzipped "SMSSpamCollection" file (tab-separated "ham/spam<TAB>text").
import 'dart:io';

import 'package:kantoi/engine/evaluation.dart';

Future<void> main(List<String> args) async {
  String? uci, csv;
  var errorsAt = 40;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--uci':
        uci = args[++i];
      case '--csv':
        csv = args[++i];
      case '--errors-at':
        errorsAt = int.parse(args[++i]);
      case '-h' || '--help':
        stdout.writeln('Usage: dart run tool/evaluate.dart [--csv file] [--uci SMSSpamCollection] [--errors-at 40]');
        return;
    }
  }
  final thresholds = {...defaultThresholds, errorsAt}.toList()..sort();

  final csvPath = csv ?? (uci == null ? 'test/data/labelled_messages.csv' : null);
  final sets = <String, List<LabelledMessage>>{};
  if (csvPath != null) sets[csvPath] = parseLabelledCsv(File(csvPath).readAsStringSync());
  if (uci != null) sets[uci] = parseUciSms(File(uci).readAsStringSync());
  for (final e in sets.entries) {
    stdout
      ..writeln('== ${e.key} ==')
      ..writeln((await evaluate(e.value, thresholds: thresholds)).format(showErrorsAt: errorsAt));
  }
}
