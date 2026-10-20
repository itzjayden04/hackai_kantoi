import '../engine/attribution/fingerprint.dart' show phoneKey;
import '../engine/models.dart';

/// What the Call guard decided about an incoming number. It only ever sees
/// the number: never the call's sound or words.
class CallVerdict {
  final String number;
  final RiskLevel level;
  final String title;
  final List<String> reasons;
  const CallVerdict(this.number, this.level, this.title, this.reasons);

  bool get warn => level.index >= RiskLevel.suspicious.index;

  Map<String, dynamic> toJson() => {
        'number': number,
        'warn': warn,
        'level': level.name,
        'label': riskLabel(level),
        'title': title,
        'reasons': reasons,
      };
}

/// Country codes used for one-ring ("call me back") and premium-rate call
/// scams, and satellite or international networks real callers rarely use.
const premiumPrefixes = {
  '222', '224', '225', '231', '232', '242', '243', '252', '261', '269', '675', '677', '678', '681', '682', '683',
  '686', '688', '690', '691', '692', '870', '881', '882', '883', '979',
};

/// Digits only, in international form without "+" (60123456789), or null for
/// a hidden number.
String? normalizeCaller(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  final d = t.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return null;
  if (t.startsWith('+')) return d;
  if (d.startsWith('00')) return d.substring(2);
  return phoneKey(d);
}

/// Checks an incoming caller against the user's own blocks, Kantoi's scam
/// list ([listed] returns found and whether it is demo data) and simple
/// number patterns.
CallVerdict checkCaller(String? raw, {bool marked = false, (bool, bool) Function(String key)? listed}) {
  final n = normalizeCaller(raw);
  if (n == null) {
    return const CallVerdict('Hidden number', RiskLevel.caution, 'Hidden number',
        ['The caller hid their number. Banks and the police do not need to hide theirs.']);
  }
  final shown = '+$n';
  final reasons = <String>[];
  var level = RiskLevel.safe;
  void raise(RiskLevel l, String why) {
    reasons.add(why);
    if (l.index > level.index) level = l;
  }

  if (marked) raise(RiskLevel.danger, 'You marked this number as a scam before.');
  final (found, demo) = listed?.call(n) ?? (false, false);
  if (found) raise(RiskLevel.danger, demo ? 'This number is on Kantoi\'s scam list (demo data).' : 'This number is on Kantoi\'s scam list.');

  if (RegExp(r'^(\d)\1{6,}$').hasMatch(n.substring(n.length > 7 ? n.length - 7 : 0)) || n.length < 6) {
    raise(RiskLevel.suspicious, 'The number looks made up.');
  }

  if (n.startsWith('60')) {
    final local = n.substring(2);
    if (local.startsWith('0') || (local.startsWith('60') && local.length >= 10)) {
      // "+600..." or "+6060..." does not exist: a sign the caller ID was faked.
      raise(RiskLevel.suspicious, 'This is not a real Malaysian number format. Caller IDs can be faked.');
    } else if (RegExp(r'^1[378]00').hasMatch(local)) {
      // 1300 / 1800 company hotlines.
    } else if (local.startsWith('1')) {
      final ok = local.startsWith('11') ? local.length == 10 : local.length == 9;
      if (!ok) raise(RiskLevel.suspicious, 'Wrong length for a Malaysian mobile number. Caller IDs can be faked.');
    } else if (RegExp(r'^[3-9]').hasMatch(local)) {
      if (local.length < 8 || local.length > 9) raise(RiskLevel.suspicious, 'Wrong length for a Malaysian phone number. Caller IDs can be faked.');
    }
  } else {
    final cc = premiumPrefixes.where((p) => n.startsWith(p)).firstOrNull;
    if (cc != null) {
      raise(RiskLevel.suspicious, 'Calls from +$cc are often one-ring or premium-rate scams. Do not call back.');
    } else {
      raise(RiskLevel.caution, 'This call comes from outside Malaysia. Many "police", "bank" and "parcel" scam calls do.');
    }
  }

  final title = switch (level) {
    RiskLevel.danger => 'Likely scam caller',
    RiskLevel.suspicious => 'Suspicious caller',
    RiskLevel.caution => 'Unknown caller',
    RiskLevel.safe => 'No warning signs',
  };
  return CallVerdict(shown, level, title, reasons);
}
