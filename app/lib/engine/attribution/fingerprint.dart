/// Normalising entities and comparing scripts, pages and icons, so the same
/// scam written slightly differently still lines up.
library;

import '../url_analyzer.dart';

/// Hosting platforms where every customer gets a subdomain, so the full host
/// (not the platform) is the scam site.
const _sharedHosts = {
  'web.app', 'firebaseapp.com', 'vercel.app', 'netlify.app', 'github.io', 'pages.dev', 'blogspot.com',
  'wixsite.com', 'weebly.com', '000webhostapp.com', 'herokuapp.com', 'glitch.me', 'ngrok-free.app',
  'workers.dev', 'square.site', 'webflow.io', 'framer.website', 'my.id', 'carrd.co',
};

/// Brands that matter to Malaysian users (the global ones are left out so the
/// feeds stay local).
const malaysianBrands = {
  'Maybank', 'CIMB', 'Public Bank', 'RHB', 'Hong Leong Bank', 'AmBank', 'Bank Islam', 'BSN', "Touch 'n Go",
  'Boost', 'Grab', 'Shopee', 'Lazada', 'Pos Malaysia', 'J&T Express', 'DHL', 'LHDN', 'JPJ', 'PDRM', 'KWSP',
  'MyEG', 'Bank Negara',
};

/// Malay and local words common in Malaysian scam links.
const _localWords = [
  'bayar', 'akaun', 'hadiah', 'tuntut', 'semak', 'bantuan', 'pinjaman', 'kerja', 'sumbangan', 'cukai', 'saman',
  'bungkusan', 'penghantaran', 'rebat', 'baucar', 'rahmah', 'madani', 'malaysia', 'msia', 'ringgit', 'myr',
  'duitnow', 'fpx', 'mykad', 'touchngo', 'tngo',
];

Uri? _uri(String raw) {
  var s = raw.trim();
  if (!RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(s)) s = 'http://$s';
  final u = Uri.tryParse(s);
  return u == null || u.host.isEmpty ? null : u;
}

/// The host of a link, decoded and without "www.".
String? hostOf(String raw) {
  final u = _uri(raw);
  if (u == null) return null;
  var h = decodeHost(u.host.toLowerCase());
  if (h.startsWith('www.')) h = h.substring(4);
  return h;
}

/// The key a website is stored under: its registered domain, or the full host
/// on shared hosting platforms. Null for official brand websites.
String? domainKey(String raw) {
  final h = hostOf(raw);
  if (h == null || !h.contains('.')) return null;
  if (officialBrandFor(h) != null) return null;
  final reg = registrableDomain(h);
  return _sharedHosts.contains(reg) ? h : reg;
}

/// Phone numbers in international form without "+", e.g. 60123456789.
String phoneKey(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('0')) d = '6$d';
  if (d.startsWith('1') && d.length >= 9 && d.length <= 10) d = '60$d';
  return d;
}

String accountKey(String raw) => raw.replaceAll(RegExp(r'\D'), '');

String walletKey(String raw) {
  final w = raw.trim();
  return w.startsWith('0x') ? w.toLowerCase() : w;
}

String handleKey(String raw) {
  var h = raw.trim().toLowerCase();
  h = h.replaceFirst(RegExp(r'^(https?://)?(www\.)?(t\.me|telegram\.me)/'), '');
  return h.replaceFirst('@', '');
}

/// The brand a host imitates, or null when it is official or unrelated.
String? lookalikeBrand(String host) {
  final h = host.toLowerCase();
  if (officialBrandFor(h) != null) return null;
  final clean = deconfuse(h);
  for (final k in brandKeywords.entries) {
    if (k.key.length >= 4 && clean.contains(k.key) || RegExp('(^|[.-])${k.key}([.-]|\$)').hasMatch(h)) return k.value;
  }
  final label = deconfuse(registrableDomain(h).split('.').first);
  for (final e in brands.entries) {
    for (final d in e.value) {
      final dl = d.split('.').first;
      if (dl.length >= 5 && label != dl && levenshtein(label, dl) <= 2) return e.key;
    }
  }
  return null;
}

/// Whether a link from a global feed is about Malaysia: it imitates a
/// Malaysian brand, sits on a .my domain, or uses Malay scam words.
bool malaysianRelevant(String url) {
  final h = hostOf(url);
  if (h == null) return false;
  if (h.endsWith('.my')) return true;
  final b = lookalikeBrand(h);
  if (b != null && malaysianBrands.contains(b)) return true;
  final low = url.toLowerCase();
  return _localWords.any(low.contains);
}

/// 32-bit FNV-1a, stable across Windows, Android and web.
int fnv32(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    // h * 0x01000193, split so web builds keep full precision.
    h = (h * 0x193 + ((h << 24) & 0xffffffff)) & 0xffffffff;
  }
  return h;
}

/// Replaces the parts of a message that change between victims (links,
/// numbers, amounts, names after greetings) so only the script remains.
String normaliseScript(String text) {
  var t = text.toLowerCase();
  t = t.replaceAll(RegExp(r'(https?://|www\.)\S+'), ' url ');
  t = t.replaceAll(RegExp(r'\b[a-z0-9-]+\.(com|my|net|org|xyz|top|info|link|site|online|shop|club|vip|cc|io|co|me|app|live|store|icu|buzz)\b\S*'), ' url ');
  t = t.replaceAll(RegExp(r'@\w+'), ' handle ');
  t = t.replaceAll(RegExp(r'\b(rm|myr|usdt|usd)\s?\d[\d,.]*'), ' amount ');
  t = t.replaceAll(RegExp(r'\d[\d\s,.-]*'), ' n ');
  t = t.replaceAll(RegExp(r'\b(mr|mrs|ms|miss|encik|puan|cik|dear|hi|hello)\s+[a-z]+'), r' $1 name ');
  t = t.replaceAll(RegExp(r'[^a-z\s]'), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const sketchSize = 64;

/// A bottom-k MinHash sketch of three-word shingles. Two sketches estimate
/// how much of the wording two messages share.
List<int> scriptSketch(String text) {
  final w = normaliseScript(text).split(' ').where((s) => s.isNotEmpty).toList();
  final shingles = <int>{};
  if (w.length < 3) {
    if (w.isNotEmpty) shingles.add(fnv32(w.join(' ')));
  } else {
    for (var i = 0; i + 3 <= w.length; i++) {
      shingles.add(fnv32(w.sublist(i, i + 3).join(' ')));
    }
  }
  final sorted = shingles.toList()..sort();
  return sorted.take(sketchSize).toList();
}

/// Estimated share of wording two sketches have in common, 0 to 1.
double scriptSimilarity(List<int> a, List<int> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final sa = a.toSet(), sb = b.toSet();
  final union = {...sa, ...sb}.toList()..sort();
  final k = union.take(sketchSize).toList();
  final both = k.where((x) => sa.contains(x) && sb.contains(x)).length;
  return both / k.length;
}

/// A 32-bit SimHash of the page's tag sequence: pages built from the same kit
/// get nearly the same number even when the text differs.
int pageShape(String html) {
  final tags = RegExp(r'<\s*([a-zA-Z][a-zA-Z0-9]*)').allMatches(html).map((m) => m.group(1)!.toLowerCase()).toList();
  final v = List<int>.filled(32, 0);
  for (var i = 0; i + 4 <= tags.length; i++) {
    final h = fnv32(tags.sublist(i, i + 4).join('>'));
    for (var bit = 0; bit < 32; bit++) {
      v[bit] += (h >> bit) & 1 == 1 ? 1 : -1;
    }
  }
  var out = 0;
  for (var bit = 0; bit < 32; bit++) {
    if (v[bit] > 0) out |= 1 << bit;
  }
  return out;
}

int hamming32(int a, int b) {
  var x = (a ^ b) & 0xffffffff, n = 0;
  while (x != 0) {
    x &= x - 1;
    n++;
  }
  return n;
}

/// Bits that differ between two hex hashes of the same length.
int hexDistance(String a, String b) {
  if (a.length != b.length) return 999;
  var n = 0;
  for (var i = 0; i < a.length; i++) {
    n += hamming32(int.parse(a[i], radix: 16), int.parse(b[i], radix: 16));
  }
  return n;
}

/// Similarity of two domain names ignoring dashes and look-alike letters, 0 to 1.
double nameSimilarity(String a, String b) {
  final x = deconfuse(a.split('.').first), y = deconfuse(b.split('.').first);
  final m = x.length > y.length ? x.length : y.length;
  if (m == 0) return 0;
  return 1 - levenshtein(x, y) / m;
}

/// A page title with the brand-agnostic noise removed, for "same template".
String titleKey(String t) => t.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), ' ').trim();
