import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small JSON helpers over shared_preferences that never throw, so a broken
/// store only means starting fresh.
Future<Map<String, dynamic>?> readJson(String key) async {
  try {
    final s = (await SharedPreferences.getInstance()).getString(key);
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<void> writeJson(String key, Map<String, dynamic> value) async {
  try {
    await (await SharedPreferences.getInstance()).setString(key, jsonEncode(value));
  } catch (_) {}
}

Future<void> removeKey(String key) async {
  try {
    await (await SharedPreferences.getInstance()).remove(key);
  } catch (_) {}
}
