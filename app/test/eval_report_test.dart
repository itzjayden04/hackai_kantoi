// Prints the evaluation tables for every labelled set in test/data.
//
//   flutter test test/eval_report_test.dart
//
// The engine uses Flutter's asset loader, so `dart run tool/evaluate.dart`
// cannot load it on its own; this runs the same evaluation inside the
// Flutter test runner instead.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/engine/evaluation.dart';

void main() {
  for (final path in [
    'test/data/labelled_messages.csv',
    'test/data/holdout_messages.csv',
    'test/data/holdout_v2_messages.csv',
  ]) {
    test('evaluation report: $path', () async {
      final f = File(path);
      if (!f.existsSync()) {
        markTestSkipped('$path not found');
        return;
      }
      final r = await evaluate(parseLabelledCsv(f.readAsStringSync()), thresholds: defaultThresholds);
      // ignore: avoid_print
      print('\n== $path ==\n${r.format(showErrorsAt: 40)}');
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
