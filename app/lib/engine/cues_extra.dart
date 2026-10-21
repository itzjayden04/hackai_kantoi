import 'models.dart';

/// Extra cue rules: Chinese and Tamil scam phrases, more Malay phrasing, and
/// the fake-officer (Macau scam) call script. Included by [detectCues].
class _Rule {
  final CueCategory category;
  final RegExp pattern;
  final int weight;
  final String title;
  final String explanation;
  _Rule(this.category, String pattern, this.weight, this.title, this.explanation)
      : pattern = RegExp(pattern, caseSensitive: false, unicode: true),
        requires = null;
  /// When set, the rule only counts if this also matches somewhere in the text.
  final RegExp? requires;
  _Rule.re(this.category, this.pattern, this.weight, this.title, this.explanation, {this.requires});
}

RegExp _re(String p) => RegExp(p, caseSensitive: false, unicode: true);

// "Can you send me money" from someone you know: the hijacked-account and
// "new number" scam. Each piece is mild alone; together they are the script.
const _money = r'(money|duit|wang|cash|fund|rm ?\d+|\d+ ?(ringgit|rm|k)\b|myr ?\d+|\$ ?\d+)';
const _askVerb = r'(lend|pinjam(kan)?|borrow|transfer|tf|bank ?in|send|give|bagi|hantar|tng|duit ?now|top ?up)';
// Not when the writer says they paid or will pay ("I'll transfer you").
const _notMine = r"(?<!\b(i|i'll|i will|i can|i've|we|we'll|aku|saya|dah|sudah|already|just) )";
const _please = r'(can|could|boleh|bole|leh|pls|plz|please|tolong|help|mintak|minta|kindly|need (you )?to)';
final _askRe = _re('\\b$_askVerb (me|aku|saya|us|kat aku|to me)\\b.{0,30}$_money'
    '|\\b$_please\\b.{0,25}$_notMine\\b$_askVerb\\b.{0,30}$_money'
    '|\\b(send|transfer|tf|tng|bank ?in) (me|aku|saya) (rm ?)?\\d{2,6}\\b'
    '|$_notMine\\b(need|perlu|nak|want|mau|desperately need)\\b.{0,15}\\b(money|duit|cash|wang|rm ?\\d+)'
    '|\\b(lend me|pinjam(kan)? (aku|saya|sikit|kejap|sekejap|dulu)|borrow (some|a bit|rm|money|\\d)|can i borrow|help me with (rm ?)?\\d{2,})'
    '|$_money.{0,20}\\b(lend|pinjam|borrow|bank ?in)\\b( (me|aku|saya)|\\?)');
// Money mentioned at all: the emergency, account and "can't call" cues only
// count alongside it, so "stuck in traffic" stays a normal message.
final _moneyAnyRe = _re('$_money|\\b(transfer|bank ?in|bayar|pay|pinjam|borrow|lend|tng|duit ?now)\\b');
final _urgentRe = _re(r'\b(urgent(ly)?|asap|quick(ly)?|fast|cepat|segera|now|sekarang|right away|immediately|today|hari ni|harini|terdesak|desperate(ly)?|kejap|sekejap|jap)\b');
final _emergencyRe = _re(r"\b(emergency|kecemasan|darurat|accident|kemalangan|hospital|stuck|tersangkut|terkandas|stranded|in trouble|dalam masalah|detained|kena tahan|lost my (wallet|purse|card|bag)|dompet (aku |saya )?hilang|card (is |kena )?(blocked|block|frozen))\b");
final _payBackRe = _re(r"\b(pay (you )?back|bayar balik|ganti balik|pulangkan|return (it|you|the money)|i('ll| will) return|nanti (aku|saya|i) (bayar|ganti|pulang)|settle (it )?(later|tmr|tomorrow)|i pay (you )?(tmr|tomorrow|later)|esok (aku|saya|i) bayar)\b");
const _banks = r'(maybank|mbb|cimb|public ?bank|pbb|rhb|hong ?leong|hlb|ambank|bsn|bank islam|bank rakyat|affin|alliance|ocbc|uob|hsbc|agro ?bank|muamalat|gx ?bank)';
final _accountRe = _re('\\b(acc(oun)?t?|akaun|a/c|acc no|account no)\\b.{0,25}\\d[\\d -]{6,18}\\d'
    '|\\b\\d{8,16}\\b.{0,25}\\b$_banks\\b|\\b$_banks\\b.{0,25}\\b\\d{8,16}\\b'
    '|\\b(to|ke|into) (this|my|the|that) (account|akaun|acc)\\b|\\b(account|akaun) (ni|ini|ini ya)\\b');
final _ewalletRe = _re(r"\b(tng|touch ?'?n ?go|e-?wallet|duit ?now|grab ?pay|shopee ?pay|big ?pay|boost (e-?wallet|app)|reload)\b");
/// "New number" and "lost my phone" lines, also used by [detectCues].
final newNumberCue = _re(r"\b(this is my new (number|no)|(my |guna )?(nombor|no\.?|number|nmbr) (baru|lain)|new (phone )?(number|no\.?)|i changed my number|other number|(my )?(temp|temporary) (number|phone)|lost my phone|(broke|spoilt|spoiled) my phone|(hand)?phone( (aku|saya|i|my))? (rosak|hilang|spoil(ed|t)?|broken|lost|stolen|kena curi)|\bhp (aku |saya )?(rosak|hilang)|it'?s me,? (your|ur))\b");
final _cantCallRe = _re(r"\b(can'?t|cannot|cant|unable to|tak (boleh|dapat|leh)|x (boleh|leh)) (talk|call|answer|pick up|angkat|cakap|bercakap|telefon|voice ?call)\b|\b(don'?t|do not|dont|jangan|no need to) (call|telefon|phone) (me|aku|saya)\b|\b(text|mesej|msg|whatsapp|chat) (only|je|sahaja|saja)\b|\b(in a meeting|mic (rosak|broken|spoil))\b");
final _secrecyRe = _re(r"\b(don'?t|do not|dont|jangan) (tell|beritahu|bagitahu|bagitau|cakap|inform|bagi tau)\b|\bkeep (it|this) (between us|secret|quiet)\b|\brahsia\b");
final _giftCardRe = _re(r'\b(gift ?cards?|google play (cards?|codes?|gift)|itunes|steam (cards?|wallet)|razer gold|apple gift)\b');
final _codeRe = _re(r"\b(accidentally|by mistake|wrongly|tersalah|silap|terhantar)\b.{0,30}\b(code|kod|otp|tac|pin)\b|\b(code|kod|otp|tac)\b.{0,40}\b(by mistake|accidentally|tersalah|silap)\b|\b(send|forward|hantar|bagi|give|screenshot)\b.{0,15}\b(it|that|the|6[- ]digit|kod|code|otp|tac)( code| kod)?\b.{0,15}\b(to me|kat aku|kepada saya|back to me|balik)\b");
final _amountRe = _re(r'\b(?:rm|myr) ?(\d[\d,]*)|\b(\d[\d,]*) ?(?:ringgit|rm)\b');

/// The pieces of a money request found in one message.
class MoneyAsk {
  final bool ask, urgent, emergency, payBack, account, ewallet, newNumber, cantCall, secrecy, giftCard, code;
  /// The largest amount named, in ringgit.
  final int? amount;
  const MoneyAsk({
    this.ask = false,
    this.urgent = false,
    this.emergency = false,
    this.payBack = false,
    this.account = false,
    this.ewallet = false,
    this.newNumber = false,
    this.cantCall = false,
    this.secrecy = false,
    this.giftCard = false,
    this.code = false,
    this.amount,
  });

  /// Asks the reader for money, a gift card or a code.
  bool get any => ask || code || (giftCard && urgent);
  bool get pressure => urgent || emergency;

  /// How many of the classic "hijacked friend" extras appear.
  int get extras => [account || ewallet, newNumber, cantCall, secrecy, giftCard].where((x) => x).length;

  /// The risk this money request alone carries, or null when there is none.
  RiskLevel? get level {
    if (code) return RiskLevel.danger;
    if (!any) return null;
    final RiskLevel l;
    if (extras >= 2 && pressure) {
      l = RiskLevel.danger;
    } else if (extras >= 1 && pressure || extras >= 2 || giftCard) {
      l = RiskLevel.suspicious;
    } else {
      l = RiskLevel.caution;
    }
    // Friends often ask each other for small change.
    final small = amount != null && amount! <= 50;
    if (small && l == RiskLevel.suspicious && extras < 2 && !giftCard) return RiskLevel.caution;
    return l;
  }

  /// Worth a heads-up notification even at the caution level.
  bool get worthNotice => code || (any && (pressure || payBack || extras > 0));

  /// Short reasons, most telling first.
  List<String> get reasons => [
        if (code) 'Asks you to pass on a code',
        if (giftCard) 'Wants gift cards',
        if (newNumber) 'Says they have a new number or lost their phone',
        if (cantCall) "Says they can't talk on the phone",
        if (account) 'Gives an account to pay into',
        if (ewallet && !account) 'Wants an e-wallet transfer',
        if (secrecy) 'Asks you to keep it quiet',
        if (ask) 'Asks you for money',
        if (emergency) 'Sudden emergency story',
        if (urgent && !emergency) 'Wants it fast',
        if (payBack) 'Promises to pay you back',
      ];
}

/// Looks for a request for money, gift cards or codes in [text].
MoneyAsk moneyAskIn(String text) {
  int? amount;
  for (final m in _amountRe.allMatches(text)) {
    final v = int.tryParse((m.group(1) ?? m.group(2) ?? '').replaceAll(',', ''));
    if (v != null && (amount == null || v > amount)) amount = v;
  }
  final ask = _askRe.hasMatch(text);
  final gift = _giftCardRe.hasMatch(text);
  return MoneyAsk(
    ask: ask,
    urgent: _urgentRe.hasMatch(text),
    emergency: _emergencyRe.hasMatch(text),
    payBack: _payBackRe.hasMatch(text),
    account: _accountRe.hasMatch(text),
    ewallet: _ewalletRe.hasMatch(text),
    newNumber: newNumberCue.hasMatch(text),
    cantCall: _cantCallRe.hasMatch(text),
    secrecy: _secrecyRe.hasMatch(text),
    giftCard: gift && (ask || RegExp(r'\b(buy|beli|send|hantar|code|kod)\b', caseSensitive: false).hasMatch(text)),
    code: _codeRe.hasMatch(text),
    amount: amount,
  );
}

const _officer = 'Fake officer script';
const _officerWhy = 'This is the script of the "fake police or bank officer" scam. Real officers never ask you to move money or keep it secret.';

final List<_Rule> _extraRules = [
  // Money requests from someone you know (hijacked or "new number" accounts).
  _Rule.re(CueCategory.payment, _askRe, 12, 'Asks you for money',
      'Scammers who take over a friend\'s account, or pretend to have a new number, ask for money straight away. Call the person on their usual number first.'),
  _Rule.re(CueCategory.urgency, _emergencyRe, 8, 'Sudden emergency story',
      'A sudden emergency is used so you send money before you stop to check.', requires: _moneyAnyRe),
  _Rule.re(CueCategory.payment, _accountRe, 10, 'Gives an account to pay into',
      'Being sent an account number to pay is how the money reaches a scammer or a mule account.', requires: _moneyAnyRe),
  _Rule.re(CueCategory.payment, _ewalletRe, 4, 'E-wallet transfer',
      'E-wallet and DuitNow transfers are instant and hard to reverse.'),
  _Rule.re(CueCategory.secrecy, _cantCallRe, 12, "Can't talk on the phone",
      'An excuse not to talk on the phone stops you from hearing that it is not really them.', requires: _moneyAnyRe),
  _Rule.re(CueCategory.credentials, _codeRe, 26, 'Wants your code',
      'The "I sent you a code by mistake" trick is how WhatsApp and bank accounts are stolen. Never pass on a code.'),
  _Rule(CueCategory.payment, r'\b(start (with|from) (only |just )?(rm|\$) ?\d+|min(imum)? (deposit|investment|modal|top ?up) (of )?(rm|\$)? ?\d+|modal (serendah|hanya|cuma) rm ?\d+)', 8,
      'Asks for a first deposit', 'Investment and job scams start with a small deposit, then ask for more.'),
  _Rule(CueCategory.urgency, '$_money.{0,40}\\b(quick(ly)?|fast|now|sekarang|right away|cepat|jap)\\b|\\b(quick(ly)?|fast)\\b.{0,30}$_money', 8,
      'Rushes you', 'Scammers rush you so you act before you think or check with someone.'),
  // Fake officer (Macau scam) call script, in English and Malay.
  _Rule(CueCategory.fear, r'\b(your|anda|awak)?\s?(ic|mykad|identity card|kad pengenalan|bank account|akaun bank)\b.{0,40}\b(linked|involved|used|terlibat|digunakan|dikaitkan)\b.{0,40}\b(money laundering|laundering|pengubahan wang haram|drug|dadah|fraud|penipuan|crime|jenayah|syndicate|sindiket)\b', 22,
      _officer, _officerWhy),
  _Rule(CueCategory.authority, r'\b(bank negara|bnm)\b.{0,30}\b(officer|pegawai|department|jabatan|investigation|siasatan)\b|\b(officer|pegawai)\b.{0,20}\b(bank negara|bnm)\b', 14,
      'Claims to be from Bank Negara', 'Bank Negara Malaysia never calls members of the public about their accounts or asks for money.'),
  _Rule(CueCategory.fear, r'\b(arrest warrant|waran tangkap|court (case|order|summons)|kes mahkamah|saman mahkamah|you will be arrested|anda akan ditangkap)\b', 14,
      _officer, _officerWhy),
  _Rule(CueCategory.payment, r'\b(transfer|move|pindahkan|masukkan)\b.{0,40}\b(for (investigation|verification|audit)|untuk (siasatan|pengesahan)|to (clear|prove) your name|bersihkan nama)\b', 18,
      _officer, _officerWhy),
  _Rule(CueCategory.secrecy, r"\b(don'?t|do not|jangan) (hang up|letak (telefon|panggilan)|end the call)\b|\b(call|panggilan) (will be )?(transferred|disambungkan) to (the )?(police|pdrm|officer)", 10,
      _officer, _officerWhy),
  // More Malay phrasing.
  _Rule(CueCategory.link, r'\b(klik|tekan) (pautan|link|di sini)\b', 8,
      'Asks you to tap a link', 'Messages that push you to tap a link are the usual way to steal logins.'),
  _Rule(CueCategory.reward, r'\b(anda (telah )?menang|tuntut (sekarang|hadiah)|duit raya percuma|baucar percuma|percuma untuk anda)\b', 9,
      'Too-good reward', 'Unexpected prizes or rewards are bait to get your details or a "small fee".'),
  _Rule(CueCategory.payment, r'\b(pinjaman (segera|peribadi|mudah|tanpa (penjamin|dokumen))|loan approved|instant loan|no (guarantor|documents) needed)\b', 10,
      'Easy loan offer', 'Loans offered by message that need an upfront "processing fee" are a common scam.'),
  // Chinese (no word boundaries in Chinese text).
  _Rule(CueCategory.payment, r'转账|汇款|打款', 8, 'Money is mentioned', 'The message asks you to transfer money.'),
  _Rule(CueCategory.payment, r'安全账户|安全帐户|保管账户', 20, 'Asks you to move money to a "safe account"',
      'No police, bank or agency will ever ask you to move your money to a "safe account". This is always a scam.'),
  _Rule(CueCategory.fear, r'洗钱|洗黑钱|逮捕令|通缉|冻结|涉嫌|犯罪', 12, 'Threat or penalty', 'Threats of arrest, money laundering or a frozen account are meant to panic you.'),
  _Rule(CueCategory.authority, r'警察|公安|警方|警官|法院|国家银行|检察', 9, 'Claims authority', 'Claiming to be police, court or bank officials is used to scare you into obeying.'),
  _Rule(CueCategory.credentials, r'验证码|密码|动态码', 14, 'Asks for secret codes', 'No real bank or agency will ever ask for your code or password.'),
  _Rule(CueCategory.secrecy, r'保密|不要告诉|别告诉|不要跟(任何人|家人)', 14, 'Asks for secrecy', 'Being told to keep it secret cuts you off from people who would warn you.'),
  _Rule(CueCategory.urgency, r'立即|马上|立刻|紧急|今天之内|限时', 8, 'Rushes you', 'Scammers rush you so you act before you think.'),
  _Rule(CueCategory.reward, r'中奖|恭喜|奖金|领取', 9, 'Too-good reward', 'Unexpected prizes are bait to get your details or a "small fee".'),
  _Rule(CueCategory.investment, r'高回报|稳赚|保本|零风险|日赚|躺赚|带单|导师', 14, 'Unrealistic returns', 'Guaranteed or very high returns do not exist in legitimate investing.'),
  _Rule(CueCategory.investment, r'兼职|刷单|点赞|做任务', 11, 'Easy-money job offer', 'Paid "like and review" tasks that later need a deposit are a common job scam.'),
  _Rule(CueCategory.impersonation, r'(包裹|快递).{0,20}(费用|扣留|未付|地址)', 12, 'Parcel problem', 'Fake "parcel held, pay a small fee" messages are among the most common scams.'),
  // Tamil.
  _Rule(CueCategory.urgency, r'உடனடியாக|உடனே|இன்றே', 8, 'Rushes you', 'Scammers rush you so you act before you think.'),
  _Rule(CueCategory.authority, r'காவல்துறை|போலீஸ்|நீதிமன்ற|அதிகாரி', 9, 'Claims authority', 'Claiming to be police, court or bank officials is used to scare you into obeying.'),
  _Rule(CueCategory.fear, r'கைது|பணமோசடி|சட்டவிரோத', 12, 'Threat or penalty', 'Threats of arrest or a frozen account are meant to panic you.'),
  _Rule(CueCategory.payment, r'பணம் (அனுப்ப|செலுத்த|மாற்ற)|வங்கி கணக்கு', 8, 'Money is mentioned', 'The message asks you to send money.'),
  _Rule(CueCategory.credentials, r'கடவுச்சொல்|ரகசிய (எண்|குறியீடு)', 14, 'Asks for secret codes', 'No real bank or agency will ever ask for your code or password.'),
  _Rule(CueCategory.reward, r'பரிசு|வென்றுள்ளீர்கள்', 9, 'Too-good reward', 'Unexpected prizes are bait to get your details or a "small fee".'),
  _Rule(CueCategory.secrecy, r'ரகசியமாக|யாரிடமும் சொல்ல', 14, 'Asks for secrecy', 'Being told to keep it secret cuts you off from people who would warn you.'),
];

/// Findings from the extra rules, with spans for highlighting.
List<Finding> detectExtraCues(String text) {
  final out = <Finding>[];
  for (final r in _extraRules) {
    if (r.requires != null && !r.requires!.hasMatch(text)) continue;
    var first = true;
    for (final m in r.pattern.allMatches(text)) {
      out.add(Finding(
        category: r.category,
        title: r.title,
        explanation: r.explanation,
        weight: first ? r.weight : 1,
        start: m.start,
        end: m.end,
        tool: 'Cue detector',
      ));
      first = false;
    }
  }
  return out;
}
