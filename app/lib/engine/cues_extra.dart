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
      : pattern = RegExp(pattern, caseSensitive: false, unicode: true);
}

const _officer = 'Fake officer script';
const _officerWhy = 'This is the script of the "fake police or bank officer" scam. Real officers never ask you to move money or keep it secret.';

final List<_Rule> _extraRules = [
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
