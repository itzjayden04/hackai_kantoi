import 'models.dart';

class _Rule {
  final CueCategory category;
  final RegExp pattern;
  final int weight;
  final String title;
  final String explanation;
  _Rule(this.category, String pattern, this.weight, this.title, this.explanation)
      : pattern = RegExp(pattern, caseSensitive: false, unicode: true);
}

// Patterns cover English plus the Malay and Manglish phrasing Malaysian scams
// commonly use; the app UI stays English.
final List<_Rule> _rules = [
  // Urgency
  _Rule(CueCategory.urgency, r'\b(urgent(ly)?|immediately|right now|asap|segera|cepat|hari ini juga)\b', 8,
      'Rushes you', 'Scammers rush you so you act before you think or check with someone.'),
  _Rule(CueCategory.urgency, r'\b(within|in) (\d+|twenty[- ]four|one|two) ?(hours?|hrs?|minutes?|mins?|jam|minit)\b|\b(last|final) (chance|reminder|warning|notice)\b|\bexpir(e|es|ing|ed) (today|soon|tonight)\b|\btoday only\b|\blimited (time|slots?)\b', 10,
      'Tight deadline', 'A short deadline is a classic pressure tactic. Real banks and agencies give you time.'),
  // Authority / impersonation
  _Rule(CueCategory.authority, r'\b(polis|police|pdrm|bank negara|bnm|lhdn|hasil|mahkamah|court|magistrate|mcmc|jpj|kastam|customs|immigration|imigresen|interpol|officer|pegawai|inspector|inspektor|sergeant|sarjan)\b', 9,
      'Claims authority', 'Claiming to be police, court, tax or bank officials is used to scare you into obeying.'),
  _Rule(CueCategory.fear, r'\b(warrant|waran|arrest(ed)?|tangkap|money laundering|pengubahan wang haram|haram|illegal|lawsuit|saman|summons|blacklist(ed)?|senarai hitam|frozen|freeze|dibekukan|suspend(ed)?|block(ed)?|disekat|penalty|denda|legal action|tindakan undang)\b', 10,
      'Threat or penalty', 'Threats of arrest, fines or a frozen account are meant to panic you.'),
  // Credentials
  _Rule(CueCategory.credentials, r'\b(otp|tac|one[- ]time (password|pin)|pin( number)?|password|kata laluan|cvv|card number|nombor kad|login details|username)\b', 14,
      'Asks for secret codes', 'No real bank, courier or agency will ever ask for your OTP, TAC, PIN or password.'),
  _Rule(CueCategory.credentials, r"(?<!(not|never|n't|jangan) )\b(reply|send|give|forward|share|tell|bagi|hantar)( me| us)? (with )?(the |your |that )?(\d-digit )?(code|otp|tac|pin|verification code|kod)\b", 26,
      'Wants your code', 'Anyone asking you to send them a code you received is trying to take over your account.'),
  _Rule(CueCategory.credentials, r'\b(verify|update|confirm|reactivate|unlock|sahkan|kemas ?kini)\b.{0,40}\b(account|akaun|identity|details|maklumat|ic|mykad)\b', 10,
      'Asks you to "verify" your account', 'Verification requests through a link are the most common way bank logins get stolen.'),
  // Payment
  _Rule(CueCategory.payment, r'\b(transfer|bank in|bank-in|pindahkan|bayar|pay(ment)?|deposit|top ?up|send money|hantar duit|fee|yuran|caj|charges?|tax|cukai|release fee|unlock fee|processing fee|admin fee|insurance fee|duty)\b', 6,
      'Money is mentioned', 'The conversation leads to you paying or transferring money.'),
  _Rule(CueCategory.payment, r'\b(pay|bayar|transfer).{0,30}\b(to (unlock|release|withdraw|claim)|untuk (keluarkan|tuntut))\b|\b(withdraw(al)?|pengeluaran).{0,40}\b(fee|tax|deposit|cukai|bayar)\b', 16,
      'Pay to get your money', 'Being told to pay a fee or tax before you can withdraw or receive money is a hallmark of investment and task scams.'),
  _Rule(CueCategory.payment, r'\b(safe account|akaun selamat|secure account|holding account|akaun simpanan sementara)\b', 18,
      'Asks you to move money to a "safe account"', 'No police, bank or agency will ever ask you to move your money to a "safe account". This is always a scam.'),
  _Rule(CueCategory.payment, r'\b(gift ?cards?|google play cards?|itunes|steam cards?|usdt|bitcoin|btc|crypto|binance|trc20|erc20)\b', 12,
      'Untraceable payment method', 'Gift cards and crypto are hard to trace or reverse, which is why scammers prefer them.'),
  _Rule(CueCategory.payment, r"\b(my (friend|cousin|uncle|boss|agent)'?s? account|third[- ]party account|akaun (kawan|orang lain)|not (in )?my name)\b", 14,
      "Pay into someone else's account", "Paying into an account that doesn't match the person or company is a strong sign of a mule account."),
  // Secrecy and isolation
  _Rule(CueCategory.secrecy, r"\b(don'?t tell|do not tell|jangan (beritahu|bagitahu|cakap)|keep (this|it) (secret|confidential|between us)|rahsia|confidential|sulit|don'?t (contact|call) (the )?(bank|police))\b", 14,
      'Asks for secrecy', 'Being told to keep it secret or not to call your bank cuts you off from people who would warn you.'),
  // Channel switch
  _Rule(CueCategory.channelSwitch, r'\b(add (me|my) (on|to)|contact (me|us) (on|via)|chat (on|in)|move to|switch to|join (our|my|the)|tambah).{0,25}\b(whatsapp|telegram|wechat|line|signal|group)\b|\bt\.me/|\bwa\.me/|\bchat\.whatsapp\.com/', 9,
      'Moves you to another app', 'Moving the chat to Telegram or a private group takes you away from platform protections.'),
  // Reward
  _Rule(CueCategory.reward, r"\b(congratulations|tahniah|you('ve| have)? won|winner|pemenang|prize|hadiah|lucky draw|cabutan bertuah|free gift|claim your|reward|ganjaran|bonus|cashback|rebate)\b", 9,
      'Too-good reward', 'Unexpected prizes or rewards are bait to get your details or a "small fee".'),
  // Investment and task scams
  _Rule(CueCategory.investment, r'\b(guaranteed|dijamin|confirm(ed)? (profit|untung)|risk[- ]free|tanpa risiko|no risk|double your|passive income|pendapatan pasif|daily (profit|income|return)|(\d{1,3})\s?% (profit|return|daily|monthly|sehari|sebulan)|high returns?|pulangan tinggi)\b', 14,
      'Unrealistic returns', 'Guaranteed or very high returns do not exist in legitimate investing.'),
  _Rule(CueCategory.investment, r'\b(forex|trading platform|crypto (trading|mining|platform)|investment (plan|package|platform|group)|pelaburan|mentor|signal group|vip group|insider|tip(s)? from my uncle|uncle.{0,25}\btips?|arbitrage|mining pool)\b', 9,
      'Investment pitch', 'Investment talk from strangers or new online contacts is how most investment scams begin.'),
  _Rule(CueCategory.investment, r'\b(part[- ]time|kerja sambilan|work from home|kerja dari rumah|simple tasks?|tugasan mudah|like (and|&) (follow|subscribe)|rate (products|hotels)|boost (sales|ratings)|merchant task|commission|komisen|earn (rm|\$)?\s?\d+ (daily|a day|sehari))\b', 11,
      'Easy-money job offer', 'Paid "like and review" tasks that later need a deposit are a common job scam.'),
  // Romance
  _Rule(CueCategory.romance, r'\b(hi|hello|hey|morning|good (morning|night)|night|miss you),? (dear|darling|babe|baby|honey|sayang)\b', 6,
      'Fast emotional bond', 'Strong affection early on, especially from someone you have never met, is used to build trust before asking for money.'),
  _Rule(CueCategory.romance, r'\b(my (dear|love|darling|baby|honey|queen|king)|sayang|i love you|love you so much|soulmate|destiny|meant to be|marry you|kahwin)\b', 6,
      'Fast emotional bond', 'Strong affection early on, especially from someone you have never met, is used to build trust before asking for money.'),
  _Rule(CueCategory.romance, r"\b(can'?t|cannot|unable to) (video ?call|meet|turn on (my )?camera)|camera (is )?(broken|rosak)|i'?m (on an oil rig|in the army|a doctor (with|in) (the )?un|deployed|working overseas)\b", 12,
      'Avoids being seen', 'Excuses for never meeting or video calling are a key sign the person is not who they claim.'),
  // Impersonation of known contacts
  _Rule(CueCategory.impersonation, r"\b(this is my new number|nombor baru|i changed my number|lost my phone|phone (rosak|spoiled|broken)|it'?s me,? (your|ur))\b", 12,
      'Claims a new number', '"New number" messages are how scammers pretend to be friends or family.'),
  _Rule(CueCategory.impersonation, r'\b(parcel|bungkusan|package|delivery|penghantaran|pos ?laju|poslaju|j&t|dhl|ninja ?van|courier|kurier).{0,60}\b(held|ditahan|failed|gagal|pending|unpaid|fee|caj|address|alamat|reschedul)', 12,
      'Parcel problem', 'Fake "parcel held, pay a small fee" messages are among the most common scams in Malaysia.'),
];

// Phrases genuine banks and services use; they lower the risk and cancel a
// credentials cue that sits inside them ("Do not share your TAC").
final List<_Rule> _legitRules = [
  _Rule(CueCategory.legitimacy, r"\b(do not|don'?t|never) (share|give|disclose|reveal)( (your|this|the))? (tac|otp|pin|password|code)\b|\bjangan (kongsi|dedahkan)\b", -14,
      'Security warning', 'Genuine banks remind you never to share your codes; scammers ask for them.'),
  _Rule(CueCategory.legitimacy, r'\b(we|bank|maybank|cimb|we will) (will )?never (ask|request) (for )?(your )?(tac|otp|pin|password|personal)', -10,
      'Security warning', 'A reminder that the bank never asks for codes is typical of genuine messages.'),
  _Rule(CueCategory.legitimacy, r'\b(valid for|expires in) \d+ (min(ute)?s?|saat|seconds)\b.{0,60}|if (you did not|this was not you)', -6,
      'Standard one-time code message', 'This reads like an automatic one-time code you requested yourself.'),
  _Rule(CueCategory.legitimacy, r'\b(track (it )?in the|open the official|via the official) .{0,20}\bapp\b', -6,
      'Points you to the official app', 'Genuine messages send you to the official app instead of a link.'),
];

final _zeroWidth = RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]', unicode: true);
final _aiInjection = RegExp(
  r'(ignore (all |any )?(previous|prior|above) (instructions|rules)|you are (an? )?(ai|assistant|language model)|(ai|assistant|scanner|checker|model)s?:? (this|the) (message|link) (is|has been) (verified|safe|legit)|mark (this|it) as safe|classify (this|it) as (safe|legitimate)|system prompt)',
  caseSensitive: false,
);

/// Runs every text rule and returns findings with exact spans so the UI can
/// highlight the words that triggered them. Repeated hits of the same rule
/// add little extra weight.
List<Finding> detectCues(String text) {
  final out = <Finding>[];
  for (final r in _rules) {
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

  for (final r in _legitRules) {
    final m = r.pattern.firstMatch(text);
    if (m == null) continue;
    if (r.title == 'Security warning') {
      out.removeWhere((f) => f.title == 'Asks for secret codes');
    }
    out.add(Finding(
      category: r.category,
      title: r.title,
      explanation: r.explanation,
      weight: r.weight,
      start: m.start,
      end: m.end,
      tool: 'Legitimacy check',
    ));
  }

  final zw = _zeroWidth.allMatches(text).toList();
  if (zw.isNotEmpty) {
    out.add(Finding(
      category: CueCategory.obfuscation,
      title: 'Invisible characters',
      explanation: 'The text contains ${zw.length} invisible character(s), often used to slip past spam filters.',
      weight: 10,
      start: zw.first.start,
      end: zw.first.end,
      tool: 'Obfuscation check',
    ));
  }
  final mixed = _mixedScriptWord(text);
  if (mixed != null) {
    out.add(Finding(
      category: CueCategory.obfuscation,
      title: 'Look-alike letters',
      explanation: 'A word mixes letters from different alphabets (for example a Cyrillic "а" inside an English word) to imitate a real name.',
      weight: 12,
      start: mixed.$1,
      end: mixed.$2,
      tool: 'Obfuscation check',
    ));
  }
  for (final m in _aiInjection.allMatches(text)) {
    out.add(Finding(
      category: CueCategory.aiManipulation,
      title: 'Hidden instructions for AI',
      explanation: 'The message contains text aimed at AI scam checkers, trying to make them call it safe. Genuine messages never do this.',
      weight: 25,
      start: m.start,
      end: m.end,
      tool: 'Prompt-injection guard',
    ));
  }
  return out;
}

(int, int)? _mixedScriptWord(String text) {
  for (final m in RegExp(r'\S+').allMatches(text)) {
    final w = m.group(0)!;
    var latin = false, other = false;
    for (final r in w.runes) {
      if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) latin = true;
      if ((r >= 0x0400 && r <= 0x04FF) || (r >= 0x0370 && r <= 0x03FF)) other = true;
    }
    if (latin && other) return (m.start, m.end);
  }
  return null;
}
