import 'models.dart';

/// Kantoi's scam taxonomy: 5 groups of 4 kinds. Codes are stable (stored in
/// reports and history), labels can change.
enum ScamGroup { identity, finance, commerce, cyber, social }

class ScamKind {
  final String code;
  final ScamGroup group;
  final String label;
  /// One plain line a beginner recognises.
  final String example;
  const ScamKind(this.code, this.group, this.label, this.example);
}

String groupLabel(ScamGroup g) => switch (g) {
      ScamGroup.identity => 'Identity & impersonation',
      ScamGroup.finance => 'Money & investment',
      ScamGroup.commerce => 'Shopping & deals',
      ScamGroup.cyber => 'Hacked accounts & links',
      ScamGroup.social => 'Trust & relationships',
    };

String groupExample(ScamGroup g) => switch (g) {
      ScamGroup.identity => 'Fake police, bank, boss or family member',
      ScamGroup.finance => 'Crypto, get-rich-quick, task jobs, upfront fees',
      ScamGroup.commerce => 'Fake shops, marketplace, rental, never delivered',
      ScamGroup.cyber => 'Phishing links, malware, stolen OTP, SIM swap',
      ScamGroup.social => "Romance, fake charity, blackmail, 'recovery' agents",
    };

const scamKinds = <ScamKind>[
  ScamKind('identity.government', ScamGroup.identity, 'Government or authority impersonation',
      'Someone claims to be police, LHDN, court, Pos Malaysia or Bank Negara'),
  ScamKind('identity.brand', ScamGroup.identity, 'Business & brand copycat', 'A fake bank, Shopee, telco or courier page or message'),
  ScamKind('identity.family', ScamGroup.identity, 'Family or friend emergency', 'A "relative" or friend on a new number urgently needs money'),
  ScamKind('identity.tech_support', ScamGroup.identity, 'Tech support fraud', 'A pop-up or call says your phone is infected and asks for remote access'),
  ScamKind('finance.crypto', ScamGroup.finance, 'Crypto & token scam', 'A coin, trading app or mining plan that promises sure profit'),
  ScamKind('finance.get_rich', ScamGroup.finance, 'Get-rich-quick scheme', 'Guaranteed returns, "passive income", join-and-recruit plans'),
  ScamKind('finance.task_job', ScamGroup.finance, 'Task & employment scam', 'Paid to like videos or rate products, then asked to top up'),
  ScamKind('finance.advance_fee', ScamGroup.finance, 'Advance-fee & unexpected money', 'You won a prize or loan, but must pay a fee first'),
  ScamKind('commerce.fake_store', ScamGroup.commerce, 'Fake online store', 'Too-cheap prices, new website, pay by bank transfer only'),
  ScamKind('commerce.marketplace', ScamGroup.commerce, 'Classifieds or marketplace fraud', 'Carousell or Facebook seller or buyer who wants to deal off the app'),
  ScamKind('commerce.rental', ScamGroup.commerce, 'Rental & housing scam', 'Pay a deposit before viewing a room or house'),
  ScamKind('commerce.non_delivery', ScamGroup.commerce, 'Non-delivery & service scam', 'Paid for goods or a service that never came'),
  ScamKind('cyber.phishing', ScamGroup.cyber, 'Phishing & deceptive link', 'A link that asks you to log in, pay a fee or "verify" your account'),
  ScamKind('cyber.malware', ScamGroup.cyber, 'Malware & unwanted software', 'An APK, "wedding card" file or app outside the Play Store'),
  ScamKind('cyber.account_takeover', ScamGroup.cyber, 'Account hijacking', 'Someone logs into your WhatsApp, email or social account'),
  ScamKind('cyber.sim_otp', ScamGroup.cyber, 'SIM swap & OTP theft', 'Asked to share a TAC or OTP code, or your SIM suddenly stops working'),
  ScamKind('social.romance', ScamGroup.social, 'Romance & catfishing', 'An online partner you have never met asks for money or investment'),
  ScamKind('social.charity', ScamGroup.social, 'Fake charity or donation', 'A donation appeal after a disaster with a personal bank account'),
  ScamKind('social.sextortion', ScamGroup.social, 'Sextortion & blackmail', 'Threats to share private photos or videos unless you pay'),
  ScamKind('social.recovery', ScamGroup.social, 'Scam recovery fraud', 'Someone offers to get your lost money back for a fee'),
];

ScamKind? kindByCode(String? code) {
  if (code == null) return null;
  for (final k in scamKinds) {
    if (k.code == code) return k;
  }
  return null;
}

List<ScamKind> kindsIn(ScamGroup g) => [for (final k in scamKinds) if (k.group == g) k];

/// The codes and labels, one per line, for AI prompts.
String taxonomyForPrompt() => scamKinds.map((k) => '${k.code}: ${k.label}').join('\n');

/// Words that point to each kind, matched on the scam type name and the
/// message text (lower case). Malay words included where scams use them.
const _words = <String, List<String>>{
  'identity.government': [
    'police', 'polis', 'pdrm', 'macau', 'officer', 'lhdn', 'hasil', 'court', 'mahkamah', 'customs', 'kastam', 'bank negara',
    'warrant', 'waran', 'jpj', 'summons', 'saman', 'government', 'kerajaan', 'mcmc', 'immigration', 'imigresen'
  ],
  'identity.brand': ['phishing of', 'fake bank', 'copycat', 'brand', 'maybank', 'cimb', 'public bank', 'pos laju', 'poslaju', 'j&t', 'shopee support', 'tnb', 'unifi', 'celcom', 'maxis', 'touch n go', 'tng'],
  'identity.family': ['family', 'friend', 'grandparent', 'relative', 'new number', 'nombor baru', 'hijacked friend', 'mum', 'mak', 'son', 'anak', 'emergency'],
  'identity.tech_support': ['tech support', 'virus', 'infected', 'anydesk', 'teamviewer', 'remote access', 'microsoft support'],
  'finance.crypto': ['crypto', 'bitcoin', 'btc', 'usdt', 'token', 'binance', 'mining', 'wallet address', 'ethereum'],
  'finance.get_rich': ['investment', 'pelaburan', 'guaranteed return', 'profit', 'untung', 'passive income', 'forex', 'ponzi', 'mlm', 'get-rich'],
  'finance.task_job': ['job', 'task', 'kerja', 'part time', 'part-time', 'commission', 'komisen', 'like videos', 'rate products', 'employment'],
  'finance.advance_fee': ['prize', 'hadiah', 'won', 'menang', 'lucky draw', 'loan', 'pinjaman', 'processing fee', 'inheritance', 'unexpected money', 'advance fee'],
  'commerce.fake_store': ['fake shop', 'fake store', 'online store', 'kedai', 'too cheap', 'clearance sale', 'gambling', 'judi'],
  'commerce.marketplace': ['carousell', 'mudah', 'marketplace', 'seller', 'buyer', 'classified'],
  'commerce.rental': ['rent', 'sewa', 'room', 'bilik', 'house', 'rumah', 'deposit', 'landlord', 'tenant', 'homestay'],
  'commerce.non_delivery': ['never delivered', 'non-delivery', 'did not arrive', 'service scam', 'parcel never'],
  'cyber.phishing': ['phishing', 'link', 'verify your account', 'login', 'log in', 'parcel fee', 'pautan', 'click'],
  'cyber.malware': ['apk', 'malware', 'install', 'dangerous file', 'wedding card', 'kad kahwin', 'risky app'],
  'cyber.account_takeover': ['account', 'hijack', 'hacked', 'akaun', 'password', 'kata laluan', 'credential'],
  'cyber.sim_otp': ['otp', 'tac', 'sim', 'verification code', 'kod pengesahan', '6-digit', 'one-time'],
  'social.romance': ['love', 'romance', 'sayang', 'darling', 'dear', 'catfish', 'dating', 'boyfriend', 'girlfriend'],
  'social.charity': ['charity', 'donation', 'derma', 'sumbangan', 'flood', 'banjir', 'orphan', 'yatim', 'tabung'],
  'social.sextortion': ['sextortion', 'nude', 'bogel', 'private video', 'video call', 'blackmail', 'ugut', 'expose you'],
  'social.recovery': ['recover your money', 'recovery', 'get your money back', 'lawyer', 'peguam', 'refund agent', 'fund recovery'],
};

/// Which cue categories point to which kinds (weaker than words).
const _cueHints = <CueCategory, String>{
  CueCategory.authority: 'identity.government',
  CueCategory.impersonation: 'identity.brand',
  CueCategory.investment: 'finance.get_rich',
  CueCategory.romance: 'social.romance',
  CueCategory.credentials: 'cyber.phishing',
  CueCategory.link: 'cyber.phishing',
  CueCategory.file: 'cyber.malware',
  CueCategory.reward: 'finance.advance_fee',
};

/// The best-fitting kind for a scam, or null when nothing points anywhere
/// (a clean message). [scamType] is the verdict's own short name, which counts
/// three times as much as the message text.
ScamKind? classifyScam({String scamType = '', String text = '', Iterable<CueCategory> cues = const []}) {
  final kind = kindByCode(scamType.trim());
  if (kind != null) return kind;
  final t = scamType.toLowerCase();
  if (t.contains('legitimate') || t == 'unclear' || t.contains('normal chat')) {
    if (cues.isEmpty) return null;
  }
  final body = text.toLowerCase();
  final score = <String, int>{};
  bool hit(String hay, String w) {
    if (w.length <= 3) return RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(hay);
    return hay.contains(w);
  }

  _words.forEach((code, words) {
    var s = 0;
    for (final w in words) {
      if (hit(t, w)) s += 3;
      if (hit(body, w)) s += 1;
    }
    if (s > 0) score[code] = s;
  });
  for (final c in cues) {
    final code = _cueHints[c];
    if (code != null) score[code] = (score[code] ?? 0) + 1;
  }
  // A romance story that turns into investing is romance first.
  if ((score['social.romance'] ?? 0) > 0 && (score['finance.crypto'] ?? 0) + (score['finance.get_rich'] ?? 0) > 0) {
    score['social.romance'] = score['social.romance']! + 2;
  }
  if (score.isEmpty) return null;
  final best = score.entries.reduce((a, b) => b.value > a.value ? b : a);
  return kindByCode(best.key);
}

/// The kind for a finished check.
ScamKind? kindOf(Investigation inv) {
  if (inv.verdict.level == RiskLevel.safe) return null;
  return classifyScam(
      scamType: inv.verdict.kind ?? inv.verdict.scamType,
      text: inv.artefact.text,
      cues: inv.findings.where((f) => f.isRisk).map((f) => f.category));
}
