/// The things Kantoi can look up on the public web (phone numbers, bank
/// accounts, emails and websites), every way people write them, and how to
/// spot them in a page.
library;

import '../trace/trace_input.dart' show analyzePhone, parseTraceInput, SeedKind;
import '../url_analyzer.dart' show registrableDomain;

enum WebIdKind { phone, account, email, domain }

class WebIdentifier {
  final WebIdKind kind;

  /// Canonical form: international digits for phones (60123456789), digits
  /// for accounts, lower-case email or registrable domain.
  final String key;
  const WebIdentifier(this.kind, this.key);

  factory WebIdentifier.phone(String raw) => WebIdentifier(WebIdKind.phone, analyzePhone(raw).digits);
  factory WebIdentifier.account(String raw) => WebIdentifier(WebIdKind.account, raw.replaceAll(RegExp(r'\D'), ''));
  factory WebIdentifier.email(String raw) => WebIdentifier(WebIdKind.email, raw.trim().toLowerCase());
  factory WebIdentifier.domain(String raw) => WebIdentifier(WebIdKind.domain, registrableDomain(raw.trim().toLowerCase()));

  String get id => '${kind.name}:$key';

  bool get _myPhone => kind == WebIdKind.phone && key.startsWith('60') && key.length >= 10;

  /// National form for Malaysian numbers (0123456789).
  String? get local => _myPhone ? '0${key.substring(2)}' : null;

  String get display => switch (kind) {
        WebIdKind.phone => _myPhone ? _spaced : '+$key',
        WebIdKind.account => _grouped,
        _ => key,
      };

  String get kindLabel => switch (kind) {
        WebIdKind.phone => 'number',
        WebIdKind.account => 'bank account',
        WebIdKind.email => 'email address',
        WebIdKind.domain => 'website',
      };

  // +60 12-345 6789
  String get _spaced {
    final n = key.substring(2);
    if (!n.startsWith('1')) return '+60 ${n.substring(0, 1)}-${n.substring(1)}';
    final rest = n.substring(2);
    final head = rest.length > 4 ? rest.substring(0, rest.length - 4) : rest;
    return '+60 ${n.substring(0, 2)}-$head ${rest.substring(head.length)}';
  }

  String get _grouped => [for (var i = 0; i < key.length; i += 4) key.substring(i, i + 4 > key.length ? key.length : i + 4)].join(' ');

  /// Every common way of writing it, for search queries.
  List<String> get variants {
    switch (kind) {
      case WebIdKind.phone:
        if (!_myPhone) return ['+$key', key];
        final l = local!;
        final n = key.substring(2);
        if (!n.startsWith('1')) return [l, '+60 ${n.substring(0, 1)}-${n.substring(1)}', key];
        final rest = l.substring(3);
        final head = rest.length > 4 ? rest.substring(0, rest.length - 4) : rest;
        return {
          _spaced, // +60 12-345 6789
          '${l.substring(0, 3)}-$rest', // 012-3456789
          l, // 0123456789
          key, // 60123456789
          '${l.substring(0, 3)}-$head ${rest.substring(head.length)}', // 012-345 6789
        }.toList();
      case WebIdKind.account:
        return {key, _grouped}.toList();
      case WebIdKind.email:
      case WebIdKind.domain:
        return [key];
    }
  }

  /// Where it appears in [text] (start offsets), however it was written.
  List<int> findIn(String text) {
    switch (kind) {
      case WebIdKind.phone:
      case WebIdKind.account:
        final wanted = {key, ?local, if (kind == WebIdKind.phone) '00$key'};
        final at = <int>{
          for (final m in RegExp(r'\+?\d[\d  ().\-]{5,24}\d').allMatches(text))
            if (wanted.contains(m.group(0)!.replaceAll(RegExp(r'\D'), ''))) m.start,
          // A run can swallow neighbouring digits ("Tel: 0123456789 / 0198765432").
          for (final v in wanted)
            for (final m in RegExp('(?<!\\d)${RegExp.escape(v)}(?!\\d)').allMatches(text)) m.start,
        };
        return at.toList()..sort();
      case WebIdKind.email:
      case WebIdKind.domain:
        final lower = text.toLowerCase();
        return [
          for (final m in RegExp('(?<![a-z0-9-])${RegExp.escape(key)}(?![a-z0-9-])').allMatches(lower)) m.start,
        ];
    }
  }

  bool foundIn(String text) => findIn(text).isNotEmpty;

  /// Whether this is one of the user's own details (never searched).
  bool isOwn(Set<String> own) {
    for (final o in own) {
      final t = o.trim();
      if (t.isEmpty) continue;
      final digits = t.replaceAll(RegExp(r'\D'), '');
      switch (kind) {
        case WebIdKind.phone:
          if (digits.length >= 8 && analyzePhone(t).digits == key) return true;
        case WebIdKind.account:
          if (digits.length >= 6 && digits == key) return true;
        case WebIdKind.email:
        case WebIdKind.domain:
          if (t.toLowerCase() == key) return true;
      }
    }
    return false;
  }

  @override
  bool operator ==(Object other) => other is WebIdentifier && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}

/// Phone numbers, accounts and emails in [text] worth looking up, without
/// the user's own details.
List<WebIdentifier> webIdentifiersIn(String text, {Set<String> own = const {}, int max = 3}) {
  final out = <WebIdentifier>[];
  for (final s in parseTraceInput(text).seeds) {
    final id = switch (s.kind) {
      SeedKind.phone => WebIdentifier.phone(s.value),
      SeedKind.account => WebIdentifier.account(s.value),
      SeedKind.email => WebIdentifier.email(s.value),
      SeedKind.url => null,
    };
    if (id == null || id.key.length < 6 || id.isOwn(own) || out.contains(id)) continue;
    out.add(id);
    if (out.length >= max) break;
  }
  return out;
}
