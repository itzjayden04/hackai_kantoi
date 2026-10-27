/// VirusTotal for links: what 70+ security companies say about a link and
/// the website it is on, with a fresh scan when VirusTotal has not seen the
/// link yet (or its last scan is old).
///
/// The free VirusTotal key allows 4 requests a minute and 500 a day, so every
/// request goes through [VtLimiter] and answers are kept for a while in
/// [VtCache]. A check that would go over the limit is skipped and logged,
/// never queued for minutes.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../attribution/fingerprint.dart' show domainKey;
import '../models.dart';
import '../redaction.dart' show PiiType, findPii;
import '../url_analyzer.dart' show StepLogger;
import 'net_guard.dart' show runningFlutterTest;
import 'reputation.dart' show ReputationHit;

const vtBase = 'https://www.virustotal.com/api/v3';

/// How much of VirusTotal to use for one link.
enum VtDepth {
  /// Look the link up only (used for extra hops such as a shortener).
  lookup,

  /// Also scan unknown or stale links and look up the website itself.
  full,
}

// ------------------------------------------------------------------ parsing

/// VirusTotal's id for a URL: unpadded base64url of the URL.
String virusTotalUrlId(String url) => base64Url.encode(utf8.encode(url)).replaceAll('=', '');

/// (malicious, suspicious, harmless) engine counts, or null if unknown.
(int, int, int)? parseVirusTotal(String body) {
  final v = parseVtObject(body);
  return v == null ? null : (v.malicious, v.suspicious, v.harmless);
}

/// What VirusTotal knows about one link or website, or the result of a scan.
class VtVerdict {
  final int malicious;
  final int suspicious;
  final int harmless;
  final int undetected;

  /// Security company -> what it called the link ("phishing", "malware"),
  /// those that said malicious first.
  final Map<String, String> flagged;

  /// Security company -> how it classifies the site ("phishing and other frauds").
  final Map<String, String> categories;
  final DateTime? analysedAt;
  final DateTime? firstSeen;

  /// Websites only: when the domain was registered.
  final DateTime? registered;
  final String? finalUrl;
  final String? title;
  final int votesMalicious;
  final int votesHarmless;

  const VtVerdict({
    this.malicious = 0,
    this.suspicious = 0,
    this.harmless = 0,
    this.undetected = 0,
    this.flagged = const {},
    this.categories = const {},
    this.analysedAt,
    this.firstSeen,
    this.registered,
    this.finalUrl,
    this.title,
    this.votesMalicious = 0,
    this.votesHarmless = 0,
  });

  int get engines => malicious + suspicious + harmless + undetected;
  bool get flaggedAny => malicious + suspicious > 0;

  /// An old clean result says little about a link scammers reuse.
  bool staleAt(DateTime now) => analysedAt == null || now.difference(analysedAt!) > const Duration(days: 30);

  /// The most common kind of threat the security companies named.
  String get threat {
    final counts = <String, int>{};
    for (final label in flagged.values) {
      final k = _threatKind(label);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    if (counts.length > 1) counts.remove('suspicious');
    if (counts.isEmpty) return 'malicious';
    return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  /// "Fortinet, Kaspersky, BitDefender and 4 more".
  String vendorList([int show = 3]) {
    final names = flagged.keys.toList();
    if (names.length <= show) return _and(names);
    return '${names.take(show).join(', ')} and ${names.length - show} more';
  }

  /// Categories that mean phishing, malware or fraud.
  List<String> get badCategories => {
        for (final c in categories.values)
          if (RegExp(r'phish|malicious|malware|fraud|scam|compromised', caseSensitive: false).hasMatch(c)) c.toLowerCase(),
      }.toList();
}

String _threatKind(String label) {
  final l = label.toLowerCase();
  if (l.contains('phish')) return 'phishing';
  if (l.contains('malware') || l.contains('trojan') || l.contains('virus')) return 'malware';
  if (l.contains('spam')) return 'spam';
  if (l.contains('suspicious')) return 'suspicious';
  return 'malicious';
}

String _and(List<String> xs) => xs.length <= 1 ? xs.join() : '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';

DateTime? _unix(Object? v) => (v is num) ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000, isUtc: true) : null;

VtVerdict _verdict(Map stats, Map? results, Map<String, dynamic> a, {DateTime? analysedAt}) {
  int n(String k) => (stats[k] as num?)?.toInt() ?? 0;
  final bad = <String, String>{}, sus = <String, String>{};
  for (final e in (results ?? const {}).entries) {
    final r = e.value;
    if (r is! Map) continue;
    final name = '${r['engine_name'] ?? e.key}';
    final label = '${r['result'] ?? r['category'] ?? ''}';
    if (r['category'] == 'malicious') bad[name] = label;
    if (r['category'] == 'suspicious') sus[name] = label;
  }
  final votes = (a['total_votes'] is Map) ? a['total_votes'] as Map : const {};
  return VtVerdict(
    malicious: n('malicious'),
    suspicious: n('suspicious'),
    harmless: n('harmless'),
    undetected: n('undetected'),
    flagged: {...bad, ...sus},
    categories: {
      if (a['categories'] is Map)
        for (final e in (a['categories'] as Map).entries) '${e.key}': '${e.value}',
    },
    analysedAt: analysedAt ?? _unix(a['last_analysis_date']),
    firstSeen: _unix(a['first_submission_date']),
    registered: _unix(a['creation_date']),
    finalUrl: a['last_final_url'] as String?,
    title: (a['title'] as String?)?.trim().isEmpty == true ? null : a['title'] as String?,
    votesMalicious: (votes['malicious'] as num?)?.toInt() ?? 0,
    votesHarmless: (votes['harmless'] as num?)?.toInt() ?? 0,
  );
}

/// `data.<field>` of a VirusTotal JSON answer, or null.
Object? _dataField(String body, String field) {
  final j = jsonDecode(body);
  if (j is! Map) return null;
  final data = j['data'];
  if (data is! Map) return null;
  return data[field];
}

/// A URL or domain object (`GET /urls/{id}`, `GET /domains/{domain}`), or
/// null when it has never been analysed.
VtVerdict? parseVtObject(String body) {
  final a = _dataField(body, 'attributes');
  if (a is! Map<String, dynamic>) return null;
  final stats = a['last_analysis_stats'];
  if (stats is! Map) return null;
  return _verdict(stats, a['last_analysis_results'] as Map?, a);
}

/// A finished scan (`GET /analyses/{id}`), or null while it is still running.
VtVerdict? parseVtAnalysis(String body) {
  final a = _dataField(body, 'attributes');
  if (a is! Map<String, dynamic> || a['status'] != 'completed') return null;
  final stats = a['stats'];
  if (stats is! Map) return null;
  return _verdict(stats, a['results'] as Map?, const {}, analysedAt: _unix(a['date']) ?? DateTime.now().toUtc());
}

/// The scan id from a `POST /urls` answer.
String? parseVtSubmission(String body) {
  final id = _dataField(body, 'id');
  return id is String && id.isNotEmpty ? id : null;
}

// ------------------------------------------------------------ rate limit

/// Keeps Kantoi inside the VirusTotal key's limits (free: 4 a minute, 500 a day).
class VtLimiter {
  final int perMinute;
  final int perDay;

  /// For tests: the clock.
  DateTime Function() now;

  VtLimiter({this.perMinute = 4, this.perDay = 500, DateTime Function()? clock}) : now = clock ?? DateTime.now;
  VtLimiter.unlimited() : this(perMinute: 1 << 30, perDay: 1 << 30);

  final _recent = <DateTime>[];
  var _day = '';
  var _today = 0;
  DateTime? _pausedUntil;

  /// Takes one request now, or returns false when none is left.
  bool tryTake() {
    final t = now();
    if (_pausedUntil != null && t.isBefore(_pausedUntil!)) return false;
    final d = '${t.year}-${t.month}-${t.day}';
    if (d != _day) {
      _day = d;
      _today = 0;
    }
    if (_today >= perDay) return false;
    _recent.removeWhere((x) => t.difference(x) >= const Duration(minutes: 1));
    if (_recent.length >= perMinute) return false;
    _recent.add(t);
    _today++;
    return true;
  }

  /// How long until [tryTake] can succeed again (null: not today).
  Duration? get untilNext {
    final t = now();
    if (_today >= perDay && '${t.year}-${t.month}-${t.day}' == _day) return null;
    var w = Duration.zero;
    if (_pausedUntil != null && t.isBefore(_pausedUntil!)) w = _pausedUntil!.difference(t);
    _recent.removeWhere((x) => t.difference(x) >= const Duration(minutes: 1));
    if (_recent.length >= perMinute) {
      final free = const Duration(minutes: 1) - t.difference(_recent.first);
      if (free > w) w = free;
    }
    return w;
  }

  /// Waits up to [maxWait] for a request.
  Future<bool> take({Duration maxWait = Duration.zero}) async {
    final end = now().add(maxWait);
    while (true) {
      if (tryTake()) return true;
      final w = untilNext;
      if (w == null || now().add(w).isAfter(end)) return false;
      await Future<void>.delayed(w + const Duration(milliseconds: 50));
    }
  }

  /// VirusTotal said the limit was reached (HTTP 429): stop for a while.
  void pause([Duration d = const Duration(minutes: 1)]) => _pausedUntil = now().add(d);
}

/// Answers kept for a while, so the same link costs one request.
class VtCache {
  final bool enabled;
  VtCache({this.enabled = true});

  final _m = <String, (DateTime, DateTime, VtVerdict?)>{};

  /// (verdict or null for "not found", when it was saved), or null when not kept.
  (VtVerdict?, DateTime)? get(String key) {
    final e = _m[key];
    if (!enabled || e == null) return null;
    if (DateTime.now().isAfter(e.$1)) {
      _m.remove(key);
      return null;
    }
    return (e.$3, e.$2);
  }

  void put(String key, VtVerdict? v, Duration ttl) {
    if (!enabled) return;
    if (_m.length > 400) _m.remove(_m.keys.first);
    final now = DateTime.now();
    _m[key] = (now.add(ttl), now, v);
  }
}

/// Shared by every check in this app (and, separately, the background guard).
final vtLimiter = runningFlutterTest ? VtLimiter.unlimited() : VtLimiter();
final vtCache = VtCache(enabled: !runningFlutterTest);

// ------------------------------------------------------------- the check

const _limitNote = "Skipped: VirusTotal's free limit (4 lookups a minute) is used up. Check again in a minute.";
const _foundTtl = Duration(hours: 6);
const _unknownTtl = Duration(minutes: 10);

class _QuotaError implements Exception {}

/// The link without personal details, safe to hand to VirusTotal for a scan
/// (scans are shared with VirusTotal's paying users). Phone, IC, card,
/// account numbers and emails in the query or path are removed, and so is
/// any user:password. Returns the link and whether anything was removed.
(String, bool) shareableUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return (url, false);
  bool pii(String s) {
    String d;
    try {
      d = Uri.decodeFull(s);
    } catch (_) {
      d = s;
    }
    return findPii(d).any((p) => p.type != PiiType.name && p.type != PiiType.address);
  }

  final dropQuery = (u.hasQuery && pii(u.query)) || (u.hasFragment && pii(u.fragment));
  final dropPath = pii(u.path);
  if (!dropQuery && !dropPath && u.userInfo.isEmpty) return (url, false);
  final out = Uri(
    scheme: u.scheme,
    host: u.host,
    port: u.hasPort ? u.port : null,
    path: dropPath ? '/' : u.path,
    query: dropQuery || !u.hasQuery ? null : u.query,
    fragment: dropQuery || !u.hasFragment ? null : u.fragment,
  );
  return (out.toString(), true);
}

/// Checks [url] with VirusTotal and returns what it flagged. Never throws;
/// every step it starts is finished in the log.
///
/// 1. Looks the link up (only the link is sent).
/// 2. [VtDepth.full] and not [quick]: when VirusTotal has not seen the link,
///    or its only result is old and clean, sends it for a fresh scan by the
///    security engines and waits for the result (personal details in the
///    link are removed first).
/// 3. [VtDepth.full]: when the link itself is not flagged, looks up the
///    website, since a brand-new link on a known scam site is just as bad.
Future<List<ReputationHit>> checkVirusTotal(
  String url, {
  required String apiKey,
  required http.Client client,
  required StepLogger log,
  VtDepth depth = VtDepth.lookup,
  bool quick = false,
  VtLimiter? limiter,
  VtCache? cache,
  List<Duration> pollDelays = const [Duration(seconds: 15), Duration(seconds: 12)],
  Duration timeout = const Duration(seconds: 8),
  void Function()? onChange,
}) async {
  final lim = limiter ?? vtLimiter;
  final store = cache ?? vtCache;
  final hits = <ReputationHit>[];
  final host = Uri.tryParse(url)?.host ?? url;
  final headers = {'x-apikey': apiKey};
  void changed() => onChange?.call();

  Future<http.Response> vtGet(String path) async {
    final res = await client.get(Uri.parse('$vtBase$path'), headers: headers).timeout(timeout);
    if (res.statusCode == 429) {
      lim.pause();
      throw _QuotaError();
    }
    return res;
  }

  String failure(Object e) => e is _QuotaError ? 'VirusTotal says the limit for this key is reached; skipped' : 'Lookup unavailable';

  // 1. The link.
  final key = 'url:${virusTotalUrlId(url)}';
  VtVerdict? report;
  var known = false;
  final kept = store.get(key);
  if (kept != null) {
    report = kept.$1;
    known = true;
    log('VirusTotal', 'Looking up this link on $host in VirusTotal')
      ..result = '${report == null ? 'VirusTotal had not seen this link' : describeVt(report)} (saved from a check ${_ago(kept.$2)}, nothing sent)'
      ..status = StepStatus.done;
  } else if (!lim.tryTake()) {
    log('VirusTotal', 'Looking up this link on $host in VirusTotal')
      ..result = _limitNote
      ..status = StepStatus.skipped;
  } else {
    final s = log('VirusTotal', 'Looking up this link on $host with VirusTotal\'s 70+ security engines (only the link is sent)', sentOffDevice: true);
    try {
      final res = await vtGet('/urls/${virusTotalUrlId(url)}');
      if (res.statusCode == 404) {
        report = null;
      } else if (res.statusCode == 200) {
        report = parseVtObject(res.body);
      } else {
        throw StateError('${res.statusCode}');
      }
      known = true;
      store.put(key, report, report == null ? _unknownTtl : _foundTtl);
      s
        ..result = report == null ? 'VirusTotal has not seen this link before' : describeVt(report)
        ..status = StepStatus.done;
    } catch (e) {
      s
        ..result = failure(e)
        ..status = StepStatus.failed;
    }
  }
  changed();
  final r = report;
  if (r != null) {
    final h = linkHit(r);
    if (h != null) hits.add(h);
  }

  if (depth != VtDepth.full || !known) return hits;
  // Only "malicious" counts here: a lone "suspicious" still deserves a scan
  // and a look at the website.
  final flagged = (r?.malicious ?? 0) > 0;

  // 2. A fresh scan, and 3. the website, side by side.
  Future<void> scan() async {
    if (quick || flagged || (r != null && !r.staleAt(DateTime.now()))) return;
    final (target, stripped) = shareableUrl(url);
    final action = '${r == null ? 'VirusTotal has not seen this link: sending' : 'The last VirusTotal scan is old: sending'} it for a fresh scan '
        'by its security engines${stripped ? ' (personal details in the link removed first)' : ''}';
    if (!lim.tryTake()) {
      log('VirusTotal scan', action)
        ..result = _limitNote
        ..status = StepStatus.skipped;
      return;
    }
    final s = log('VirusTotal scan', action, sentOffDevice: true);
    changed();
    try {
      final res = await client.post(Uri.parse('$vtBase/urls'), headers: headers, body: {'url': target}).timeout(timeout);
      if (res.statusCode == 429) {
        lim.pause();
        throw _QuotaError();
      }
      if (res.statusCode != 200) throw StateError('${res.statusCode}');
      final id = parseVtSubmission(res.body);
      if (id == null) throw StateError('no scan id');
      VtVerdict? fresh;
      for (final d in pollDelays) {
        await Future<void>.delayed(d);
        if (!await lim.take(maxWait: const Duration(seconds: 10))) break;
        final a = await vtGet('/analyses/$id');
        if (a.statusCode != 200) throw StateError('${a.statusCode}');
        fresh = parseVtAnalysis(a.body);
        if (fresh != null) break;
      }
      if (fresh == null) {
        s
          ..result = 'Still scanning when Kantoi stopped waiting. The result will be on VirusTotal in a few minutes; check the link again later.'
          ..status = StepStatus.failed;
        return;
      }
      store.put('url:${virusTotalUrlId(target)}', fresh, _foundTtl);
      store.put(key, fresh, _foundTtl);
      s
        ..result = 'Fresh scan: ${describeVt(fresh)}'
        ..status = StepStatus.done;
      final h = linkHit(fresh, fresh: true);
      if (h != null) hits.add(h);
    } catch (e) {
      s
        ..result = e is _QuotaError ? failure(e) : 'Could not scan the link with VirusTotal'
        ..status = StepStatus.failed;
    } finally {
      changed();
    }
  }

  Future<void> website() async {
    // A link to a bare server address is looked up as that server.
    final ip = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) ? host : null;
    final domain = ip ?? domainKey(url);
    if (flagged || domain == null) return;
    final dKey = 'domain:$domain';
    final action = 'Looking up the ${ip == null ? 'website' : 'server'} $domain in VirusTotal';
    VtVerdict? d;
    final keptSite = store.get(dKey);
    if (keptSite != null) {
      d = keptSite.$1;
      log('VirusTotal', action)
        ..result = '${d == null ? 'No record of this website' : describeVt(d)} (saved from a check ${_ago(keptSite.$2)}, nothing sent)'
        ..status = StepStatus.done;
    } else if (!lim.tryTake()) {
      log('VirusTotal', action)
        ..result = _limitNote
        ..status = StepStatus.skipped;
      return;
    } else {
      final s = log('VirusTotal', action, sentOffDevice: true);
      try {
        final res = await vtGet(ip == null ? '/domains/${Uri.encodeComponent(domain)}' : '/ip_addresses/$ip');
        if (res.statusCode == 404) {
          d = null;
        } else if (res.statusCode == 200) {
          d = parseVtObject(res.body);
        } else {
          throw StateError('${res.statusCode}');
        }
        store.put(dKey, d, d == null ? _unknownTtl : _foundTtl);
        s
          ..result = d == null ? 'VirusTotal has no record of this website' : describeVt(d)
          ..status = StepStatus.done;
      } catch (e) {
        s
          ..result = failure(e)
          ..status = StepStatus.failed;
      } finally {
        changed();
      }
    }
    if (d != null) {
      final h = websiteHit(d, domain, linkKnown: r != null);
      if (h != null) hits.add(h);
    }
  }

  await Future.wait([scan(), website()]);
  // A fresh scan that flags the link makes the website result redundant.
  if (hits.any((h) => h.service == 'VirusTotal' && h.weight >= 14) && hits.any((h) => h.service == vtWebsiteService)) {
    hits.removeWhere((h) => h.service == vtWebsiteService && h.weight < 16);
  }
  return hits;
}

const vtWebsiteService = 'VirusTotal (website)';

/// The hit for a link VirusTotal's engines flagged, or null when none did.
ReputationHit? linkHit(VtVerdict v, {bool fresh = false}) {
  final bad = v.malicious, sus = v.suspicious;
  final prefix = fresh ? 'In a fresh scan just now, ' : '';
  if (bad + sus == 0) {
    if (v.votesMalicious >= 3 && v.votesMalicious > v.votesHarmless * 2) {
      return ReputationHit('VirusTotal', '${v.votesMalicious} VirusTotal users voted this link malicious, although no security company flags it yet', 6);
    }
    return null;
  }
  final who = v.flagged.isEmpty ? '' : ' (${v.vendorList()})';
  if (bad == 0) {
    return ReputationHit('VirusTotal', '$prefix$sus security compan${sus == 1 ? 'y calls' : 'ies call'} this link suspicious$who', 6);
  }
  final of = v.engines > 0 ? ' of ${v.engines}' : '';
  return ReputationHit(
    'VirusTotal',
    '$prefix$bad$of security companies flag this link as ${v.threat}$who${sus > 0 ? ', $sus more call it suspicious' : ''}',
    bad >= 5 ? 30 : (bad >= 3 ? 24 : 14),
  );
}

/// The hit for a website that VirusTotal's engines flagged or classify as a
/// scam, when the link itself was not flagged.
ReputationHit? websiteHit(VtVerdict d, String domain, {required bool linkKnown}) {
  final bad = d.malicious, sus = d.suspicious;
  final link = linkKnown ? 'this exact link is not flagged' : 'this exact link is new to VirusTotal';
  if (bad > 0) {
    return ReputationHit(vtWebsiteService,
        'The website $domain is flagged by $bad security compan${bad == 1 ? 'y' : 'ies'} as ${d.threat} (${d.vendorList()}), even though $link',
        bad >= 3 ? 20 : 10);
  }
  final cats = d.badCategories;
  if (cats.isNotEmpty) {
    return ReputationHit(vtWebsiteService, 'Security companies classify the website $domain as ${cats.take(2).map((c) => '"$c"').join(' and ')}', 10);
  }
  if (sus > 0) {
    return ReputationHit(vtWebsiteService, '$sus security compan${sus == 1 ? 'y calls' : 'ies call'} the website $domain suspicious', 4);
  }
  return null;
}

/// One line for the activity log.
String describeVt(VtVerdict v) {
  final counts = [
    '${v.malicious} malicious',
    '${v.suspicious} suspicious',
    '${v.harmless} clean',
    if (v.undetected > 0) '${v.undetected} no opinion',
  ].join(', ');
  final parts = <String>[
    counts,
    if (v.analysedAt != null) 'last scanned ${_ago(v.analysedAt!)}',
    if (v.flagged.isNotEmpty) 'flagged as ${v.threat} by ${v.vendorList()}',
    if (v.badCategories.isNotEmpty) 'classed as ${v.badCategories.take(2).map((c) => '"$c"').join(', ')}',
    if (v.registered != null) 'registered ${_ago(v.registered!)}',
    if (v.title != null) 'page title "${v.title}"',
  ];
  return parts.join('; ');
}

String _ago(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return '1 day ago';
  if (diff.inDays < 60) return '${diff.inDays} days ago';
  if (diff.inDays < 730) return '${diff.inDays ~/ 30} months ago';
  return '${diff.inDays ~/ 365} years ago';
}
