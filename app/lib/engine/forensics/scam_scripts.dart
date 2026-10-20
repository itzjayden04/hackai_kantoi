import '../models.dart';

class _Stage {
  final String name;
  final RegExp pattern;
  _Stage(this.name, String pattern) : pattern = RegExp(pattern, caseSensitive: false, unicode: true);
}

class _Script {
  final String name;
  final CueCategory category;
  final List<_Stage> stages;
  const _Script(this.name, this.category, this.stages);
}

// Each script is the order Malaysian scams of that type usually unfold in.
// Patterns cover English, Malay and Manglish phrasing.
final List<_Script> _scripts = [
  _Script('job task scam', CueCategory.investment, [
    _Stage('Offers an easy part-time job',
        r'\b(part[- ]?time|kerja sambilan|work from home|kerja dari rumah|hiring|we are recruiting|job offer|jawatan kosong|free ?lance|earn (rm|\$)?\s?\d+ ?(daily|a day|per day|sehari))\b'),
    _Stage('Pays a little for a simple task',
        r'\b(like (and|&) (follow|subscribe)|follow (our|the) (page|account)|subscribe to|rate (products|hotels|apps)|5[- ]?stars?|give (a )?review|simple tasks?|tugasan mudah|screenshot.{0,25}(send|hantar|submit)|commission|komisen|salary paid daily)\b'),
    _Stage('Moves you to a Telegram group',
        r'\b(telegram|join (our|the|my) (group|channel)|receptionist|task group|kumpulan tugasan|mentor will guide)\b|\bt\.me/'),
    _Stage('Asks you to prepay a "merchant task"',
        r'\b(merchant tasks?|pre-?paid tasks?|combo tasks?|vip tasks?|tugasan (berbayar|prabayar)|advance payment|top ?up.{0,30}(task|order|tugasan)|(pay|bayar|deposit).{0,30}(first|dulu|to (start|continue)))\b'),
    _Stage('Says you must pay more to withdraw',
        r'\b(withdraw(al)?|pengeluaran|keluarkan).{0,50}\b(fee|tax|cukai|deposit|unlock|frozen|beku|credit score|upgrade)\b|\b(credit score|account (is )?(frozen|locked)).{0,60}\b(pay|top ?up|bayar)\b'),
  ]),
  _Script('investment scam', CueCategory.investment, [
    _Stage('Shares a tip or a success story',
        r"\b(my (uncle|mentor|friend|cousin|aunt)|analyst|insider|signals?|i (made|earned|profit(ed)?)|my profit|tips from|i'?ve been earning)\b"),
    _Stage('Promises high, guaranteed returns',
        r'\b(guaranteed|dijamin|risk[- ]free|tanpa risiko|no risk|double your|\d{1,3}\s?% (profit|return|daily|weekly|monthly|sehari|seminggu|sebulan)|high returns?|pulangan tinggi|passive income)\b'),
    _Stage('Gets you onto a trading platform',
        r'\b(register|daftar|sign ?up|download (the|our|this) app|open (an )?account|trading (platform|app)|investment (platform|app)|platform pelaburan|install.{0,20}(apk|app))\b'),
    _Stage('Asks for your first deposit',
        r'\b(deposit|top ?up|invest(ment)? of rm|minimum (investment|deposit)|modal|start with rm ?\d+|transfer rm ?\d+)\b'),
    _Stage('Blocks your withdrawal until you pay',
        r'\b(withdraw(al)?|pengeluaran|keluarkan).{0,50}\b(tax|cukai|fee|commission|unlock|frozen|beku|insurance|verification fee)\b|\bcukai keuntungan\b'),
  ]),
  _Script('love scam', CueCategory.romance, [
    _Stage('A stranger reaches out',
        r"\b(wrong number|salah nombor|found your profile|saw your (profile|photo)|you seem (nice|kind)|can we be friends|nice to meet you|dating app)\b"),
    _Stage('Builds a fast emotional bond',
        r'\b(my (dear|love|darling|baby|honey)|sayang|i love you|love you|soulmate|destiny|miss you|rindu|meant to be|marry you|kahwin)\b'),
    _Stage('Has an excuse not to meet',
        r"\b(oil rig|in the army|deployed|(un|united nations) (doctor|mission)|working (overseas|offshore)|(can'?t|cannot|unable to) (video ?call|meet)|camera (is )?(broken|rosak))\b"),
    _Stage('A sudden problem or a gift',
        r"\b(stuck at (the )?(airport|customs)|customs (held|fee|charge)|hospital|emergency|kecemasan|sent you a (gift|parcel|package)|gift.{0,30}(held|stuck)|my account (is )?(frozen|blocked))\b"),
    _Stage('Asks you for money',
        r"\b(send (me )?money|lend me|pinjam|transfer.{0,30}(to me|for me|my account)|pay (the )?(fee|charge|customs)|help me (pay|with (the )?money)|bank in)\b"),
  ]),
  _Script('parcel scam', CueCategory.impersonation, [
    _Stage('Says you have a parcel',
        r'\b(parcel|bungkusan|package|pakej|delivery|penghantaran|shipment|courier|kurier|pos ?laju|j&t|dhl|ninja ?van)\b'),
    _Stage('Claims there is a delivery problem',
        r'\b(held|ditahan|on hold|failed|gagal|could not be delivered|unpaid|tidak berbayar|incomplete address|alamat tidak lengkap|reschedul\w*|returned to sender)\b'),
    _Stage('Asks for a small fee through a link',
        r'\b(fee|caj|pay|bayar|duty|cukai)\b.{0,60}\b(rm ?\d+(\.\d{2})?|https?://|www\.|link|pautan)|\brm ?[0-5]\.\d{2}\b'),
    _Stage('Collects your card or bank login',
        r'\b(card (number|details)|cvv|expiry|nombor kad|online banking|log ?in to your bank|tac|otp|kata laluan|password)\b'),
  ]),
  _Script('fake officer scam', CueCategory.authority, [
    _Stage('Calls as a courier, bank, telco or agency',
        r'\b(this is|calling from|dari|from) (pos ?laju|the courier|your bank|bank|tm|telekom|lhdn|hasil|insurance|klinik|hospital|kastam|customs|mahkamah|court)\b|\b(unpaid|tunggakan) (bill|bil|tax|cukai|summons|saman)\b'),
    _Stage('Says your name is linked to a crime',
        r'\b(your (ic|name|mykad|identity|account)).{0,50}\b(used|involved|linked|terlibat|registered)\b|\b(money laundering|pengubahan wang haram|drug|dadah|syndicate|sindiket)\b|\b(warrant|waran) (of|for)? ?(arrest|tangkap)'),
    _Stage('Hands you over to a "police officer"',
        r'\b(transfer(ring)? (you|this call|your call) to|connect(ing)? you (to|with)|sambungkan)\b|\b(inspector|inspektor|sergeant|sarjan|detective|pegawai polis|police officer|bank negara officer)\b'),
    _Stage('Tells you to keep it secret',
        r"\b(don'?t tell|do not tell|jangan (beritahu|bagitahu)|keep (this|it) (secret|confidential)|rahsia|sulit|do not hang up|stay on the line|jangan letak)\b"),
    _Stage('Asks you to move money to a "safe account"',
        r'\b(safe account|akaun selamat|secure account|holding account|verify your (funds|money|savings)|transfer (all )?your (money|savings|funds)|give (us |me )?your (tac|otp|online banking|banking (id|login)))\b'),
  ]),
];

/// The furthest stage of a known scam script this message reaches, if it
/// matches at least two stages of one script.
(ScriptProgress, Finding)? detectScriptStage(String text) {
  ScriptProgress? best;
  Match? bestMatch;
  _Script? bestScript;
  for (final s in _scripts) {
    final matched = <int>{};
    Match? lastMatch;
    for (var i = 0; i < s.stages.length; i++) {
      final m = s.stages[i].pattern.firstMatch(text);
      if (m != null) {
        matched.add(i);
        lastMatch = m;
      }
    }
    if (matched.length < 2) continue;
    final top = matched.reduce((a, b) => a > b ? a : b);
    final better = best == null ||
        matched.length > best.matched.length ||
        (matched.length == best.matched.length && top > best.stage);
    if (better) {
      best = ScriptProgress(script: s.name, stages: s.stages.map((x) => x.name).toList(), stage: top, matched: matched);
      bestMatch = lastMatch;
      bestScript = s;
    }
  }
  if (best == null || bestScript == null) return null;
  final n = best.stage + 1;
  final total = best.stages.length;
  final next = best.stage + 1 < total ? ' Next in this script: ${best.stages[best.stage + 1].toLowerCase()}.' : ' This is the last step, where the money is lost.';
  final finding = Finding(
    category: bestScript.category,
    title: 'Matches step $n of $total of a ${best.script}',
    explanation: 'This message is at the "${best.stages[best.stage]}" step of a known ${best.script} script '
        '(${best.matched.length} of $total steps seen).$next',
    weight: 6 + 2 * (best.matched.length - 2),
    start: bestMatch?.start,
    end: bestMatch?.end,
    tool: 'Scam script recogniser',
  );
  return (best, finding);
}
