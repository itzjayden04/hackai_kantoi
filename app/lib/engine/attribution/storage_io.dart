import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The intel store lives in a JSON file in the app's support folder.
Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}kantoi_intel.json');

Future<String?> readIntelFile() async {
  final f = await _file();
  return await f.exists() ? f.readAsString() : null;
}

Future<void> writeIntelFile(String json) async {
  final f = await _file();
  await f.parent.create(recursive: true);
  final tmp = File('${f.path}.tmp');
  await tmp.writeAsString(json, flush: true);
  await tmp.rename(f.path);
}
