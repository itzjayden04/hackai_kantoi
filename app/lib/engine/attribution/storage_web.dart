import 'package:shared_preferences/shared_preferences.dart';

/// On the web the intel store is kept in browser storage.
Future<String?> readIntelFile() async => (await SharedPreferences.getInstance()).getString('kantoi_intel');

Future<void> writeIntelFile(String json) async => (await SharedPreferences.getInstance()).setString('kantoi_intel', json);
