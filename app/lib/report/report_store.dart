import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/outbox.dart';
import 'scam_report.dart';

/// The user's reports, kept on this phone. Sending a report queues only its
/// masked payload for Kantoi's scam database.
class ReportStore extends ChangeNotifier {
  static const _k = 'reports.v2';
  final List<ScamReport> reports = [];

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      reports
        ..clear()
        ..addAll((p.getStringList(_k) ?? []).map((s) => ScamReport.fromJson(jsonDecode(s) as Map<String, dynamic>)));
      reports.sort((a, b) => b.updated.compareTo(a.updated));
    } catch (_) {}
    notifyListeners();
  }

  ScamReport? byId(String id) => reports.where((r) => r.id == id).firstOrNull;

  /// A draft with nothing filled in yet, or the latest unfinished draft.
  ScamReport? get openDraft => reports.where((r) => r.status == ReportStatus.draft).firstOrNull;

  Future<void> save(ScamReport r, {DateTime? now}) async {
    r.updated = now ?? DateTime.now();
    reports.removeWhere((x) => x.id == r.id);
    reports.insert(0, r);
    await _persist();
  }

  /// Marks the report sent and, when the user allows sharing, queues its
  /// masked payload. Returns whether anything was queued.
  Future<bool> submit(ScamReport r, {Outbox? outbox, DateTime? now}) async {
    r.status = ReportStatus.sent;
    await save(r, now: now);
    if (!r.shareWithKantoi) return false;
    await (outbox ?? cloudOutbox).add('reports', r.id, r.sharedPayload(), now: now);
    return true;
  }

  Future<void> remove(String id) async {
    reports.removeWhere((r) => r.id == id);
    await _persist();
  }

  Future<void> deleteAll() async {
    reports.clear();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_k, reports.map((r) => jsonEncode(r.toJson())).toList());
    } catch (_) {}
    notifyListeners();
  }
}

final reportStore = ReportStore();
