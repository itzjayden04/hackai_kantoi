import 'models.dart';

final _url = RegExp(
  r'''((?:https?://|www\.)[^\s<>"']+|\b[a-z0-9][a-z0-9-]{1,62}(?:\.[a-z0-9-]{2,63})*\.(?:com|my|net|org|xyz|top|info|link|site|online|shop|club|vip|cc|io|co|me|app|live|store|icu|buzz|life|fun|asia|biz|tk|ml|ga|cf|gq|ly|gl|to|sh)(?:/[^\s<>"']*)?)''',
  caseSensitive: false,
);
final _email = RegExp(r'\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b');
// Malaysian mobile and landline numbers, with or without +60, plus generic
// international numbers starting with +.
final _phone = RegExp(r'(?:\+?6?0)1[0-9][\s-]?\d{3,4}[\s-]?\d{4}\b|\+\d{1,3}[\s-]?\d{2,4}[\s-]?\d{3,4}[\s-]?\d{3,4}\b');
final _amount = RegExp(r'\b(?:RM|MYR|USD|USDT|\$)\s?\d[\d,]*(?:\.\d{1,2})?\b|\b\d[\d,]*(?:\.\d{1,2})?\s?(?:ringgit|USDT)\b', caseSensitive: false);
final _btc = RegExp(r'\b(?:bc1[a-z0-9]{25,59}|[13][a-km-zA-HJ-NP-Z1-9]{25,34})\b');
final _eth = RegExp(r'\b0x[a-fA-F0-9]{40}\b');
final _tron = RegExp(r'\bT[1-9A-HJ-NP-Za-km-z]{33}\b');
final _handle = RegExp(r'(?:^|\s)(@[A-Za-z0-9_]{4,32})\b|\bt\.me/([A-Za-z0-9_]{4,32})');
// Bank account numbers: 10-16 digit runs (optionally grouped) near a banking word.
final _acctNum = RegExp(r'\b\d{4}[\s-]?\d{2,4}[\s-]?\d{2,4}[\s-]?\d{0,4}\b');
final _bankWord = RegExp(
    r'\b(acc(?:oun)?t|a/c|akaun|bank|maybank|cimb|public ?bank|rhb|hong ?leong|ambank|bsn|bank islam|affin|alliance|uob|ocbc|hsbc|transfer|bayar|pay(?:ment)?|deposit)\b',
    caseSensitive: false);

List<Entity> extractEntities(String text) {
  final out = <Entity>[];
  final taken = <(int, int)>[];
  bool overlaps(int s, int e) => taken.any((t) => s < t.$2 && e > t.$1);
  void add(EntityType t, Match m, [String? value, int group = 0]) {
    final s = m.start, e = m.end;
    if (overlaps(s, e)) return;
    taken.add((s, e));
    out.add(Entity(t, (value ?? m.group(group)!).trim(), s, e));
  }

  for (final m in _email.allMatches(text)) {
    add(EntityType.email, m);
  }
  for (final m in _url.allMatches(text)) {
    var v = m.group(0)!.replaceAll(RegExp(r'[.,;:!?)\]]+$'), '');
    add(EntityType.url, m, v);
  }
  for (final re in [_btc, _eth, _tron]) {
    for (final m in re.allMatches(text)) {
      add(EntityType.cryptoWallet, m);
    }
  }
  for (final m in _phone.allMatches(text)) {
    add(EntityType.phone, m);
  }
  for (final m in _amount.allMatches(text)) {
    add(EntityType.amount, m);
  }
  for (final m in _acctNum.allMatches(text)) {
    final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10 || digits.length > 16) continue;
    final windowStart = (m.start - 60).clamp(0, text.length);
    final windowEnd = (m.end + 30).clamp(0, text.length);
    if (!_bankWord.hasMatch(text.substring(windowStart, windowEnd))) continue;
    add(EntityType.bankAccount, m, digits);
  }
  for (final m in _handle.allMatches(text)) {
    final v = m.group(1) ?? '@${m.group(2)}';
    add(EntityType.handle, m, v);
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}
