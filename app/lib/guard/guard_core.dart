import '../engine/cues_extra.dart' show MoneyAsk, moneyAskIn;
import '../engine/investigator.dart';
import '../engine/llm.dart';
import '../engine/models.dart';
import '../engine/relationship.dart';
import 'app_check.dart';
import 'call_check.dart';
import 'chat_ai.dart';
import 'link_guard.dart';

/// Phone protection: scores chat messages that Android hands over from
/// notifications or the open chat screen, and decides when to show the pause
/// card. Kantoi's built-in checks run on the phone; when [ai] is set, risky
/// chats also get a rate-limited AI second opinion on a masked copy of the
/// last few messages. Also judges websites, callers and new apps for the
/// other guards.
class GuardCore {
  final Map<String, List<ChatMessage>> _chats = {};
  final Map<String, RiskLevel> _alerted = {};
  final Map<String, Set<String>> _seen = {};

  /// Looks a website up in Kantoi's scam list: (found, demo data).
  final (bool, bool) Function(String url)? knownSite;

  /// Looks a phone number (60123456789) up in Kantoi's scam list.
  final (bool, bool) Function(String number)? knownNumber;

  /// The AI second opinion for chats; null keeps every check on the phone.
  final ChatAi? ai;

  GuardCore({this.knownSite, this.knownNumber, this.ai});

  final Map<String, int> _convScore = {};

  final Map<String, SiteVerdict?> _sites = {};

  /// Web & link blocker: should the page in the address bar be closed?
  Future<Map<String, dynamic>?> checkSite(String addressBar) async {
    final key = addressBar.trim().toLowerCase();
    if (_sites.containsKey(key)) return _sites[key]?.toJson();
    final v = await siteVerdict(addressBar, known: knownSite);
    if (_sites.length > 300) _sites.remove(_sites.keys.first);
    _sites[key] = v;
    return v?.toJson();
  }

  /// Call guard: the incoming number only.
  Map<String, dynamic> checkCall(String? number, {bool marked = false}) =>
      checkCaller(number, marked: marked, listed: knownNumber).toJson();

  /// New apps guard.
  Map<String, dynamic> checkApp(Map facts) => checkNewApp(NewApp.fromMap(facts)).toJson();

  /// The relationship check behind the chat badge: every message of this chat
  /// Kantoi has seen (on screen or in notifications), scored as a whole.
  Map<String, dynamic> checkChat({required String app, required String chat, required List<(String, bool)> visible}) {
    final key = '$app|$chat';
    final list = _chats.putIfAbsent(key, () => []);
    final seen = _seen.putIfAbsent(key, () => {});
    for (final (text, incoming) in visible) {
      final body = text.trim();
      if (body.length < 2 || !seen.add('${incoming ? 'in' : 'out'}|$body')) continue;
      list.add(ChatMessage(sender: incoming ? chat : 'Me', text: body, fromMe: !incoming));
    }
    if (list.length > 200) list.removeRange(0, list.length - 200);
    final r = analyzeConversation(list);
    final top = r.signals.where((s) => s.weight > 0).toList().sortedSignals().take(3);
    return {
      'app': app,
      'chat': chat,
      'level': r.level.name,
      'label': riskLabel(r.level),
      'score': r.score,
      'headline': r.headline,
      'pattern': r.patternType,
      'nextStep': r.nextStep,
      'messages': list.length,
      'signals': [
        for (final s in top) {'title': s.title, 'detail': s.detail}
      ],
    };
  }

  /// Checks one message. Returns null when it was already checked.
  ///
  /// The built-in checks run on the phone. When the message has a warning
  /// sign (or the chat is getting riskier) and an AI service is set up, the
  /// last few messages also go to the AI with personal details masked; the
  /// higher of the two verdicts wins.
  Future<Map<String, dynamic>?> check({
    required String app,
    required String chat,
    required String text,
    String? sender,
    bool incoming = true,
    Set<String> ownDetails = const {},
    bool network = true,
  }) async {
    final body = text.trim();
    if (body.length < 4) return null;
    final key = '$app|$chat';
    if (!(_seen.putIfAbsent(key, () => {})).add('${incoming ? 'in' : 'out'}|$body')) return null;

    final list = _chats.putIfAbsent(key, () => []);
    // No timestamps: Kantoi only sees the chat from when protection started,
    // so "money came up on day one" would be wrong for an old friend.
    list.add(ChatMessage(sender: incoming ? (sender ?? chat) : 'Me', text: body, fromMe: !incoming));
    if (list.length > 200) list.removeAt(0);
    final conv = analyzeConversation(list);
    final convBefore = _convScore[key] ?? 0;
    _convScore[key] = conv.score;

    Investigation? inv;
    if (incoming) {
      inv = await investigate(
        body,
        source: Source.share,
        sender: sender ?? chat,
        options: InvestigateOptions(
          llm: const LlmConfig(kind: LlmKind.none),
          network: network,
          ownDetails: ownDetails,
          quick: true,
        ),
      );
    }
    final money = incoming ? moneyAskIn(body) : const MoneyAsk();
    final msgLevel = inv?.verdict.level ?? RiskLevel.safe;
    final rules = _max(_max(msgLevel, conv.level), money.level ?? RiskLevel.safe);

    // AI second opinion, only when something in the chat looks off.
    final cue = inv != null &&
        (money.any || money.pressure || money.extras > 0 || inv.findings.any((f) => f.isRisk) || inv.urls.isNotEmpty);
    final rising = conv.level.index >= RiskLevel.caution.index && conv.score >= convBefore + 10;
    ChatAiVerdict? aiV;
    if (ai != null && incoming && rules != RiskLevel.danger && (cue || rising)) {
      aiV = await ai!.judge(key, list.sublist(list.length > 6 ? list.length - 6 : 0), ownDetails: ownDetails, chatName: chat);
    }
    var worst = rules;
    final aiLed = aiV != null && aiV.level.index > rules.index;
    if (aiLed) {
      // The AI alone may not turn a message with no warning sign into "danger".
      worst = cue ? aiV.level : _min(aiV.level, RiskLevel.suspicious);
    }

    // Alert again only when the level rises. A caution-level money request
    // gets a notification; suspicious and worse also get the pause card.
    final before = _alerted[key] ?? RiskLevel.safe;
    final notice = worst.index >= RiskLevel.suspicious.index ||
        (worst == RiskLevel.caution && (money.worthNotice || (aiLed && money.any)));
    final alert = notice && worst.index > before.index;
    if (alert) _alerted[key] = worst;

    final who = (sender ?? chat).trim();
    final name = who.isEmpty ? 'This contact' : who;
    final reasons = <String>{
      ...money.reasons.take(aiV != null ? 2 : 3),
      ...?aiV?.reasons.take(aiLed ? 2 : 1),
      ...?inv?.findings.where((f) => f.isRisk).toList().sorted().map((f) => f.title),
      ...conv.signals.where((s) => s.weight > 0).toList().sortedSignals().map((s) => s.title),
    }.take(3).toList();

    final useMessage = inv != null && msgLevel.index >= conv.level.index;
    var headline = useMessage ? inv.verdict.headline : conv.headline;
    var scamType = inv?.verdict.scamType ?? conv.patternType ?? 'Suspicious chat';
    var next = useMessage ? inv.verdict.nextStep : conv.nextStep;
    var score = useMessage ? inv.verdict.score : conv.score;
    if (money.code) {
      headline = '$name wants a code that was sent to your phone. Never pass on a code: it lets someone take over your account.';
      scamType = 'Account takeover (code) scam';
      next = "Don't send the code. If it's a friend, call them on the number you already have.";
    } else if (money.any && worst.index >= RiskLevel.caution.index) {
      headline = worst == RiskLevel.caution
          ? '$name is asking for money. Call them on their usual number before you pay.'
          : '$name is asking for money in a way that matches the "friend in need" scam, where someone uses a hacked account or a new number.';
      scamType = worst == RiskLevel.caution ? 'Money request' : 'Friend-in-need money scam';
      next = 'Call $name on the number you already have, not through this chat, and ask something only they would know. '
          "Don't send money until you have spoken.";
    }
    if (aiLed) {
      scamType = aiV.scamType;
      if (!money.any && !money.code) {
        if (aiV.reasons.isNotEmpty) headline = 'AI check: ${aiV.reasons.first}.';
        if (aiV.advice != null) next = aiV.advice!;
      }
    }
    const floor = {RiskLevel.safe: 0, RiskLevel.caution: 25, RiskLevel.suspicious: 45, RiskLevel.danger: 70};
    if (score < floor[worst]!) score = floor[worst]!;
    return {
      'alert': alert,
      'alertKind': !alert ? 'none' : worst.index >= RiskLevel.suspicious.index ? 'pause' : 'notify',
      'level': worst.name,
      'label': riskLabel(worst),
      'score': score,
      'headline': headline,
      'scamType': scamType,
      'nextStep': next,
      'reasons': reasons,
      'moneyAsk': money.any || money.code,
      'ai': aiV == null ? 'none' : (aiV.cloud ? 'cloud' : 'device'),
      'aiLevel': aiV?.level.name,
      'checkedBy': aiV == null
          ? 'Checked on this phone'
          : aiV.cloud
              ? 'Checked on this phone and by AI online (personal details masked)'
              : 'Checked on this phone and by AI',
      'chat': chat,
      'app': app,
      'text': body,
    };
  }
}

RiskLevel _max(RiskLevel a, RiskLevel b) => a.index >= b.index ? a : b;
RiskLevel _min(RiskLevel a, RiskLevel b) => a.index <= b.index ? a : b;

extension on List<Finding> {
  List<Finding> sorted() => this..sort((a, b) => b.weight.compareTo(a.weight));
}

extension on List<RelSignal> {
  List<RelSignal> sortedSignals() => this..sort((a, b) => b.weight.compareTo(a.weight));
}
