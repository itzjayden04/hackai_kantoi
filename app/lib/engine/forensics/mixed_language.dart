import '../models.dart';

/// Malaysian messages often mix English, Malay, Chinese and Tamil in one line
/// ("Bro, your akaun kena freeze, cepat bayar ya"). This finds which languages
/// a message uses and adds scam phrases in Chinese, Tamil and colloquial Malay
/// that the English and Malay rules in cues.dart do not cover.

final _malayWords = RegExp(
  r'\b(anda|awak|kamu|saya|kami|sila|untuk|dengan|dan|ini|itu|akan|telah|sudah|belum|boleh|tak|tidak|nak|mahu|kena|cepat|segera|duit|wang|bayar|akaun|hari|esok|terima kasih|tahniah|percuma|hadiah|jangan|lagi|ya|lah|kan|je|dah|pun|apa|bila|mana)\b',
  caseSensitive: false,
);
final _englishWords = RegExp(
  r'\b(hello|hi|the|you|your|is|are|to|and|for|please|this|that|with|have|will|now|click|account|pay|money|today)\b',
  caseSensitive: false,
);
final _cjk = RegExp(r'[一-鿿]');
final _tamil = RegExp(r'[஀-௿]');

/// Languages found in [text], most used first.
List<String> detectLanguages(String text) {
  final counts = <String, int>{
    'English': _englishWords.allMatches(text).length,
    'Malay': _malayWords.allMatches(text).length,
    'Chinese': _cjk.allMatches(text).length ~/ 2,
    'Tamil': _tamil.allMatches(text).length ~/ 3,
  };
  final out = counts.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
  return out.map((e) => e.key).toList();
}

class _Rule {
  final CueCategory category;
  final RegExp pattern;
  final int weight;
  final String title;
  final String explanation;
  _Rule(this.category, String p, this.weight, this.title, this.explanation)
      : pattern = RegExp(p, caseSensitive: false, unicode: true);
}

final List<_Rule> _rules = [
  // Chinese (Simplified and Traditional)
  _Rule(CueCategory.credentials, r'(验证码|驗證碼|密码|密碼|一次性密码|OTP码|网银|網銀)', 14, 'Asks for secret codes',
      'The message asks about a verification code, password or online banking login (written in Chinese). No real bank asks for these.'),
  _Rule(CueCategory.payment, r'(转账|轉賬|汇款|匯款|付款|手续费|手續費|保证金|保證金|解冻费|解凍費)', 8, 'Money is mentioned',
      'The message asks you to transfer money or pay a fee (written in Chinese).'),
  _Rule(CueCategory.authority, r'(警察|警方|警官|法院|国家银行|國家銀行|税务局|稅務局|海关|海關)', 9, 'Claims authority',
      'The message claims to be police, a court, the tax office or customs (written in Chinese).'),
  _Rule(CueCategory.fear, r'(洗钱|洗錢|逮捕|通缉|通緝|冻结|凍結|违法|違法)', 10, 'Threat or penalty',
      'The message threatens arrest, money-laundering charges or a frozen account (written in Chinese).'),
  _Rule(CueCategory.investment, r'(保证回报|保證回報|高回报|高回報|稳赚|穩賺|投资群|投資群|兼职|兼職|刷单|刷單)', 14, 'Investment or task scheme',
      'The message promises guaranteed returns or easy part-time tasks (written in Chinese).'),
  _Rule(CueCategory.impersonation, r'(包裹|快递|快遞).{0,20}(扣留|未付|失败|失敗|费用|費用)', 12, 'Parcel problem',
      'The message says a parcel is held until you pay (written in Chinese).'),
  // Tamil
  _Rule(CueCategory.credentials, r'(ஓடிபி|கடவுச்சொல்|சரிபார்ப்பு குறியீடு)', 14, 'Asks for secret codes',
      'The message asks for a code or password (written in Tamil). No real bank asks for these.'),
  _Rule(CueCategory.payment, r'(பணம் அனுப்ப|கட்டணம்|பணப் பரிமாற்றம்)', 8, 'Money is mentioned',
      'The message asks you to send money or pay a fee (written in Tamil).'),
  _Rule(CueCategory.authority, r'(காவல்துறை|போலீஸ்|நீதிமன்றம்)', 9, 'Claims authority',
      'The message claims to be police or a court (written in Tamil).'),
  // Colloquial Malay and Manglish the main rules miss
  _Rule(CueCategory.fear, r'\b(akaun (anda |awak |kamu )?(kena|akan|telah|dah) (freeze|beku|block|sekat|tutup)|kena tangkap|masuk lokap)\b', 10,
      'Threat or penalty', 'The message says your account will be frozen or you will be arrested (in colloquial Malay).'),
  _Rule(CueCategory.urgency, r'\b(cepat sikit|lekas|sekarang juga|before (pukul|jam) \d+|hari ni je|hari ini sahaja)\b', 8, 'Rushes you',
      'The message rushes you to act right now (in colloquial Malay).'),
  _Rule(CueCategory.reward, r'\b(untung (besar|lumayan)|duit (senang|mudah)|kaya cepat|easy money|confirm untung|sure (win|untung))\b', 12,
      'Too-good reward', 'Promises of easy or guaranteed money are bait (in colloquial Malay or Manglish).'),
];

class LanguageScan {
  final List<String> languages;
  final List<Finding> findings;
  const LanguageScan(this.languages, this.findings);
  bool get mixed => languages.length > 1;
}

/// Finds the languages used and scam phrases in Chinese, Tamil and
/// colloquial Malay. [existing] lets it skip a cue the main rules already
/// caught at the same place.
LanguageScan scanLanguages(String text, {List<Finding> existing = const []}) {
  final langs = detectLanguages(text);
  final out = <Finding>[];
  final titles = existing.map((f) => f.title).toSet();
  for (final r in _rules) {
    final m = r.pattern.firstMatch(text);
    if (m == null) continue;
    out.add(Finding(
      category: r.category,
      title: r.title,
      explanation: r.explanation,
      // A cue already found in another language only adds a little.
      weight: titles.contains(r.title) ? 1 : r.weight,
      start: m.start,
      end: m.end,
      tool: 'Mixed-language reader',
    ));
  }
  return LanguageScan(langs, out);
}
