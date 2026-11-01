import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where queued items go once the cloud is connected. Firebase (next tag)
/// implements this; until then items wait in the outbox on the phone.
abstract class CloudSink {
  /// Writes one document. Throws when offline or refused, so it stays queued.
  Future<void> write(String collection, String id, Map<String, dynamic> data);
}

class OutboxItem {
  final String collection;
  final String id;
  final Map<String, dynamic> data;
  final DateTime at;
  int tries;
  OutboxItem(this.collection, this.id, this.data, this.at, {this.tries = 0});

  Map<String, dynamic> toJson() => {'c': collection, 'id': id, 'data': data, 'at': at.toIso8601String(), 'tries': tries};
  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
      j['c'] as String, j['id'] as String, (j['data'] as Map).cast<String, dynamic>(), DateTime.parse(j['at'] as String),
      tries: j['tries'] as int? ?? 0);
}

/// A queue of masked records for Kantoi's shared scam database. Everything
/// in it has already been stripped of message text, names and screenshots.
/// Nothing is sent while [sink] is null.
class Outbox extends ChangeNotifier {
  static const _k = 'cloud.outbox';
  static const maxItems = 500;
  final List<OutboxItem> items = [];
  CloudSink? sink;
  /// Total records sent from this phone, shown in Settings.
  int sent = 0;

  /// Share masked details of confident scam detections. On by default: the
  /// user agreed at sign-up, and can turn it off in Settings.
  bool shareDetections = true;

  Future<void> setShareDetections(bool on) async {
    shareDetections = on;
    if (!on) items.removeWhere((i) => i.collection == 'detections');
    await _persist();
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      items
        ..clear()
        ..addAll((p.getStringList(_k) ?? []).map((s) => OutboxItem.fromJson(jsonDecode(s) as Map<String, dynamic>)));
      sent = p.getInt('$_k.sent') ?? 0;
      shareDetections = p.getBool('$_k.share') ?? true;
    } catch (_) {}
    notifyListeners();
  }

  /// Queues a record; the same collection/id replaces an older queued copy.
  Future<void> add(String collection, String id, Map<String, dynamic> data, {DateTime? now}) async {
    items.removeWhere((i) => i.collection == collection && i.id == id);
    items.add(OutboxItem(collection, id, data, now ?? DateTime.now()));
    while (items.length > maxItems) {
      items.removeAt(0);
    }
    await _persist();
    await flush();
  }

  /// Drops a queued record, e.g. when the user marks a detection "not a scam".
  Future<void> withdraw(String collection, String id) async {
    items.removeWhere((i) => i.collection == collection && i.id == id);
    await _persist();
  }

  /// Sends what it can. Items that fail stay for next time.
  Future<int> flush() async {
    final s = sink;
    if (s == null || items.isEmpty) return 0;
    var n = 0;
    for (final i in List.of(items)) {
      try {
        await s.write(i.collection, i.id, i.data);
        items.remove(i);
        n++;
      } catch (_) {
        i.tries++;
      }
    }
    sent += n;
    await _persist();
    return n;
  }

  Future<void> clear() async {
    items.clear();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_k, items.map((i) => jsonEncode(i.toJson())).toList());
      await p.setInt('$_k.sent', sent);
      await p.setBool('$_k.share', shareDetections);
    } catch (_) {}
    notifyListeners();
  }
}

final cloudOutbox = Outbox();
