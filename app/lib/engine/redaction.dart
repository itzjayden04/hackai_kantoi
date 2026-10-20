/// Finds the user's personal data so it can be masked before anything leaves
/// the device or goes into a report.
library;

enum PiiType { ic, phone, bankAccount, email, card, address, name }

class PiiMatch {
  final PiiType type;
  final int start;
  final int end;
  final String value;
  const PiiMatch(this.type, this.start, this.end, this.value);
}

String piiLabel(PiiType t) => switch (t) {
      PiiType.ic => 'IC number',
      PiiType.phone => 'Phone number',
      PiiType.bankAccount => 'Account number',
      PiiType.email => 'Email',
      PiiType.card => 'Card number',
      PiiType.address => 'Address',
      PiiType.name => 'Name',
    };

final _patterns = <PiiType, RegExp>{
  // MyKad: YYMMDD-PB-###G
  PiiType.ic: RegExp(r'\b\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])-?\d{2}-?\d{4}\b'),
  PiiType.card: RegExp(r'\b(?:\d{4}[\s-]?){3}\d{4}\b'),
  PiiType.email: RegExp(r'\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b'),
  PiiType.phone: RegExp(r'(?:\+?6?0)1[0-9][\s-]?\d{3,4}[\s-]?\d{4}\b'),
  PiiType.bankAccount: RegExp(r'\b\d{10,16}\b'),
  PiiType.address: RegExp(
      r'\b(?:no\.?\s?\d+[a-z]?,?\s)?(?:jalan|jln|lorong|persiaran|taman|tmn|lebuh)\s[^,\n]{2,40}(?:,[^,\n\d]{2,40}){0,3},?\s*\d{5}\b',
      caseSensitive: false),
};

List<PiiMatch> findPii(String text, {Set<String> ownValues = const {}}) {
  final out = <PiiMatch>[];
  final taken = <(int, int)>[];
  for (final e in _patterns.entries) {
    for (final m in e.value.allMatches(text)) {
      if (taken.any((t) => m.start < t.$2 && m.end > t.$1)) continue;
      taken.add((m.start, m.end));
      out.add(PiiMatch(e.key, m.start, m.end, m.group(0)!));
    }
  }
  for (final v in ownValues.where((v) => v.trim().length >= 3)) {
    var i = text.toLowerCase().indexOf(v.toLowerCase());
    while (i >= 0) {
      final s = i, e = i + v.length;
      if (!taken.any((t) => s < t.$2 && e > t.$1)) {
        taken.add((s, e));
        out.add(PiiMatch(PiiType.name, s, e, text.substring(s, e)));
      }
      i = text.toLowerCase().indexOf(v.toLowerCase(), e);
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

String mask(PiiMatch m) {
  final v = m.value;
  if (m.type == PiiType.email) {
    final at = v.indexOf('@');
    return '${v[0]}***${v.substring(at)}';
  }
  final digits = v.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 6) return '[${piiLabel(m.type)} ending ${digits.substring(digits.length - 4)}]';
  return '[${piiLabel(m.type)}]';
}

/// Masks every match whose index is not in [keep].
String redact(String text, List<PiiMatch> matches, {Set<int> keep = const {}}) {
  final b = StringBuffer();
  var pos = 0;
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    if (keep.contains(i)) continue;
    b.write(text.substring(pos, m.start));
    b.write(mask(m));
    pos = m.end;
  }
  b.write(text.substring(pos));
  return b.toString();
}
