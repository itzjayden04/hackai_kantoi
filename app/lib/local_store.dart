import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/cases.dart';
import 'engine/retention.dart';
import 'engine/review.dart';
import 'auth/auth_service.dart';
import 'cloud/outbox.dart';
import 'history/history_log.dart';
import 'report/report_store.dart';
import 'state.dart';
import 'vault/vault.dart';

/// What Kantoi keeps on the device besides settings: the feedback review
/// queue and the victim's case checklists, plus the retention choice that
/// limits how long anything is kept.
class LocalStore extends ChangeNotifier {
  Retention retention = defaultRetention;
  final List<ReviewItem> review = [];
  final List<ScamCase> cases = [];

  static const _kRetention = 'retention';
  static const _kReview = 'reviewQueue';
  static const _kCases = 'cases';

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      retention = Retention.values.firstWhere((r) => r.name == p.getString(_kRetention), orElse: () => defaultRetention);
      review
        ..clear()
        ..addAll((p.getStringList(_kReview) ?? []).map((s) => ReviewItem.fromJson(jsonDecode(s) as Map<String, dynamic>)));
      cases
        ..clear()
        ..addAll((p.getStringList(_kCases) ?? []).map((s) => ScamCase.fromJson(jsonDecode(s) as Map<String, dynamic>)));
    } catch (_) {}
    await applyRetention();
  }

  /// Removes everything older than the retention period: checks, live
  /// items, the review queue and cases. Runs on app start.
  Future<void> applyRetention({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final p = retentionPeriod(retention);
    if (p != null) {
      appState.dropOlderThan(t.subtract(p));
      await historyLog.dropOlderThan(t.subtract(p));
    }
    final removed = pruneOld(review, (r) => r.at, retention, now: t) + pruneOld(cases, (c) => c.createdAt, retention, now: t);
    if (removed > 0) await _save();
    notifyListeners();
  }

  Future<void> setRetention(Retention r) async {
    retention = r;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kRetention, r.name);
    } catch (_) {}
    await applyRetention();
  }

  Future<void> addReview(ReviewItem item) async {
    review.insert(0, item);
    if (review.length > 500) review.removeLast();
    notifyListeners();
    await _save();
  }

  Future<void> clearReview() async {
    review.clear();
    notifyListeners();
    await _save();
  }

  String exportReviewJson() => const JsonEncoder.withIndent('  ').convert({
        'exportedAt': DateTime.now().toIso8601String(),
        'note': 'User feedback for review. Summaries only; no message text or personal details.',
        'items': review.map((r) => r.toJson()).toList(),
      });

  /// The case with this id, or a new unsaved one. It is saved the first time
  /// a step is ticked.
  ScamCase caseFor(String id, {String title = 'My scam case'}) =>
      cases.where((c) => c.id == id).firstOrNull ?? ScamCase(id: id, createdAt: DateTime.now(), title: title);

  ScamCase? get latestOpenCase => cases.where((c) => c.isOpen).firstOrNull;

  List<ScamCase> reminders({DateTime? now}) => cases.where((c) => c.needsReminder(now ?? DateTime.now())).toList();

  Future<void> setStep(ScamCase c, String stepId, bool done) async {
    if (!cases.contains(c)) cases.insert(0, c);
    if (done) {
      c.done[stepId] = DateTime.now();
    } else {
      c.done.remove(stepId);
    }
    notifyListeners();
    await _save();
  }

  Future<void> snooze(ScamCase c, {Duration by = const Duration(hours: 12)}) async {
    c.snoozedUntil = DateTime.now().add(by);
    notifyListeners();
    await _save();
  }

  Future<void> closeCase(ScamCase c) async {
    c.closed = true;
    notifyListeners();
    await _save();
  }

  /// "Delete all my Kantoi data": clears every stored value, including
  /// settings. Only the AI key built into the app (a constant) remains.
  Future<void> deleteAll() async {
    review.clear();
    cases.clear();
    retention = defaultRetention;
    appState.forgetAll();
    await historyLog.clear();
    await reportStore.deleteAll();
    await cloudOutbox.clear();
    await vault.deleteAll();
    vault.lock();
    await auth.deleteAccount();
    try {
      final p = await SharedPreferences.getInstance();
      await p.clear();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kReview, review.map((r) => jsonEncode(r.toJson())).toList());
      await p.setStringList(_kCases, cases.map((c) => jsonEncode(c.toJson())).toList());
    } catch (_) {}
  }
}

final localStore = LocalStore();
