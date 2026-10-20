import '../engine/investigator.dart';
import '../engine/llm.dart';
import '../engine/models.dart';
import '../engine/relationship.dart';
import 'app_check.dart';
import 'call_check.dart';
import 'link_guard.dart';

/// Phone protection: scores chat messages that Android hands over from
/// notifications or the open chat screen, and decides when to show the pause
/// card. Runs on the device with Kantoi's built-in checks only (no AI), so
/// nothing from the chat leaves the phone. Also judges websites, callers and
/// new apps for the other guards.
class GuardCore {
  final Map<String, List<ChatMessage>> _chats = {};
  final Map<String, RiskLevel> _alerted = {};
  final Map<String, Set<String>> _seen = {};

  /// Looks a website up in Kantoi's scam list: (found, demo data).
  final (bool, bool) Function(String url)? knownSite;

  /// Looks a phone number (60123456789) up in Kantoi's scam list.
  final (bool, bool) Function(String number)? knownNumber;

  GuardCore({this.knownSite, this.knownNumber});

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
    list.add(ChatMessage(time: DateTime.now(), sender: incoming ? (sender ?? chat) : 'Me', text: body, fromMe: !incoming));
    if (list.length > 200) list.removeAt(0);
    final conv = analyzeConversation(list);

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
    final msgLevel = inv?.verdict.level ?? RiskLevel.safe;
    final worst = msgLevel.index >= conv.level.index ? msgLevel : conv.level;

    // Alert once per chat per level, so the card never nags about the same thing.
    final before = _alerted[key] ?? RiskLevel.caution;
    final alert = worst.index >= RiskLevel.suspicious.index && worst.index > before.index;
    if (alert) _alerted[key] = worst;

    final reasons = <String>{
      ...?inv?.findings.where((f) => f.isRisk).toList().sorted().map((f) => f.title),
      ...conv.signals.where((s) => s.weight > 0).toList().sortedSignals().map((s) => s.title),
    }.take(3).toList();

    final useMessage = inv != null && msgLevel.index >= conv.level.index;
    return {
      'alert': alert,
      'level': worst.name,
      'label': riskLabel(worst),
      'score': useMessage ? inv.verdict.score : conv.score,
      'headline': useMessage ? inv.verdict.headline : conv.headline,
      'scamType': inv?.verdict.scamType ?? conv.patternType ?? 'Suspicious chat',
      'nextStep': useMessage ? inv.verdict.nextStep : conv.nextStep,
      'reasons': reasons,
      'chat': chat,
      'app': app,
      'text': body,
    };
  }
}

extension on List<Finding> {
  List<Finding> sorted() => this..sort((a, b) => b.weight.compareTo(a.weight));
}

extension on List<RelSignal> {
  List<RelSignal> sortedSignals() => this..sort((a, b) => b.weight.compareTo(a.weight));
}
