/// Web intel: looks a phone number, bank account, email or website up on the
/// public web and reports only what a real page backs up.
///
/// 1. Gemini with Google Search grounding, when a Gemini key is set. Only the
///    pages in the grounding metadata count as sources.
/// 2. Public search pages (DuckDuckGo HTML, Bing), always, so it works
///    without a key.
/// 3. The top pages are opened in the isolated reader to confirm the
///    identifier really sits next to scam wording.
///
/// "Nothing found" never means safe. Results are kept for 24 hours.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../attribution/crawler.dart' show classifyHeadline, crawlAllowed;
import '../forensics/safe_fetch.dart' show fetchIsolated, desktopUserAgent;
import '../llm.dart';
import '../models.dart';
import '../url_analyzer.dart' show StepLogger;
import 'grounding.dart';
import 'identifiers.dart';
import 'search_parsers.dart';
import 'web_models.dart';

export 'identifiers.dart';
export 'web_models.dart';

const webTool = 'Web reports';

// ------------------------------------------------------------ cache

/// Results per identifier for 24 hours, in shared preferences under a hash
/// (the identifier itself is not stored as a key).
class WebIntelCache {
  static const ttl = Duration(hours: 24);
  final bool persist;
  final Map<String, WebIntelResult> _mem = {};
  WebIntelCache({this.persist = true});

  static String keyFor(WebIdentifier id) => 'webintel.v2.${sha256.convert(utf8.encode(id.id)).toString().substring(0, 32)}';

  Future<WebIntelResult?> get(WebIdentifier id, DateTime now) async {
    var r = _mem[id.id];
    if (r == null && persist) {
      try {
        final p = await SharedPreferences.getInstance();
        final s = p.getString(keyFor(id));
        if (s != null) r = WebIntelResult.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (r == null || r.identifier != id || now.difference(r.checkedAt) > ttl || now.isBefore(r.checkedAt)) return null;
    _mem[id.id] = r;
    return r;
  }

  Future<void> put(WebIntelResult r) async {
    _mem[r.identifier.id] = r;
    if (!persist) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(keyFor(r.identifier), jsonEncode(r.toJson()));
    } catch (_) {}
  }

  void clearMemory() => _mem.clear();
}

final webIntelCache = WebIntelCache();

// ------------------------------------------------------------ rate limit

/// Keeps grounded Gemini calls within the free quota: at most [max] per
/// [window], and a pause after the service says the quota is used up.
class GroundingLimiter {
  final int max;
  final Duration window;
  final List<DateTime> _calls = [];
  DateTime? _pausedUntil;
  GroundingLimiter({this.max = 6, this.window = const Duration(minutes: 10)});

  /// Null when a call may go ahead (and counts it), otherwise why not.
  String? acquire(DateTime now) {
    final p = _pausedUntil;
    if (p != null && now.isBefore(p)) return 'Gemini quota used up, paused for ${p.difference(now).inMinutes + 1} min';
    _calls.removeWhere((t) => now.difference(t) > window);
    if (_calls.length >= max) return 'Limit of $max searches per ${window.inMinutes} min reached';
    _calls.add(now);
    return null;
  }

  void pause(DateTime now, [Duration d = const Duration(minutes: 15)]) => _pausedUntil = now.add(d);

  void reset() {
    _calls.clear();
    _pausedUntil = null;
  }
}

final groundingLimiter = GroundingLimiter();

// ------------------------------------------------------------ lookups

bool _offlineError(Object e) {
  final s = '$e';
  return e is http.ClientException ||
      s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('Network is unreachable') ||
      s.contains('Connection refused') ||
      s.contains('offline');
}

class _Part {
  final List<WebSource> sources;
  final bool ran;
  final bool offline;
  final GroundedAnswer? answer;
  final List<WebSource> about;
  const _Part({this.sources = const [], this.ran = false, this.offline = false, this.answer, this.about = const []});
}

class WebIntel {
  final http.Client client;
  final LlmConfig llm;
  final WebIntelCache cache;
  final GroundingLimiter limiter;
  final Duration groundTimeout;
  final Duration searchTimeout;
  final Duration pageTimeout;
  final DateTime Function() now;

  WebIntel({
    required this.client,
    this.llm = LlmConfig.defaults,
    WebIntelCache? cache,
    GroundingLimiter? limiter,
    this.groundTimeout = const Duration(seconds: 10),
    this.searchTimeout = const Duration(seconds: 8),
    this.pageTimeout = const Duration(seconds: 6),
    DateTime Function()? now,
  })  : cache = cache ?? webIntelCache,
        limiter = limiter ?? groundingLimiter,
        now = now ?? DateTime.now;

  bool get canGround => llm.kind == LlmKind.gemini && llm.apiKey.isNotEmpty;

  /// Looks [id] up. Every step goes through [log]; [onChange] is called when
  /// a step finishes so a live view can redraw. Never throws.
  Future<WebIntelResult> lookup(WebIdentifier id, {StepLogger? log, void Function()? onChange}) async {
    LogStep step(String tool, String action, {bool online = true}) {
      final s = log?.call(tool, action, sentOffDevice: online) ?? LogStep(tool: tool, action: action, sentOffDevice: online);
      onChange?.call();
      return s;
    }

    void done(LogStep s, String result, [StepStatus status = StepStatus.done]) {
      s
        ..result = result
        ..status = status;
      onChange?.call();
    }

    final at = now();
    final cached = await cache.get(id, at);
    if (cached != null) {
      final s = step(webTool, 'Looking for saved web results about ${id.display}', online: false);
      final h = at.difference(cached.checkedAt).inHours;
      done(s, 'Searched ${h == 0 ? 'less than an hour' : '$h h'} ago, reused (kept 24 h): ${cached.headline}');
      return cached.copyWith(fromCache: true);
    }

    final main = step(webTool, 'Searching the public web for reports about ${id.display}');
    final parts = await Future.wait([
      _grounded(id, step, done),
      _engine('DuckDuckGo', ddgSearchUri, parseDuckDuckGo, id, step, done),
      _engine('Bing', bingSearchUri, parseBing, id, step, done),
    ]);
    final answer = parts.first.answer;

    // Candidates worth opening: every page Google cited, then search results
    // that mention the identifier with scam words.
    final all = [for (final p in parts) ...p.sources];
    final candidates = <WebSource>[];
    for (final s in [...all.where((s) => s.foundVia == groundedVia), ...all.where((s) => s.foundVia != groundedVia)]) {
      if (candidates.length >= 4) break;
      final u = Uri.tryParse(s.url);
      if (u == null || !crawlAllowed(u) || candidates.any((c) => c.url == s.url)) continue;
      candidates.add(s);
    }
    final opened = <String, WebSource>{};
    if (candidates.isNotEmpty) {
      final s = step('$webTool: page check', 'Opening the top ${candidates.length} page(s) in the isolated reader to confirm');
      var confirmed = 0, reached = 0;
      await Future.wait(candidates.map((c) async {
        try {
          final page = await fetchIsolated(Uri.parse(c.url), client: client, userAgent: desktopUserAgent, timeout: pageTimeout).timeout(pageTimeout);
          if (page.html == null) return;
          reached++;
          final text = stripHtml(page.html!);
          if (mentionsWithScamWords(text, id)) {
            confirmed++;
            opened[c.url] = c.withEvidence(WebEvidence.pageConfirmed,
                url: page.finalUrl.toString(), domain: hostOf(page.finalUrl.toString()), snippet: excerptAround(text, id));
          }
        } catch (_) {}
      }));
      done(
          s,
          reached == 0
              ? 'Could not open the pages (blocked or no answer)'
              : '$reached opened, $confirmed show the ${id.kindLabel} next to scam warnings',
          reached == 0 ? StepStatus.failed : StepStatus.done);
    }

    // Keep only pages that back a report, or search results that hint at one.
    final kept = <WebSource>[];
    for (final s0 in all) {
      final s = opened[s0.url] ?? s0;
      final hint = s.foundVia != groundedVia && s.evidence == WebEvidence.snippet;
      if (!s.confirmed && !hint) continue;
      final dup = kept.indexWhere((k) => k.url == s.url || (k.domain == s.domain && k.title == s.title));
      if (dup < 0) {
        kept.add(s);
      } else if (!kept[dup].confirmed && s.confirmed) {
        kept[dup] = s;
      }
    }
    kept.sort((a, b) => a.evidence.index.compareTo(b.evidence.index));

    final ran = parts.any((p) => p.ran);
    final status = kept.any((s) => s.confirmed)
        ? WebStatus.reported
        : kept.isNotEmpty
            ? WebStatus.possible
            : ran
                ? WebStatus.noReports
                : WebStatus.unavailable;
    final types = <String>{
      if (status == WebStatus.reported && answer?.reported == 'yes') ...answer!.scamTypes,
      for (final s in kept.where((s) => s.confirmed)) ?classifyHeadline('${s.title} ${s.snippet}'),
    }..remove('Other scams');
    final result = WebIntelResult(
      identifier: id,
      status: status,
      sources: kept.take(8).toList(),
      scamTypes: types.take(3).toList(),
      summary: status == WebStatus.reported && answer?.reported == 'yes' && answer!.summary.isNotEmpty ? answer.summary : null,
      methods: [
        if (parts[0].ran) groundedVia,
        if (parts[1].ran) 'DuckDuckGo',
        if (parts[2].ran) 'Bing',
      ],
      checkedAt: at,
      offline: !ran && parts.any((p) => p.offline),
      siteType: answer?.siteType,
      reputation: answer?.reputation,
      reputationSummary: answer?.reputationSummary,
      about: [for (final p in parts) ...p.about].take(8).toList(),
    );
    if (answer?.reported == 'yes' && status != WebStatus.reported) {
      done(main, '${result.headline}. Gemini said "reported" but no page backed it up, so it is not counted.',
          status == WebStatus.unavailable ? StepStatus.failed : StepStatus.done);
    } else {
      done(main, result.offline ? 'Offline: ${result.headline}' : result.headline, status == WebStatus.unavailable ? StepStatus.failed : StepStatus.done);
    }
    if (status != WebStatus.unavailable) await cache.put(result);
    return result;
  }

  Future<_Part> _grounded(WebIdentifier id, LogStep Function(String, String, {bool online}) step, void Function(LogStep, String, [StepStatus]) done) async {
    if (!canGround) {
      final s = step('$webTool: Google Search (Gemini)', 'Asking Gemini to search Google', online: false);
      done(s, 'No Gemini key set up, using public search pages instead', StepStatus.skipped);
      return const _Part();
    }
    final why = limiter.acquire(now());
    if (why != null) {
      final s = step('$webTool: Google Search (Gemini)', 'Asking Gemini to search Google', online: false);
      done(s, '$why, using public search pages instead', StepStatus.skipped);
      return const _Part();
    }
    final s = step('$webTool: Google Search (Gemini)', 'Asking Gemini to search Google for public reports of ${id.display}');
    try {
      final reply = await LlmClient(llm, client: client).groundedSearch(groundedPrompt(id), timeout: groundTimeout);
      final a = parseGrounded(reply, id);
      if (!a.searched) {
        done(s, 'Gemini answered without searching Google, so its answer is not used', StepStatus.failed);
        return const _Part(ran: false);
      }
      final backed = a.sources.where((x) => x.confirmed).length;
      done(s, 'Google returned ${a.sources.length} page(s). Gemini says reported: ${a.reported}; $backed page(s) back it up');
      return _Part(sources: a.sources, ran: true, answer: a);
    } on LlmError catch (e) {
      if (e.status == 429) limiter.pause(now());
      done(
          s,
          e.status == 429
              ? 'Gemini quota reached, using public search pages instead'
              : e.status == 400 || e.status == 403
                  ? 'Google Search grounding is not available for this key or model (${e.status}), using public search pages instead'
                  : 'Gemini failed (${e.status ?? 'no answer'}), using public search pages instead',
          StepStatus.failed);
      return const _Part();
    } catch (e) {
      final off = _offlineError(e);
      done(s, off ? 'Offline, skipped' : e is TimeoutException ? 'No answer in time, skipped' : 'Could not reach Gemini, skipped', StepStatus.failed);
      return _Part(offline: off);
    }
  }

  Future<_Part> _engine(String name, Uri Function(String) uri, List<SearchHit> Function(String) parse, WebIdentifier id,
      LogStep Function(String, String, {bool online}) step, void Function(LogStep, String, [StepStatus]) done) async {
    final forms = id.variants.take(4).map((v) => '"$v"').join(' OR ');
    // For a website, also ask what it is (gambling, reviews), not only scams.
    final site = id.kind == WebIdKind.domain;
    final query = site ? '$forms scam OR penipuan OR tipu OR judi OR casino OR review' : '$forms scam OR penipuan OR tipu';
    final s = step('$webTool: $name',
        'Searching $name for ${id.display} with the words scam, penipuan, tipu${site ? ', judi, casino, review' : ''}');
    try {
      final res = await client.get(uri(query), headers: {
        'User-Agent': desktopUserAgent,
        'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5',
        'Accept-Language': 'en-MY,en;q=0.9,ms;q=0.8',
      }).timeout(searchTimeout);
      if (res.statusCode != 200) throw SearchBlocked('$name (HTTP ${res.statusCode})');
      final hits = parse(res.body);
      final mentions = hits.where((h) => id.foundIn(h.text)).toList();
      final scammy = mentions.where((h) => mentionsWithScamWords(h.text, id)).toList();
      done(
          s,
          hits.isEmpty
              ? 'No results'
              : '${hits.length} result(s), ${mentions.length} mention the ${id.kindLabel}, ${scammy.length} with scam words');
      WebSource src(SearchHit h) =>
          WebSource(title: h.title, url: h.url, domain: hostOf(h.url), snippet: h.snippet, foundVia: name, evidence: WebEvidence.snippet);
      return _Part(ran: true, sources: [for (final h in scammy) src(h)], about: [
        if (site)
          for (final h in mentions.take(5))
            if (hostOf(h.url) != id.key && !hostOf(h.url).endsWith('.${id.key}')) src(h),
      ]);
    } on SearchBlocked catch (e) {
      done(s, '${e.engine} asked for a robot check or refused, skipped', StepStatus.failed);
      return const _Part();
    } catch (e) {
      final off = _offlineError(e);
      done(s, off ? 'Offline, skipped' : e is TimeoutException ? 'No answer in time, skipped' : 'Could not read the results, skipped', StepStatus.failed);
      return _Part(offline: off);
    }
  }
}

// ------------------------------------------------------------ verdict

/// Findings for the investigation: a confirmed report is strong evidence; a
/// search hint is a mild one; nothing found adds nothing.
List<Finding> webIntelFindings(List<WebIntelResult> results) => [
      for (final r in results)
        if (r.status == WebStatus.reported)
          Finding(
            category: CueCategory.knownScam,
            title: 'Reported online as a scam',
            explanation: '${r.identifier.display} appears next to scam warnings on ${r.confirmedDomains.length} public '
                'site${r.confirmedDomains.length == 1 ? '' : 's'}: ${r.confirmedDomains.take(3).join(', ')}.',
            weight: r.confirmedDomains.length >= 2 ? 45 : 30,
            tool: webTool,
          )
        else if (r.status == WebStatus.possible)
          Finding(
            category: CueCategory.knownScam,
            title: 'Possible scam reports online',
            explanation: 'Search results mention ${r.identifier.display} with scam words, but Kantoi could not open the pages to confirm.',
            weight: 8,
            tool: webTool,
          ),
    ];

/// The lowest verdict web reports allow: one confirming site means at least
/// suspicious, two or more independent sites mean danger.
RiskLevel? webIntelFloor(List<WebIntelResult> results) {
  final n = results.where((r) => r.reported).map((r) => r.confirmedDomains.length).fold<int>(0, (a, b) => a > b ? a : b);
  if (n >= 2) return RiskLevel.danger;
  if (n == 1) return RiskLevel.suspicious;
  return null;
}

/// Web results of a finished investigation, for the result screen.
final _byInvestigation = Expando<List<WebIntelResult>>('webIntel');

List<WebIntelResult> webIntelOf(Investigation inv) => _byInvestigation[inv] ?? const [];

void attachWebIntel(Investigation inv, List<WebIntelResult> results) {
  if (results.isNotEmpty) _byInvestigation[inv] = results;
}
