import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a history entry records.
enum HistoryType { check, trace, learn, report }

/// One line of the user's history in Settings. Holds a short title and a
/// result, never the full message.
class HistoryEntry {
  final HistoryType type;
  final String title;
  final String detail;
  /// A risk level name (danger, suspicious, caution, safe), a quiz score
  /// ("8/10") or a report status.
  final String result;
  final DateTime at;
  /// What tapping the entry reopens: a check time, trace target or report id.
  final String ref;
  const HistoryEntry(this.type, this.title, {this.detail = '', this.result = '', required this.at, this.ref = ''});

  Map<String, dynamic> toJson() =>
      {'type': type.name, 'title': title, 'detail': detail, 'result': result, 'at': at.toIso8601String(), 'ref': ref};

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        HistoryType.values.firstWhere((t) => t.name == j['type'], orElse: () => HistoryType.check),
        j['title'] as String? ?? '',
        detail: j['detail'] as String? ?? '',
        result: j['result'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        ref: j['ref'] as String? ?? '',
      );
}

/// The user's Check, Trace, Learn and Report history, kept on this phone and
/// trimmed by the retention setting.
class HistoryLog extends ChangeNotifier {
  static const _k = 'history.v1';
  static const maxEntries = 500;
  final List<HistoryEntry> entries = [];

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      entries
        ..clear()
        ..addAll((p.getStringList(_k) ?? []).map((s) => HistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>)));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> add(HistoryEntry e) async {
    // The same item logged twice in a row (e.g. a report saved again) is one line.
    entries.removeWhere((x) => x.type == e.type && x.ref.isNotEmpty && x.ref == e.ref);
    entries.insert(0, e);
    if (entries.length > maxEntries) entries.removeRange(maxEntries, entries.length);
    await _save();
  }

  List<HistoryEntry> filtered({HistoryType? type, String query = ''}) {
    final q = query.trim().toLowerCase();
    return entries
        .where((e) => type == null || e.type == type)
        .where((e) => q.isEmpty || e.title.toLowerCase().contains(q) || e.detail.toLowerCase().contains(q))
        .toList();
  }

  int count(HistoryType t) => entries.where((e) => e.type == t).length;

  Future<void> remove(HistoryEntry e) async {
    entries.remove(e);
    await _save();
  }

  Future<void> dropOlderThan(DateTime cutoff) async {
    final n = entries.length;
    entries.removeWhere((e) => e.at.isBefore(cutoff));
    if (entries.length != n) await _save();
  }

  Future<void> clear() async {
    entries.clear();
    await _save();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_k, entries.map((e) => jsonEncode(e.toJson())).toList());
    } catch (_) {}
    notifyListeners();
  }
}

final historyLog = HistoryLog();

/// "Today", "Yesterday", or "Last week"/"Earlier" headers for a list.
String historyGroup(DateTime at, DateTime now) {
  final d = DateTime(now.year, now.month, now.day).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (d <= 0) return 'Today';
  if (d == 1) return 'Yesterday';
  if (d < 7) return 'This week';
  if (d < 30) return 'This month';
  return 'Earlier';
}
