import '../models.dart';

/// Look-alike letters from other alphabets that scammers swap into brand names
/// ("Маybank" with a Cyrillic М, "ΡDRM" with a Greek Ρ). Every entry maps one
/// UTF-16 unit to one ASCII letter, so folding keeps text positions intact.
const Map<String, String> confusables = {
  // Cyrillic capitals
  'А': 'a', 'В': 'b', 'Е': 'e', 'Ё': 'e', 'К': 'k', 'М': 'm', 'Н': 'h', 'О': 'o', 'Р': 'p', 'С': 'c', 'Т': 't',
  'Х': 'x', 'У': 'y', 'Ѕ': 's', 'І': 'i', 'Ї': 'i', 'Ј': 'j', 'Ԛ': 'q', 'Ԝ': 'w', 'Ӏ': 'l',
  // Cyrillic small
  'а': 'a', 'в': 'b', 'е': 'e', 'ё': 'e', 'к': 'k', 'м': 'm', 'н': 'h', 'о': 'o', 'р': 'p', 'с': 'c', 'т': 't',
  'х': 'x', 'у': 'y', 'ѕ': 's', 'і': 'i', 'ї': 'i', 'ј': 'j', 'һ': 'h', 'ԁ': 'd', 'ԛ': 'q', 'ԝ': 'w', 'ӏ': 'l',
  'ո': 'n', 'ս': 'u', 'ɡ': 'g', 'ⅼ': 'l', 'ǀ': 'l', 'ı': 'i', 'ℓ': 'l', 'ⅰ': 'i',
  // Greek capitals
  'Α': 'a', 'Β': 'b', 'Ε': 'e', 'Ζ': 'z', 'Η': 'h', 'Ι': 'i', 'Κ': 'k', 'Μ': 'm', 'Ν': 'n', 'Ο': 'o', 'Ρ': 'p',
  'Τ': 't', 'Υ': 'y', 'Χ': 'x',
  // Greek small
  'α': 'a', 'β': 'b', 'γ': 'y', 'ε': 'e', 'ι': 'i', 'κ': 'k', 'ν': 'v', 'ο': 'o', 'ρ': 'p', 'τ': 't', 'υ': 'u',
  'χ': 'x', 'ω': 'w',
};

/// Number and symbol swaps ("m4yb4nk", "p0slaju").
const Map<String, String> leet = {
  '0': 'o', '1': 'l', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b', '9': 'g', '@': 'a', r'$': 's', '!': 'i', '|': 'l',
};

String _foldChar(String c, {bool oneAsI = false, bool useLeet = true}) {
  final u = c.codeUnitAt(0);
  // Full-width Latin letters (ｍａｙｂａｎｋ).
  if (u >= 0xFF21 && u <= 0xFF3A) return String.fromCharCode(u - 0xFF21 + 0x61);
  if (u >= 0xFF41 && u <= 0xFF5A) return String.fromCharCode(u - 0xFF41 + 0x61);
  final h = confusables[c];
  if (h != null) return h;
  if (useLeet) {
    if (oneAsI && (c == '1' || c == '|')) return 'i';
    final l = leet[c];
    if (l != null) return l;
  }
  final low = c.toLowerCase();
  return low.length == 1 ? low : c;
}

/// Folds look-alike letters (and, by default, number swaps) into plain ASCII,
/// one character for one character, so positions still line up.
String foldConfusables(String s, {bool oneAsI = false, bool useLeet = true}) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    b.write(_foldChar(s[i], oneAsI: oneAsI, useLeet: useLeet));
  }
  return b.toString();
}

/// The readings a disguised word could have: "c1mb" reads as "clmb" or "cimb".
Set<String> skeletons(String s) => {foldConfusables(s), foldConfusables(s, oneAsI: true)};

bool _isAsciiLetter(int r) => (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);

/// True when a word uses look-alike letters or number swaps rather than plain
/// letters.
bool isDisguised(String word) {
  var letters = 0, swaps = 0;
  for (var i = 0; i < word.length; i++) {
    final c = word[i];
    final u = c.codeUnitAt(0);
    if (_isAsciiLetter(u)) {
      letters++;
    } else if (confusables.containsKey(c) || (u >= 0xFF21 && u <= 0xFF5A)) {
      swaps++;
    } else if (leet.containsKey(c)) {
      swaps++;
    }
  }
  return swaps > 0 && letters > 0 && letters + swaps >= 3;
}

/// Brand names as people write them in messages, folded to plain letters.
/// Two-word names are matched with the space removed.
const Map<String, String> textBrands = {
  'maybank': 'Maybank', 'maybank2u': 'Maybank', 'cimb': 'CIMB', 'publicbank': 'Public Bank', 'hongleong': 'Hong Leong Bank',
  'ambank': 'AmBank', 'bankislam': 'Bank Islam', 'touchngo': "Touch 'n Go", 'tngdigital': "Touch 'n Go",
  'poslaju': 'Pos Malaysia', 'posmalaysia': 'Pos Malaysia', 'jtexpress': 'J&T Express', 'ninjavan': 'Ninja Van',
  'lhdn': 'LHDN', 'hasil': 'LHDN', 'pdrm': 'PDRM', 'polis': 'PDRM', 'police': 'PDRM', 'kwsp': 'KWSP', 'shopee': 'Shopee',
  'lazada': 'Lazada', 'myeg': 'MyEG', 'banknegara': 'Bank Negara', 'paypal': 'PayPal', 'netflix': 'Netflix',
  'grab': 'Grab', 'boost': 'Boost', 'gdex': 'GDEX', 'bsn': 'BSN', 'rhb': 'RHB', 'jpj': 'JPJ',
};

/// Risk words that scammers disguise to slip past filters ("0TP", "p4yment").
const Set<String> _riskWords = {
  'otp', 'tac', 'pin', 'password', 'akaun', 'account', 'verify', 'parcel', 'bayar', 'transfer', 'deposit', 'profit',
  'prize', 'hadiah', 'login', 'bank', 'payment', 'urgent', 'segera', 'claim', 'reward', 'bonus', 'crypto', 'usdt',
  'guaranteed', 'withdraw', 'fee', 'saman', 'waran', 'warrant', 'arrest', 'frozen', 'telegram', 'whatsapp',
};

final _token = RegExp(r"[\p{L}\p{N}@$!|]+", unicode: true);

class DisguisedWord {
  final int start;
  final int end;
  final String raw;
  final String reads;
  final String? brand;
  /// Whether "1" was read as "i" (c1mb) rather than "l" (pay1oad).
  final bool oneAsI;
  const DisguisedWord(this.start, this.end, this.raw, this.reads, this.brand, this.oneAsI);
}

/// Finds words written with look-alike letters or number swaps that read as a
/// brand name or a scam keyword.
List<DisguisedWord> findDisguisedWords(String text) {
  final out = <DisguisedWord>[];
  final tokens = _token.allMatches(text).toList();
  for (var i = 0; i < tokens.length; i++) {
    final m = tokens[i];
    final raw = m.group(0)!;
    // Single words, then a word joined with the next ("P0s L4ju").
    final candidates = <(int, int, String)>[
      (m.start, m.end, raw),
      if (i + 1 < tokens.length && tokens[i + 1].start - m.end <= 2)
        (m.start, tokens[i + 1].end, raw + tokens[i + 1].group(0)!),
    ];
    for (final (s, e, word) in candidates) {
      if (!isDisguised(word)) continue;
      final plain = word.toLowerCase();
      if (textBrands.containsKey(plain)) continue; // e.g. "Maybank2u" written normally
      String? hit;
      String? brand;
      var oneAsI = false;
      for (final asI in const [false, true]) {
        final sk = foldConfusables(word, oneAsI: asI);
        if (textBrands.containsKey(sk)) {
          hit = sk;
          brand = textBrands[sk];
          oneAsI = asI;
          break;
        }
        if (hit == null && _riskWords.contains(sk)) {
          hit = sk;
          oneAsI = asI;
        }
      }
      if (hit == null) continue;
      // Plain numbers glued to a currency are normal ("RM50"), not disguise.
      if (brand == null && RegExp(r'^(rm|usd|myr)\d').hasMatch(plain)) continue;
      out.add(DisguisedWord(s, e, text.substring(s, e), hit, brand, oneAsI));
      if (e != m.end) i++; // the joined word used the next token
      break;
    }
  }
  return out;
}

/// The text with disguised words replaced by what they read as, keeping the
/// same length so cue spans still point at the original characters.
String unmaskText(String text) {
  final words = findDisguisedWords(text);
  if (words.isEmpty) return text;
  final b = StringBuffer();
  var pos = 0;
  for (final w in words) {
    b.write(text.substring(pos, w.start));
    final folded = foldConfusables(w.raw, oneAsI: w.oneAsI);
    b.write(folded.length == w.raw.length ? folded : w.raw);
    pos = w.end;
  }
  b.write(text.substring(pos));
  return b.toString();
}

/// Findings for brand names and keywords written in disguise.
List<Finding> disguisedWordFindings(String text) {
  final out = <Finding>[];
  final seen = <String>{};
  for (final w in findDisguisedWords(text)) {
    if (!seen.add(w.reads)) continue;
    out.add(Finding(
      category: CueCategory.obfuscation,
      title: w.brand != null ? 'Disguised brand name' : 'Disguised spelling',
      explanation: w.brand != null
          ? '"${w.raw}" is written with look-alike letters or numbers to read as ${w.brand}. Real companies spell their own name normally.'
          : '"${w.raw}" is spelled with look-alike letters or numbers to read as "${w.reads}", a trick to slip past spam filters.',
      weight: w.brand != null ? 14 : 8,
      start: w.start,
      end: w.end,
      tool: 'Obfuscation check',
    ));
  }
  return out;
}
