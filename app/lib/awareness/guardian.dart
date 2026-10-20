/// Guardian mode: a trusted family member the user can alert in one tap.
/// Alerts never include the suspicious message or any personal details, and
/// are only ever sent by the user pressing send in WhatsApp or SMS.
library;

import 'package:flutter/foundation.dart';

import '../engine/models.dart';
import 'explainers.dart';
import 'prefs.dart';

class Guardian {
  final String name;
  final String phone;
  final bool consent;
  final bool useSms;
  const Guardian({required this.name, required this.phone, this.consent = false, this.useSms = false});

  /// Ready to alert: has a name, a valid number and the user's consent.
  bool get ready => consent && name.trim().isNotEmpty && normalisePhone(phone) != null;

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone, 'consent': consent, 'useSms': useSms};

  factory Guardian.fromJson(Map<String, dynamic> j) => Guardian(
        name: (j['name'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        consent: j['consent'] == true,
        useSms: j['useSms'] == true,
      );
}

/// International digits for wa.me and sms, assuming Malaysia (+60) for local
/// numbers. Returns null if it can't be a phone number.
String? normalisePhone(String raw) {
  final s = raw.trim();
  var d = s.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00')) {
    d = d.substring(2);
  } else if (s.startsWith('+') || d.startsWith('60')) {
    // Already international.
  } else if (d.startsWith('0')) {
    d = '60${d.substring(1)}';
  } else if (d.startsWith('1') && d.length >= 9 && d.length <= 10) {
    d = '60$d';
  }
  return d.length >= 10 && d.length <= 15 ? d : null;
}

/// What the scam is trying to get the user to do, in plain words.
String likelyAction(Iterable<CueCategory> cats) {
  final c = cats.toSet();
  if (c.contains(CueCategory.credentials)) return 'share a code or log in to my account';
  if (c.contains(CueCategory.payment) || c.contains(CueCategory.investment)) return 'pay or transfer money';
  if (c.contains(CueCategory.link)) return 'open a link';
  if (c.contains(CueCategory.channelSwitch)) return 'move the chat to another app';
  return 'reply to it';
}

/// The short alert text. Built only from the scam type name and the risk
/// level, never from the message itself.
String guardianAlert({required String guardianName, Investigation? inv, bool emergency = false}) {
  final hi = guardianName.trim().isEmpty ? 'Hi' : 'Hi ${guardianName.trim()}';
  final type = inv == null ? null : explainerForInvestigation(inv);
  final what = type == null || type.genuine || type.id == 'general' ? '' : ' (type: ${type.name})';
  if (emergency) {
    return '$hi, this is an alert from my Kantoi app. I think I was caught by a scam$what and may have already paid or '
        'shared my details. Please call me as soon as you can.';
  }
  final level = inv == null ? 'Very likely a scam' : riskLabel(inv.verdict.level);
  final action = likelyAction(inv?.findings.where((f) => f.isRisk).map((f) => f.category) ?? const []);
  return '$hi, this is an alert from my Kantoi app. I got a message that Kantoi rated "$level"$what. '
      'It wants me to $action. Can you call me before I do anything?';
}

Uri guardianUri(Guardian g, String text) {
  final n = normalisePhone(g.phone) ?? '';
  return g.useSms
      ? Uri.parse('sms:+$n?body=${Uri.encodeComponent(text)}')
      : Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(text)}');
}

class GuardianStore extends ChangeNotifier {
  static const _key = 'awareness.guardian';
  Guardian? guardian;
  bool _loaded = false;

  Guardian? get ready => guardian?.ready == true ? guardian : null;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final j = await readJson(_key);
    if (j != null) guardian = Guardian.fromJson(j);
    notifyListeners();
  }

  Future<void> save(Guardian g) async {
    guardian = g;
    _loaded = true;
    notifyListeners();
    await writeJson(_key, g.toJson());
  }

  Future<void> clear() async {
    guardian = null;
    notifyListeners();
    await removeKey(_key);
  }
}

final guardianStore = GuardianStore();
