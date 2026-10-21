/// What a web lookup found: the pages, how each one was checked, and the
/// honest overall answer.
library;

import 'identifiers.dart';

/// How strongly a page backs a scam report.
enum WebEvidence {
  /// Kantoi opened the page and saw the identifier next to scam words.
  pageConfirmed,

  /// Google Search grounding tied a scam statement to this page.
  grounded,

  /// Only a search result's title or snippet mentions it; not confirmed.
  snippet,
}

class WebSource {
  final String title;
  final String url;
  final String domain;
  final String snippet;

  /// "Google Search (via Gemini)", "DuckDuckGo" or "Bing".
  final String foundVia;
  final WebEvidence evidence;
  const WebSource({
    required this.title,
    required this.url,
    required this.domain,
    this.snippet = '',
    required this.foundVia,
    required this.evidence,
  });

  bool get confirmed => evidence != WebEvidence.snippet;

  String get evidenceLabel => switch (evidence) {
        WebEvidence.pageConfirmed => 'Kantoi opened this page and found it next to scam warnings',
        WebEvidence.grounded => 'Google Search linked this page to the scam report',
        WebEvidence.snippet => 'Search result only, not confirmed',
      };

  WebSource withEvidence(WebEvidence e, {String? url, String? domain, String? snippet}) => WebSource(
      title: title, url: url ?? this.url, domain: domain ?? this.domain, snippet: snippet ?? this.snippet, foundVia: foundVia, evidence: e);

  Map<String, dynamic> toJson() =>
      {'title': title, 'url': url, 'domain': domain, 'snippet': snippet, 'foundVia': foundVia, 'evidence': evidence.name};

  factory WebSource.fromJson(Map<String, dynamic> j) => WebSource(
        title: '${j['title'] ?? ''}',
        url: '${j['url'] ?? ''}',
        domain: '${j['domain'] ?? ''}',
        snippet: '${j['snippet'] ?? ''}',
        foundVia: '${j['foundVia'] ?? ''}',
        evidence: WebEvidence.values.firstWhere((e) => e.name == j['evidence'], orElse: () => WebEvidence.snippet),
      );
}

enum WebStatus {
  /// At least one page confirms a scam report.
  reported,

  /// Search results mention it with scam words, but no page could be confirmed.
  possible,

  /// The lookups ran and found no scam reports.
  noReports,

  /// Nothing could run (offline, blocked or quota).
  unavailable,

  /// One of the user's own details, never searched.
  skipped,
}

class WebIntelResult {
  final WebIdentifier identifier;
  final WebStatus status;
  final List<WebSource> sources;
  final List<String> scamTypes;

  /// Gemini's short summary of what it found, if it searched.
  final String? summary;

  /// Which lookups actually ran, e.g. ["Google Search (via Gemini)", "DuckDuckGo"].
  final List<String> methods;
  final DateTime checkedAt;
  final bool fromCache;
  final bool offline;
  const WebIntelResult({
    required this.identifier,
    required this.status,
    this.sources = const [],
    this.scamTypes = const [],
    this.summary,
    this.methods = const [],
    required this.checkedAt,
    this.fromCache = false,
    this.offline = false,
  });

  List<WebSource> get confirmed => sources.where((s) => s.confirmed).toList();

  /// Distinct websites that confirm a report.
  List<String> get confirmedDomains => {for (final s in confirmed) s.domain}.toList();

  bool get reported => status == WebStatus.reported;

  /// One line for logs and lists, never claiming "safe".
  String get headline => switch (status) {
        WebStatus.reported =>
          'Reported online as a scam on ${confirmedDomains.length} site${confirmedDomains.length == 1 ? '' : 's'}: ${confirmedDomains.take(3).join(', ')}',
        WebStatus.possible => 'Search results mention it with scam words, but no page could be confirmed',
        WebStatus.noReports => "No public reports found (this does not prove it's safe)",
        WebStatus.unavailable => offline ? 'Offline: could not search the web' : 'Could not search the web (blocked or no answer)',
        WebStatus.skipped => 'Your own detail, not searched',
      };

  WebIntelResult copyWith({bool? fromCache}) => WebIntelResult(
      identifier: identifier,
      status: status,
      sources: sources,
      scamTypes: scamTypes,
      summary: summary,
      methods: methods,
      checkedAt: checkedAt,
      fromCache: fromCache ?? this.fromCache,
      offline: offline);

  Map<String, dynamic> toJson() => {
        'kind': identifier.kind.name,
        'key': identifier.key,
        'status': status.name,
        'sources': sources.map((s) => s.toJson()).toList(),
        'scamTypes': scamTypes,
        'summary': ?summary,
        'methods': methods,
        'checkedAt': checkedAt.toIso8601String(),
      };

  static WebIntelResult? fromJson(Map<String, dynamic> j) {
    try {
      return WebIntelResult(
        identifier: WebIdentifier(WebIdKind.values.byName('${j['kind']}'), '${j['key']}'),
        status: WebStatus.values.byName('${j['status']}'),
        sources: [for (final s in (j['sources'] as List? ?? const [])) WebSource.fromJson((s as Map).cast<String, dynamic>())],
        scamTypes: [for (final s in (j['scamTypes'] as List? ?? const [])) '$s'],
        summary: j['summary'] as String?,
        methods: [for (final s in (j['methods'] as List? ?? const [])) '$s'],
        checkedAt: DateTime.parse('${j['checkedAt']}'),
      );
    } catch (_) {
      return null;
    }
  }
}

// ------------------------------------------------------------ scam wording

final _scamWords = RegExp(
  r'\b(scams?|scammers?|scamming|scammed|penipu|penipuan|tipu|ditipu|menipu|kena tipu|fraud|fraudsters?|fraudulent|phishing|macau|sindiket|syndicate|mule|keldai akaun|swindl\w*|con artists?|beware|waspada|blacklist(ed)?|senarai hitam|laporan polis|police report|reported as scam)\b',
  caseSensitive: false,
);

// Number-lookup sites put "spam or scam?" on every page they generate, so a
// question like that is not a report.
final _templateQuestions = RegExp(
  r'(is (this|it|that) (number |caller )?(a )?(scam|fraud)\??|spam or (a )?scam\??|scam or (not|legit\w*)\??|(scam|fraud) ?\?|apakah (ini )?penipu(an)?\??)',
  caseSensitive: false,
);

String stripHtml(String html) => html
    .replaceAll(RegExp(r'<(script|style|noscript)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ')
    // Search engines bold parts of a number ("<b>012</b>-<b>3456789</b>"):
    // inline tags vanish, block tags become spaces.
    .replaceAll(RegExp(r'</?(b|strong|em|i|u|mark|span|a|font|small|wbr)\b[^>]*>', caseSensitive: false), '')
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAllMapped(RegExp(r'&#(\d{1,6});'), (m) {
      final c = int.parse(m.group(1)!);
      return c > 0 && c < 0x110000 ? String.fromCharCode(c) : ' ';
    })
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The scam words in [text], ignoring generic "is it a scam?" questions.
Iterable<RegExpMatch> scamWordsIn(String text) => _scamWords.allMatches(text.replaceAll(_templateQuestions, ' '));

bool hasScamWords(String text) => scamWordsIn(text).isNotEmpty;

/// True when [id] appears in [text] with scam wording within [window]
/// characters of it: the bar for counting a page as a report.
bool mentionsWithScamWords(String text, WebIdentifier id, {int window = 300}) {
  final clean = text.replaceAll(_templateQuestions, ' ');
  final at = id.findIn(clean);
  if (at.isEmpty) return false;
  final words = _scamWords.allMatches(clean).map((m) => m.start).toList();
  return at.any((a) => words.any((w) => (w - a).abs() <= window));
}

/// A short piece of [text] around the identifier, for showing as evidence.
String excerptAround(String text, WebIdentifier id, {int radius = 110}) {
  final at = id.findIn(text);
  if (at.isEmpty) return text.length > 2 * radius ? '${text.substring(0, 2 * radius)}…' : text;
  final s = (at.first - radius).clamp(0, text.length);
  final e = (at.first + radius).clamp(0, text.length);
  return '${s > 0 ? '…' : ''}${text.substring(s, e).trim()}${e < text.length ? '…' : ''}';
}

String hostOf(String url) {
  final h = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return h.startsWith('www.') ? h.substring(4) : h;
}
