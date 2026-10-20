/// On-device language detection for the languages Malaysian scams use:
/// script ranges for Chinese and Tamil, word counts for Malay and English.
library;

const _malay = {
  'yang', 'dan', 'anda', 'untuk', 'ini', 'itu', 'akan', 'dengan', 'tidak', 'sila', 'akaun', 'kami', 'telah',
  'dalam', 'boleh', 'saya', 'kepada', 'adalah', 'segera', 'bayar', 'encik', 'puan', 'dari', 'hari', 'wang',
  'tuan', 'kerana', 'jika', 'sudah', 'belum', 'lagi', 'mahu', 'nak', 'tak', 'ada', 'kita', 'awak', 'kamu',
  'terima', 'kasih', 'bank', 'pautan', 'klik', 'maklumat', 'nombor', 'bungkusan', 'tahniah', 'jangan', 'sahaja',
  'pada', 'oleh', 'atau', 'juga', 'lah', 'ke', 'di', 'sebelum', 'selepas', 'tarikh', 'bayaran',
};
const _english = {
  'the', 'and', 'you', 'your', 'to', 'is', 'for', 'this', 'that', 'will', 'with', 'not', 'please', 'we', 'have',
  'be', 'are', 'of', 'in', 'on', 'it', 'my', 'me', 'our', 'can', 'if', 'now', 'today', 'click', 'link', 'pay',
  'has', 'been', 'was', 'from', 'at', 'by', 'or', 'all', 'do', 'i', 'a', 'an', 'hi', 'hello', 'dear',
};

/// Languages present in [text], most prominent first, as plain English names.
List<String> detectLanguages(String text) {
  var han = 0, tamil = 0;
  for (final r in text.runes) {
    if ((r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF)) han++;
    if (r >= 0x0B80 && r <= 0x0BFF) tamil++;
  }
  var ms = 0, en = 0;
  final words = RegExp(r"[a-zA-Z']+").allMatches(text.toLowerCase()).map((m) => m.group(0)!).toList();
  for (final w in words) {
    if (_malay.contains(w)) ms++;
    if (_english.contains(w)) en++;
  }
  final scores = <String, int>{};
  if (han >= 2) scores['Chinese'] = han;
  if (tamil >= 2) scores['Tamil'] = tamil ~/ 3;
  final latinHits = ms + en;
  if (latinHits > 0) {
    if (ms >= 2 && ms * 4 >= latinHits) scores['Malay'] = ms * 3;
    if (en >= 2 && en * 4 >= latinHits) scores['English'] = en * 3;
    if (!scores.containsKey('Malay') && !scores.containsKey('English')) {
      scores[ms > en ? 'Malay' : 'English'] = latinHits;
    }
  } else if (words.length >= 3 && scores.isEmpty) {
    scores['English'] = 1;
  }
  final out = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return out.map((e) => e.key).toList();
}
