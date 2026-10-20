/// Short "how this scam works" cards, one per scam type the engine produces.
library;

import '../engine/models.dart';

class Explainer {
  final String id;
  final String name;
  final String title;
  final String summary;
  final List<String> steps;
  final List<String> signs;
  final List<String> todo;
  final String example;
  final List<String> keywords;
  final Set<CueCategory> cues;
  final bool genuine;
  const Explainer({
    required this.id,
    required this.name,
    required this.title,
    required this.summary,
    required this.steps,
    required this.signs,
    required this.todo,
    required this.example,
    required this.keywords,
    this.cues = const {},
    this.genuine = false,
  });
}

/// Order matters: the first card whose keyword matches wins, so the more
/// specific types sit above the broad ones.
const explainers = <Explainer>[
  Explainer(
    id: 'love_investment',
    name: 'Love and investment scam',
    title: 'How "love and investment" scams work',
    summary: 'A new online friend builds a close bond for weeks, then shows you a "sure win" investment. Every ringgit you put in is gone.',
    steps: [
      'A stranger messages by "wrong number" or on a dating or social app and chats every day.',
      'They become your close friend or partner, and talk about their rich lifestyle from trading or crypto.',
      'They guide you to a trading app or website. Your first small profit is real-looking, so you put in more.',
      'When you try to withdraw, you are told to pay a "tax" or "unlock fee" first. The money never comes out.',
    ],
    signs: [
      'Someone you have never met in person talks about love and money together',
      'A trading app or website they chose, not one you found yourself',
      'You must pay a fee or tax before you can withdraw',
    ],
    todo: [
      'Never invest through a link or app given to you by an online friend.',
      'Check the company on the Securities Commission Investor Alert List.',
      'If you already paid, call 997 now and stop paying any "fees".',
    ],
    example: 'Sayang, my uncle showed me this platform, I made RM20k this month. Just start with RM3,000, I will guide you. Trust me ok?',
    keywords: ['love and investment', 'love-investment', 'romance investment', 'romance and investment', 'pig butcher', 'pig-butcher'],
    cues: {CueCategory.romance, CueCategory.investment, CueCategory.payment},
  ),
  Explainer(
    id: 'parcel',
    name: 'Parcel fee scam',
    title: 'How fake parcel SMS work',
    summary: 'You get an SMS saying a parcel is stuck and you must pay a small fee. The link steals your card or bank login.',
    steps: [
      'An SMS or WhatsApp says your parcel from Pos Malaysia, J&T or a courier is held.',
      'It asks for a small fee, like RM2.50, so it feels harmless.',
      'The link opens a copy of the courier website that asks for your card details or bank login.',
      'The scammer uses your card or logs into your bank and empties it.',
    ],
    signs: [
      'A parcel you were not expecting, or a fee you never heard of',
      'A short deadline like "pay within 24 hours"',
      'A link that is not the courier\'s real website',
    ],
    todo: [
      'Do not click the link. Track parcels only in the courier\'s own app or website.',
      'Couriers do not ask for card details by SMS.',
      'If you typed in card details, call your bank to block the card now.',
    ],
    example: 'POS MALAYSIA: Your parcel is held due to unpaid fee RM2.50. Pay within 24 hours: https://poslaju-my-redelivery.top/pay',
    keywords: ['parcel', 'courier', 'delivery', 'poslaju', 'pos laju', 'pos malaysia', 'j&t', 'dhl', 'ninja van', 'shipping'],
    cues: {CueCategory.impersonation, CueCategory.link, CueCategory.urgency, CueCategory.payment},
  ),
  Explainer(
    id: 'lhdn',
    name: 'Fake tax refund (LHDN) scam',
    title: 'How fake LHDN refund messages work',
    summary: 'A message says you are owed a tax refund and asks for your bank details. LHDN never does this.',
    steps: [
      'An SMS, email or WhatsApp claims to be from LHDN (Hasil) and says you have a refund waiting.',
      'It sends a link to "claim" the refund before a deadline.',
      'The page asks for your bank login, card number or IC.',
      'The scammer uses your details to take money or open accounts in your name.',
    ],
    signs: [
      'A refund you did not ask about, with a link',
      'Asks for your bank login or card to "receive" money',
      'The website does not end in hasil.gov.my',
    ],
    todo: [
      'Real LHDN refunds go straight to the bank account you gave in MyTax. You never need to claim by link.',
      'Check your refund status only at mytax.hasil.gov.my, typed in yourself.',
      'If you entered bank details, call your bank now.',
    ],
    example: 'LHDN: You are eligible for a tax refund of RM1,284.50. Submit your bank details at https://lhdn-refund.my-claim.co within 3 days.',
    keywords: ['lhdn', 'hasil', 'tax refund', 'refund', 'tax'],
    cues: {CueCategory.authority, CueCategory.reward, CueCategory.credentials, CueCategory.link},
  ),
  Explainer(
    id: 'officer',
    name: 'Fake officer (Macau) scam',
    title: 'How fake police and officer calls work',
    summary: 'Someone pretending to be police, a court or Bank Negara scares you about a crime and tells you to move your money to a "safe account".',
    steps: [
      'A call or message says a parcel, phone line or bank account in your name is linked to a crime.',
      'You are passed to a fake "police officer" or "Bank Negara officer" who shows a fake warrant.',
      'They say you will be arrested unless you keep it secret and move your money to a "safe account" to check it.',
      'The "safe account" belongs to the scammer. The money is moved out within minutes.',
    ],
    signs: [
      'Threats of arrest, warrant or frozen account',
      'Told not to tell family or your bank',
      'Asked to move money to a "safe account" or share your banking app',
    ],
    todo: [
      'Hang up. Real police never ask you to transfer money or keep it secret.',
      'Call the police station or agency yourself on its official number.',
      'Tell a family member right away. If you paid, call 997.',
    ],
    example: 'This is Inspector Rahman from PDRM. Your IC is linked to money laundering. A warrant will be issued today. Do not tell anyone and transfer your savings to the safe account for checking.',
    keywords: ['officer', 'macau', 'police', 'pdrm', 'court', 'customs', 'bank negara', 'authority', 'government'],
    cues: {CueCategory.authority, CueCategory.fear, CueCategory.secrecy, CueCategory.payment},
  ),
  Explainer(
    id: 'job',
    name: 'Job task scam',
    title: 'How "easy online job" scams work',
    summary: 'You are offered easy money for liking videos or rating products. Later you must pay in to "unlock" bigger tasks, and you lose it all.',
    steps: [
      'A message offers a part-time job: like videos, rate hotels or boost shop sales, paid daily.',
      'You are moved to a Telegram or WhatsApp group and paid small amounts at first, so it feels real.',
      'Then a "merchant task" needs you to top up your own money for a bigger commission.',
      'Your balance shows big profits, but to withdraw you must pay more. You never get it back.',
    ],
    signs: [
      'Easy money for simple tasks, with no interview',
      'Moved to a Telegram group or a "mentor"',
      'You must deposit or top up money to keep working',
    ],
    todo: [
      'A real job never asks you to pay to work.',
      'Leave the group and do not top up, even to "recover" your money.',
      'If you already paid, call 997 and report the accounts.',
    ],
    example: 'Hello! We are hiring part-time. Like YouTube videos and earn RM300 daily. Add our Telegram @HRJobsMY to start.',
    keywords: ['job', 'task', 'part-time', 'part time', 'employment', 'work from home', 'commission'],
    cues: {CueCategory.investment, CueCategory.reward, CueCategory.channelSwitch, CueCategory.payment},
  ),
  Explainer(
    id: 'investment',
    name: 'Investment scam',
    title: 'How fake investment schemes work',
    summary: 'A "guaranteed" investment with high returns takes your money. Early payouts come from newer victims until it all disappears.',
    steps: [
      'An ad, group chat or "mentor" promises guaranteed high returns in crypto, forex, gold or shares.',
      'They often use photos of famous people or claim approval from Bank Negara or the Securities Commission.',
      'A small first payout makes you trust it, so you put in more and invite friends.',
      'Withdrawals get blocked with new fees, then the group and website vanish.',
    ],
    signs: [
      'Guaranteed or very high returns, like 10% a month',
      '"Limited slots" or pressure to join today',
      'Pay into a personal account or with crypto',
    ],
    todo: [
      'Check the company on the Securities Commission Investor Alert List and the Bank Negara Financial Consumer Alert List.',
      'Never pay an investment into a personal bank account.',
      'If you paid, call 997 and stop paying any withdrawal fees.',
    ],
    example: 'Guaranteed 30% profit every week with our crypto trading platform. Risk-free! Join our VIP group now, limited slots.',
    keywords: ['invest', 'crypto', 'trading', 'forex', 'ponzi', 'gold', 'shares', 'stock'],
    cues: {CueCategory.investment, CueCategory.urgency, CueCategory.payment},
  ),
  Explainer(
    id: 'love',
    name: 'Love scam',
    title: 'How online love scams work',
    summary: 'Someone builds a romance online, then has an emergency and needs your money. You never meet them.',
    steps: [
      'A good-looking stranger contacts you on social media or a dating app.',
      'They say "I love you" quickly and chat every day. They work overseas, on an oil rig or in the army.',
      'They always have a reason not to video call or meet.',
      'Then comes an emergency: customs fees for a gift, a hospital bill or a plane ticket. They ask you to pay.',
    ],
    signs: [
      'Strong love words very early',
      'Never video calls or meets in person',
      'An emergency that needs your money',
    ],
    todo: [
      'Never send money to someone you have not met in person.',
      'Do a reverse image search on their photos.',
      'Talk to family or a friend before you pay anything.',
    ],
    example: 'Good morning my dear. My contract on the oil rig ends next month. My camera is broken so I can\'t video call. I need help with customs fees for your gift.',
    keywords: ['love', 'romance', 'dating', 'relationship'],
    cues: {CueCategory.romance, CueCategory.payment},
  ),
  Explainer(
    id: 'prize',
    name: 'Prize scam',
    title: 'How fake prize and lucky draw messages work',
    summary: 'You "won" a prize you never entered for. To claim it, you pay a fee or give your details.',
    steps: [
      'A message says you won cash, a phone or a car in a lucky draw from a shop, bank or telco.',
      'It looks official, with the brand\'s logo and a reference number.',
      'To claim, you must pay a "processing fee" or "tax", or log in through a link.',
      'There is no prize. The fee or your login is what they wanted.',
    ],
    signs: [
      'You won something you never entered',
      'A fee or tax to receive the prize',
      'A deadline like "claim before tonight"',
    ],
    todo: [
      'Real prizes never ask you to pay first.',
      'Check with the company through its official app or hotline.',
      'Delete the message and do not click the link.',
    ],
    example: 'TAHNIAH! You have won RM5,000 in the 11.11 Lucky Draw. Claim your prize at http://shopee-hadiah.xyz before it expires tonight.',
    keywords: ['prize', 'lucky draw', 'giveaway', 'lottery', 'reward', 'winner', 'contest'],
    cues: {CueCategory.reward, CueCategory.link, CueCategory.urgency},
  ),
  Explainer(
    id: 'otp',
    name: 'Account phishing (OTP theft)',
    title: 'How OTP and account theft works',
    summary: 'Scammers trick you into sharing a one-time code (OTP or TAC) so they can take over your WhatsApp, bank or e-wallet.',
    steps: [
      'The scammer starts logging into your account and the app sends you a code.',
      'You get a message: "Sorry, I sent my code to you by mistake" or "WhatsApp Support: send the code to keep your account".',
      'If you send the code, they take over your account.',
      'They then message your friends and family from your account to ask for money.',
    ],
    signs: [
      'Anyone asking for a code you received',
      'Pretends to be support from WhatsApp, a bank or an e-wallet',
      'A threat that your account will be closed',
    ],
    todo: [
      'Never share an OTP or TAC with anyone, even "support" or a friend.',
      'Turn on two-step verification in WhatsApp (Settings, Account).',
      'If you shared a code, change your password and call your bank now.',
    ],
    example: 'Hi, sorry I accidentally sent my 6-digit code to your number. Can you send me the code? It\'s urgent, thanks!',
    keywords: ['account phishing', 'otp', 'tac', 'account takeover', 'takeover', 'verification code', 'whatsapp'],
    cues: {CueCategory.credentials, CueCategory.urgency, CueCategory.impersonation},
  ),
  Explainer(
    id: 'ecommerce',
    name: 'Fake seller scam',
    title: 'How fake online sellers work',
    summary: 'A cheap deal on Facebook, Carousell or Mudah asks you to pay outside the platform. The item never arrives.',
    steps: [
      'A post sells a phone, concert ticket or car part far below the normal price.',
      'The seller says many people want it, so you must pay a deposit now.',
      'They refuse cash on delivery or the platform\'s own payment, often "because I am outstation".',
      'You transfer to a personal account and the seller blocks you.',
    ],
    signs: [
      'A price that is much too cheap',
      'Pressure to pay a deposit quickly',
      'No cash on delivery, and payment to someone else\'s account',
    ],
    todo: [
      'Pay only through the platform\'s own checkout, or meet in a safe public place.',
      'Check the account number on Semak Mule (semakmule.rmp.gov.my) before paying.',
      'If you paid, call 997 and report the seller on the platform.',
    ],
    example: 'iPhone 15 brand new RM1,800 only. Many people want it, pay deposit RM500 today. Cannot COD, pay to my cousin\'s account.',
    keywords: ['seller', 'e-commerce', 'ecommerce', 'shopping', 'marketplace', 'carousell', 'mudah', 'purchase', 'online shop', 'buyer'],
    cues: {CueCategory.reward, CueCategory.urgency, CueCategory.payment},
  ),
  Explainer(
    id: 'friend',
    name: 'Hijacked friend account',
    title: 'How "it\'s me, new number" scams work',
    summary: 'A scammer pretends to be a friend or relative, often from a hijacked WhatsApp, and asks to borrow money quickly.',
    steps: [
      'You get a message from a friend\'s account, or from a "new number" claiming to be family.',
      'They say their phone is broken or they are stuck and need help today.',
      'They ask you to bank in money or buy gift cards, and promise to pay back tomorrow.',
      'Often they ask you not to tell anyone else in the family.',
    ],
    signs: [
      '"This is my new number" or an unusual way of writing',
      'Urgent request for money or gift cards',
      'Payment to an account not in their name',
    ],
    todo: [
      'Call the person on their old number, or ask your family code word.',
      'Never pay before you have talked to them by voice.',
      'Warn others: their account may be sending the same message to everyone.',
    ],
    example: 'Hi dear, this is my new number, my old phone rosak. Can you help me bank in RM800 first? I\'ll return tomorrow. Don\'t tell uncle ya.',
    keywords: ['friend', 'family', 'new number', 'hijack', 'relative', 'contact', 'impersonating'],
    cues: {CueCategory.impersonation, CueCategory.payment, CueCategory.secrecy},
  ),
  Explainer(
    id: 'phishing',
    name: 'Bank or brand phishing',
    title: 'How fake bank and brand messages work',
    summary: 'A message copies your bank, TNB, an e-wallet or a shop, and sends you to a fake website to steal your login.',
    steps: [
      'You get an SMS or email that looks like it is from your bank, TNB, Touch \'n Go or another brand.',
      'It says your account is blocked, a payment failed or you have points expiring.',
      'The link opens a website that looks real but has a slightly different address.',
      'When you log in or enter your TAC, the scammer gets into your account.',
    ],
    signs: [
      'A link to "verify", "update" or "unblock" your account',
      'A web address that is close to the real one but not the same',
      'A scary deadline or threat to close the account',
    ],
    todo: [
      'Banks in Malaysia no longer send links by SMS. Open your banking app yourself.',
      'Save your bank\'s real website as a bookmark and use only that.',
      'If you entered your login, call your bank now and change your password.',
    ],
    example: 'CIMB: Your account has been suspended. Verify your identity at https://cimb-secure-login.com immediately to avoid closure.',
    keywords: ['phishing', 'bank', 'maybank', 'cimb', 'public bank', 'rhb', 'brand', 'login', 'tnb', 'touch \'n go', 'e-wallet', 'impersonation'],
    cues: {CueCategory.impersonation, CueCategory.link, CueCategory.credentials, CueCategory.fear},
  ),
  Explainer(
    id: 'legit',
    name: 'Genuine message',
    title: 'How to tell a genuine message',
    summary: 'Real banks, couriers and agencies write in a calm, predictable way. Knowing it helps you trust real messages and spot fakes.',
    steps: [
      'Genuine messages tell you something you expected, like a code you just asked for or a parcel you ordered.',
      'They send you to the official app, not to a link that asks you to log in.',
      'They remind you never to share codes, instead of asking for them.',
      'There is no threat, no prize and no rush to pay.',
    ],
    signs: [
      'You expected it, and it matches what you did',
      'Says "do not share this code" or "use the official app"',
      'No request for money, codes or personal details',
    ],
    todo: [
      'Still not sure? Open the official app or call the number on the back of your card.',
      'Never reply with codes, even to a real-looking message.',
      'Check again with Kantoi if anything changes.',
    ],
    example: 'Maybank: Your TAC for transfer of RM50.00 to account ending 1234 is 482913. Valid for 3 minutes. Do not share TAC with anyone.',
    keywords: ['legitimate', 'genuine', 'not a scam', 'real message'],
    cues: {CueCategory.legitimacy},
    genuine: true,
  ),
];

/// Used when nothing more specific matches.
const generalExplainer = Explainer(
  id: 'general',
  name: 'Common scam tricks',
  title: 'How most scams work',
  summary: 'Almost every scam uses the same few tricks: rush you, scare you or excite you, then ask for money or a code.',
  steps: [
    'The scammer pretends to be someone you trust: a bank, a shop, the police or a friend.',
    'They create a feeling: fear, excitement or love, so you stop thinking calmly.',
    'They rush you with a deadline and tell you to keep it secret.',
    'They ask you to pay, click a link, or share a code.',
  ],
  signs: [
    'A rush or a deadline',
    'A request for money, a code or your login',
    'Asked to keep it secret',
  ],
  todo: [
    'Stop and do not reply or click.',
    'Check through the official app or number, typed in yourself.',
    'Talk to someone you trust. If you paid, call 997.',
  ],
  example: 'URGENT: Your account will be blocked today. Click the link and enter your TAC to keep it active.',
  keywords: [],
  cues: {CueCategory.urgency, CueCategory.payment, CueCategory.credentials, CueCategory.secrecy},
);

Explainer? explainerById(String id) =>
    id == generalExplainer.id ? generalExplainer : explainers.where((e) => e.id == id).firstOrNull;

/// Picks the card for a free-text scam type (from the engine or the AI). Falls
/// back to the strongest cue categories, then to the general card.
Explainer explainerFor(String scamType, {Iterable<CueCategory> categories = const [], Iterable<String> cueTitles = const []}) {
  final t = scamType.toLowerCase();
  // "Investment or job scam" from the built-in guesser: decide by the cues.
  if (t.contains('investment or job')) {
    final job = cueTitles.any((c) => c.toLowerCase().contains('job'));
    return explainerById(job ? 'job' : 'investment')!;
  }
  for (final e in explainers) {
    if (e.keywords.any(t.contains)) return e;
  }
  final cats = categories.toSet();
  if (cats.isEmpty && (t.isEmpty || t == 'unclear')) return generalExplainer;
  Explainer? best;
  var bestScore = 0;
  for (final e in explainers.where((e) => !e.genuine)) {
    final s = e.cues.intersection(cats).length;
    if (s > bestScore) {
      best = e;
      bestScore = s;
    }
  }
  return bestScore >= 2 ? best! : generalExplainer;
}

/// Same, straight from an investigation.
Explainer explainerForInvestigation(Investigation inv) {
  final risky = inv.findings.where((f) => f.isRisk);
  if (inv.verdict.level == RiskLevel.safe && risky.isEmpty) return explainerById('legit')!;
  return explainerFor(inv.verdict.scamType,
      categories: risky.map((f) => f.category), cueTitles: risky.map((f) => f.title));
}
