import '../engine/cues.dart';
import '../engine/entities.dart';
import '../engine/models.dart';

const _leet = {'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b', '@': 'a', r'$': 's', '!': 'i', '|': 'l'};

/// Brand names as they appear in text, lower case without spaces.
const Map<String, String> brandWords = {
  'maybank': 'Maybank', 'maybank2u': 'Maybank', 'cimb': 'CIMB', 'publicbank': 'Public Bank', 'rhb': 'RHB',
  'hongleong': 'Hong Leong Bank', 'ambank': 'AmBank', 'bankislam': 'Bank Islam', 'bsn': 'BSN',
  'touchngo': "Touch 'n Go", 'tng': "Touch 'n Go", 'boost': 'Boost', 'grabpay': 'Grab', 'grab': 'Grab',
  'shopee': 'Shopee', 'shopeepay': 'Shopee', 'lazada': 'Lazada', 'poslaju': 'Pos Malaysia', 'posmalaysia': 'Pos Malaysia',
  'jtexpress': 'J&T Express', 'dhl': 'DHL', 'ninjavan': 'Ninja Van', 'lhdn': 'LHDN', 'hasil': 'LHDN', 'jpj': 'JPJ',
  'pdrm': 'PDRM', 'polis': 'PDRM', 'kwsp': 'KWSP', 'epf': 'KWSP', 'myeg': 'MyEG', 'banknegara': 'Bank Negara',
  'bnm': 'Bank Negara', 'paypal': 'PayPal', 'apple': 'Apple', 'icloud': 'Apple', 'microsoft': 'Microsoft',
  'facebook': 'Facebook', 'instagram': 'Facebook', 'whatsapp': 'WhatsApp', 'telegram': 'Telegram',
  'netflix': 'Netflix', 'tnb': 'TNB', 'unifi': 'Unifi', 'celcom': 'Celcom', 'maxis': 'Maxis', 'digi': 'Digi',
  'mcmc': 'MCMC', 'kastam': 'Kastam', 'perkeso': 'PERKESO', 'socso': 'PERKESO',
};

const _ambiguous = {'boost', 'grab', 'apple', 'hasil', 'polis', 'digi', 'epf', 'unifi', 'maxis'};

final _token = RegExp(r'[A-Za-z0-9@$!|]+');
final _disguised = RegExp(r'[a-z][0-9@$!|]+[a-z]|^[0-9@$!|][a-z]{2,}|[a-z]{2,}[0-9@$!|]$', caseSensitive: false);

/// Undoes number-for-letter swaps ("m4yb4nk", "p0s laju") one character for
/// one character, so positions in the result match the original text.
String deLeet(String text) {
  return text.replaceAllMapped(_token, (m) {
    final w = m.group(0)!;
    if (!_disguised.hasMatch(w) || RegExp(r'^\d+$').hasMatch(w)) return w;
    if (RegExp(r'^(rm|usd|myr)\d', caseSensitive: false).hasMatch(w)) return w;
    return w.split('').map((c) => _leet[c] ?? c).join();
  });
}

/// Findings for disguised spellings: brand names written with numbers, and
/// cue words that only show up once the spelling is undone.
List<Finding> disguisedSpellingFindings(String text) {
  final clean = deLeet(text);
  if (clean == text) return const [];
  final changed = <(int, int)>[];
  for (final m in _token.allMatches(text)) {
    if (clean.substring(m.start, m.end) != m.group(0)) changed.add((m.start, m.end));
  }
  final out = <Finding>[];
  final tokens = _token.allMatches(clean).toList();
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    final isChanged = changed.any((c) => c.$1 == t.start);
    if (!isChanged) continue;
    final one = t.group(0)!.toLowerCase().replaceAll('i', 'l');
    final candidates = <(String, int)>[
      (t.group(0)!.toLowerCase(), t.end),
      (one, t.end),
      if (i + 1 < tokens.length) ('${t.group(0)!}${tokens[i + 1].group(0)!}'.toLowerCase(), tokens[i + 1].end),
      if (i > 0) ('${tokens[i - 1].group(0)!}${t.group(0)!}'.toLowerCase(), t.end),
    ];
    for (final (w, end) in candidates) {
      final brand = brandWords[w];
      if (brand == null) continue;
      out.add(Finding(
        category: CueCategory.obfuscation,
        title: 'Disguised brand name',
        explanation: '"${text.substring(t.start, end)}" spells $brand with numbers or symbols. Scammers do this to get past spam filters; real companies never do.',
        weight: 14,
        start: t.start,
        end: end,
        tool: 'Spelling normaliser',
      ));
      break;
    }
  }
  final before = detectCues(text).map((f) => f.title).toSet();
  for (final f in detectCues(clean)) {
    if (before.contains(f.title) || f.start == null) continue;
    if (!changed.any((c) => f.start! < c.$2 && f.end! > c.$1)) continue;
    out.add(Finding(
      category: f.category,
      title: f.title,
      explanation: '${f.explanation} The words were disguised with numbers or symbols.',
      weight: f.weight,
      start: f.start,
      end: f.end,
      tool: 'Spelling normaliser',
    ));
    before.add(f.title);
  }
  return out;
}

final _ewallet = RegExp(
    r"\b(touch ?'?n ?go|tng|boost|grabpay|shopeepay|duitnow|bigpay|mae)( e-?wallet)?( id| account| no\.?| number)?\s*[:\-]?\s*((?:\+?6?0)1\d[\s-]?\d{3,4}[\s-]?\d{4}|[A-Za-z0-9]{6,20})",
    caseSensitive: false);

/// E-wallet IDs and named brands, which the core extractor does not cover.
List<Entity> extraEntities(String text) {
  final core = extractEntities(text);
  bool overlaps(int s, int e) => core.any((x) => s < x.end && e > x.start);
  final out = <Entity>[];
  for (final m in _ewallet.allMatches(text)) {
    final id = m.group(4)!;
    if (!RegExp(r'\d').hasMatch(id)) continue;
    final s = m.start + m.group(0)!.lastIndexOf(id);
    out.add(Entity(EntityType.ewallet, '${m.group(1)}: ${id.trim()}', s, s + id.length));
  }
  final seen = <String>{};
  final words = RegExp(r'[A-Za-z0-9]+').allMatches(text).toList();
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final pair = i + 1 < words.length && words[i + 1].start == w.end + 1 ? words[i + 1] : null;
    String? brand;
    var end = w.end;
    if (pair != null && brandWords['${w.group(0)}${pair.group(0)}'.toLowerCase()] != null) {
      brand = brandWords['${w.group(0)}${pair.group(0)}'.toLowerCase()];
      end = pair.end;
    } else {
      final single = w.group(0)!;
      brand = brandWords[single.toLowerCase()];
      // Common English words only count when written as a name.
      if (brand != null && _ambiguous.contains(single.toLowerCase()) && single[0] != single[0].toUpperCase()) brand = null;
    }
    if (brand == null || overlaps(w.start, end) || out.any((x) => w.start < x.end && end > x.start) || !seen.add(brand)) continue;
    out.add(Entity(EntityType.brand, brand, w.start, end));
  }
  return out;
}
