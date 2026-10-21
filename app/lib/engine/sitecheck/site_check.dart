/// Website purpose and reputation, together: what a site is for (from its
/// page), how the rest of the internet sees it (top-sites rank, domain age,
/// web reports, blocklists), and the risk that follows. Used by the Trace tab
/// and by link checks in the Check tab. Every online part times out and fails
/// soft; offline, the purpose still comes from the web address.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../forensics/keys.dart';
import '../forensics/reputation.dart';
import '../forensics/safe_fetch.dart';
import '../llm.dart';
import '../models.dart';
import '../url_analyzer.dart' show StepLogger, officialBrandFor, registrableDomain;
import '../webintel/grounding.dart' show groundedVia;
import '../webintel/web_intel.dart';
import 'purpose.dart';

export 'purpose.dart';

const purposeTool = 'Website purpose';
const popularityTool = 'Top-sites rank (Tranco)';
const reputationTool = 'Website reputation';

/// Sites ranked this high are household names.
const wellKnownRank = 10000;

// ------------------------------------------------------------ Tranco

Uri trancoUri(String domain) => Uri.parse('https://tranco-list.eu/api/ranks/domain/$domain');

/// The latest rank in a Tranco answer, or null when the site is not in the
/// top million.
int? parseTranco(String body) {
  final j = jsonDecode(body);
  final ranks = j is Map ? j['ranks'] as List? : null;
  if (ranks == null || ranks.isEmpty) return null;
  final rows = [
    for (final r in ranks)
      if (r is Map && r['rank'] is num) ('${r['date'] ?? ''}', (r['rank'] as num).toInt()),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  return rows.isEmpty ? null : rows.first.$2;
}

// ------------------------------------------------------------ report

/// One place a reputation fact came from, for the tappable source list.
class RepSource {
  final String label;
  final String detail;
  final String? url;

  /// 1 reassuring, -1 worrying, 0 neutral.
  final int tone;
  const RepSource(this.label, this.detail, {this.url, this.tone = 0});
}

/// A reason for the site's risk: a warning (positive weight) or a
/// reassuring sign (negative). [floor] is the lowest level it allows.
class SiteReason {
  final String title;
  final String why;
  final int weight;
  final RiskLevel? floor;
  final CueCategory category;
  const SiteReason(this.title, this.why, this.weight, {this.floor, this.category = CueCategory.link});
  bool get isRisk => weight > 0;
}

String _years(int days) => days < 60
    ? '$days days'
    : days < 730
        ? '${days ~/ 30} months'
        : '${days ~/ 365} years';

class SiteReport {
  final String domain;
  final String url;
  final PurposeResult purpose;
  final bool trancoChecked;
  final int? trancoRank;
  final int? ageDays;
  final List<ReputationHit> listings;
  final WebIntelResult? web;
  final bool mcmcBlocked;
  final DateTime checkedAt;
  final bool fromCache;
  const SiteReport({
    required this.domain,
    required this.url,
    required this.purpose,
    this.trancoChecked = false,
    this.trancoRank,
    this.ageDays,
    this.listings = const [],
    this.web,
    this.mcmcBlocked = false,
    required this.checkedAt,
    this.fromCache = false,
  });

  String? get officialBrand => officialBrandFor(domain);
  bool get wellKnown => trancoRank != null && trancoRank! <= wellKnownRank;
  bool get webReported => web?.reported == true;
  bool get badListing => listings.isNotEmpty;

  /// True when something online was actually checked.
  bool get reputationChecked =>
      officialBrand != null || trancoChecked || ageDays != null || listings.isNotEmpty || mcmcBlocked || (web != null && web!.methods.isNotEmpty);

  /// 0 (bad) to 100 (excellent), or null when nothing could be checked.
  int? get reputationScore {
    if (officialBrand != null) return 95;
    if (!reputationChecked) return null;
    var s = 50;
    final r = trancoRank;
    if (r != null) {
      s += r <= wellKnownRank ? 35 : (r <= 100000 ? 22 : 10);
    } else if (trancoChecked) {
      s -= 5;
    }
    final a = ageDays;
    if (a != null) s += a > 365 * 3 ? 10 : (a > 365 ? 5 : (a < 30 ? -30 : (a < 180 ? -12 : 0)));
    final w = web;
    if (w != null) {
      if (w.reported) s -= w.confirmedDomains.length >= 2 ? 45 : 35;
      if (w.status == WebStatus.possible) s -= 10;
      if (w.status == WebStatus.noReports) s += 5;
      if (w.reputation == 'bad') s -= 20;
      if (w.reputation == 'mixed') s -= 5;
      if (w.reputation == 'good' && !w.reported) s += 8;
    }
    if (listings.isNotEmpty) s -= 40;
    if (mcmcBlocked) s -= 35;
    return s.clamp(0, 100);
  }

  String get reputationLabel {
    final s = reputationScore;
    if (s == null) return 'Not checked';
    if (s >= 80) return 'Good';
    if (s >= 60) return 'Fair';
    if (s >= 40) return 'Little known';
    if (s >= 20) return 'Poor';
    return 'Bad';
  }

  /// One or two plain sentences.
  String get reputationSummary {
    if (officialBrand != null) return 'Official website of $officialBrand.';
    if (!reputationChecked) return 'Kantoi could not check how the internet sees this site (offline or blocked).';
    final parts = <String>[
      if (trancoRank != null)
        trancoRank! <= wellKnownRank
            ? 'One of the world\'s most visited sites (rank #$trancoRank)'
            : 'In the top ${trancoRank! <= 100000 ? '100 000' : '1 million'} sites (rank #$trancoRank)'
      else if (trancoChecked)
        'Not in the top 1 million sites',
      if (ageDays != null) 'registered ${_years(ageDays!)} ago',
      if (web?.reported == true)
        'reported as a scam on ${web!.confirmedDomains.length} site${web!.confirmedDomains.length == 1 ? '' : 's'}'
      else if (web?.status == WebStatus.possible)
        'search results mention it with scam words (not confirmed)'
      else if (web?.status == WebStatus.noReports)
        'no scam reports found online',
      for (final h in listings) 'listed by ${h.service}',
      if (mcmcBlocked) 'blocked in Malaysia',
    ];
    var s = parts.isEmpty ? '' : '${parts.first[0].toUpperCase()}${parts.first.substring(1)}${parts.length > 1 ? ', ${parts.skip(1).join(', ')}' : ''}.';
    final g = web?.reputationSummary;
    if (g != null && g.isNotEmpty) s = '$s Google Search (via Gemini): $g';
    if (purpose.risky && (trancoRank ?? 1 << 30) <= 100000) s = '$s Being popular does not make it legal or safe.';
    return s.trim();
  }

  List<RepSource> get sources {
    final out = <RepSource>[
      if (officialBrand != null) RepSource('Kantoi official websites list', '$domain belongs to $officialBrand', tone: 1),
      if (trancoChecked)
        RepSource('Tranco top-sites list', trancoRank == null ? 'Not in the top 1 million' : 'Rank #$trancoRank worldwide',
            url: trancoUri(domain).toString(), tone: trancoRank != null && trancoRank! <= 100000 ? 1 : 0),
      if (ageDays != null)
        RepSource('Domain registry (RDAP)', 'Registered ${_years(ageDays!)} ago',
            url: 'https://rdap.org/domain/$domain', tone: ageDays! < 180 ? -1 : (ageDays! > 365 * 3 ? 1 : 0)),
      for (final h in listings) RepSource(h.service, h.summary, tone: -1),
      if (mcmcBlocked) const RepSource('Internet provider block notice', 'The page was the notice shown for sites blocked in Malaysia', tone: -1),
      if (web?.reputationSummary != null)
        RepSource(groundedVia, web!.reputationSummary!, tone: web!.reputation == 'bad' ? -1 : (web!.reputation == 'good' ? 1 : 0)),
      for (final s in [...?web?.sources, ...?web?.about].take(6))
        RepSource(s.domain, s.title, url: s.url, tone: s.confirmed ? -1 : 0),
    ];
    final seen = <String>{};
    return out.where((s) => seen.add('${s.label}|${s.url ?? s.detail}')).toList();
  }

  /// The reasons behind the site's risk. Domain age, reputation-service
  /// listings and confirmed web reports are left out: the callers already
  /// report those. [official] adds the official-site sign (the Check tab has
  /// its own).
  List<SiteReason> reasons({bool official = true}) {
    final p = purpose;
    final out = <SiteReason>[];
    if (p.risky) {
      final weight = switch (p.level) {
        RiskLevel.danger => 50,
        RiskLevel.suspicious => 30,
        _ => 12,
      };
      out.add(SiteReason(p.headline, '${p.explanation} Found: ${p.reasons.join('; ')}.', weight,
          floor: p.level, category: purposeCategory(p.purpose)));
    }
    if (mcmcBlocked) {
      out.add(const SiteReason('Blocked in Malaysia',
          'When Kantoi opened it, the internet provider showed the notice used for sites blocked under Malaysian law (MCMC).', 30,
          floor: RiskLevel.suspicious));
    }
    final w = web;
    if (w != null && w.reputation == 'bad' && !w.reported) {
      out.add(SiteReason('Bad reputation online', 'Google Search (via Gemini): ${w.reputationSummary ?? 'reviews and reports about it are negative'}.', 14));
    }
    final clean = !p.risky && !mcmcBlocked && !webReported && listings.isEmpty && w?.reputation != 'bad';
    if (clean && officialBrand == null) {
      final r = trancoRank;
      if (r != null && r <= wellKnownRank) {
        out.add(SiteReason('Well-known website', '$domain is ranked #$r in the Tranco list of the world\'s most visited websites.', -25,
            category: CueCategory.legitimacy));
      } else if (r != null && r <= 100000) {
        out.add(SiteReason('Established website', '$domain is in the top 100 000 websites worldwide (Tranco rank #$r).', -12,
            category: CueCategory.legitimacy));
      } else if (r != null) {
        out.add(SiteReason('Listed among popular websites', '$domain is in the Tranco top 1 million (rank #$r).', -4, category: CueCategory.legitimacy));
      }
    }
    if (official && officialBrand != null && !p.risky) {
      out.add(SiteReason('Official website', '$domain is an official website of $officialBrand.', -20, category: CueCategory.legitimacy));
    }
    return out;
  }

  RiskLevel get level {
    final rs = reasons();
    final score = rs.fold<int>(0, (a, r) => a + r.weight);
    var l = score >= 45
        ? RiskLevel.danger
        : score >= 25
            ? RiskLevel.suspicious
            : score >= 8
                ? RiskLevel.caution
                : RiskLevel.safe;
    for (final r in rs) {
      final f = r.floor;
      if (f != null && f.index > l.index) l = f;
    }
    if (webReported && l.index < RiskLevel.suspicious.index) l = RiskLevel.suspicious;
    if (badListing && l.index < RiskLevel.suspicious.index) l = RiskLevel.suspicious;
    return l;
  }

  /// "Low risk" only with a real reason to trust it; otherwise "No warning
  /// signs found yet".
  String get levelLabel => switch (level) {
        RiskLevel.danger => 'High risk',
        RiskLevel.suspicious => 'Elevated risk',
        RiskLevel.caution => 'Some risk',
        RiskLevel.safe => officialBrand != null || wellKnown || (trancoRank != null && trancoRank! <= 100000) ? 'Low risk' : 'No warning signs found yet',
      };

  SiteReport copyWith({WebIntelResult? web, PurposeResult? purpose, bool? fromCache}) => SiteReport(
      domain: domain,
      url: url,
      purpose: purpose ?? this.purpose,
      trancoChecked: trancoChecked,
      trancoRank: trancoRank,
      ageDays: ageDays,
      listings: listings,
      web: web ?? this.web,
      mcmcBlocked: mcmcBlocked,
      checkedAt: checkedAt,
      fromCache: fromCache ?? this.fromCache);

  Map<String, dynamic> toJson() => {
        'domain': domain,
        'url': url,
        'purpose': purpose.toJson(),
        'trancoChecked': trancoChecked,
        'trancoRank': ?trancoRank,
        'ageDays': ?ageDays,
        'listings': [for (final h in listings) {'service': h.service, 'summary': h.summary, 'weight': h.weight}],
        'web': ?web?.toJson(),
        'mcmcBlocked': mcmcBlocked,
        'checkedAt': checkedAt.toIso8601String(),
      };

  static SiteReport? fromJson(Map<String, dynamic> j) {
    try {
      return SiteReport(
        domain: '${j['domain']}',
        url: '${j['url']}',
        purpose: PurposeResult.fromJson((j['purpose'] as Map).cast<String, dynamic>()),
        trancoChecked: j['trancoChecked'] == true,
        trancoRank: (j['trancoRank'] as num?)?.toInt(),
        ageDays: (j['ageDays'] as num?)?.toInt(),
        listings: [
          for (final h in (j['listings'] as List? ?? const []))
            ReputationHit('${(h as Map)['service']}', '${h['summary']}', (h['weight'] as num?)?.toInt() ?? 0),
        ],
        web: j['web'] == null ? null : WebIntelResult.fromJson((j['web'] as Map).cast<String, dynamic>()),
        mcmcBlocked: j['mcmcBlocked'] == true,
        checkedAt: DateTime.parse('${j['checkedAt']}'),
      );
    } catch (_) {
      return null;
    }
  }
}

CueCategory purposeCategory(SitePurpose p) => switch (p) {
      SitePurpose.investment || SitePurpose.jobScam => CueCategory.investment,
      SitePurpose.moneyLending => CueCategory.payment,
      SitePurpose.phishing => CueCategory.credentials,
      SitePurpose.fakeShop => CueCategory.reward,
      _ => CueCategory.link,
    };

/// Uses what the web says about a site when its own page gave no risky
/// purpose: Gemini's reading of the Google results, or several search
/// results describing it. Never more than "suspicious" on its own.
PurposeResult withWebPurpose(PurposeResult p, WebIntelResult? w, Uri url) {
  if (w == null || p.risky || p.purpose == SitePurpose.legitBrand) return p;
  RiskLevel cap(RiskLevel l) => l.index > RiskLevel.suspicious.index ? RiskLevel.suspicious : l;
  final g = w.siteType == null ? null : purposeFromName(w.siteType!);
  if (g != null && purposeLevel(g) != RiskLevel.safe) {
    return PurposeResult(
        purpose: g,
        level: cap(purposeLevel(g)),
        confidence: 0.7,
        basis: PurposeBasis.web,
        aiPurpose: p.aiPurpose,
        aiConfidence: p.aiConfidence,
        aiReasons: p.aiReasons,
        title: p.title,
        reasons: ['Google Search (via Gemini) describes the site as ${purposeLabel(g).toLowerCase()}${w.reputationSummary == null ? '' : ': ${w.reputationSummary}'}']);
  }
  // Search results only count when two different sites each describe it
  // the same way: spam pages list many domains next to gambling words.
  final votes = <SitePurpose, Set<String>>{};
  final found = <SitePurpose, PurposeResult>{};
  for (final s in w.about) {
    final r = classifyPurpose(PageSample(url: url, fetched: true, title: s.title, text: s.snippet));
    if (!r.risky) continue;
    (votes[r.purpose] ??= {}).add(s.domain);
    found[r.purpose] ??= r;
  }
  final r = votes.entries.where((e) => e.value.length >= 2).map((e) => found[e.key]!).firstOrNull;
  if (r == null) return p;
  return PurposeResult(
      purpose: r.purpose,
      level: cap(r.level),
      confidence: 0.6,
      basis: PurposeBasis.web,
      aiPurpose: p.aiPurpose,
      aiConfidence: p.aiConfidence,
      aiReasons: p.aiReasons,
      title: p.title,
      severe: r.severe,
      reasons: ['${votes[r.purpose]!.length} search results describe it: ${r.reasons.join('; ')}']);
}

// ------------------------------------------------------------ cache

/// Site reports per domain for 24 hours.
class SiteCache {
  static const ttl = Duration(hours: 24);
  final bool persist;
  final Map<String, SiteReport> _mem = {};
  SiteCache({this.persist = true});

  static String keyFor(String domain) => 'sitecheck.v1.${sha256.convert(utf8.encode(domain)).toString().substring(0, 32)}';

  Future<SiteReport?> get(String domain, DateTime now) async {
    var r = _mem[domain];
    if (r == null && persist) {
      try {
        final p = await SharedPreferences.getInstance();
        final s = p.getString(keyFor(domain));
        if (s != null) r = SiteReport.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (r == null || r.domain != domain || now.difference(r.checkedAt) > ttl || now.isBefore(r.checkedAt)) return null;
    _mem[domain] = r;
    return r.copyWith(fromCache: true);
  }

  Future<void> put(SiteReport r) async {
    _mem[r.domain] = r;
    if (!persist) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(keyFor(r.domain), jsonEncode(r.toJson()));
    } catch (_) {}
  }

  void clearMemory() => _mem.clear();
}

final siteCache = SiteCache();

// ------------------------------------------------------------ checker

class SiteChecker {
  final http.Client client;
  final LlmConfig llm;
  final ForensicKeys keys;
  final SiteCache cache;

  /// Searches the web for the domain's reputation. Null skips it.
  final WebIntel? webIntel;
  final Duration timeout;
  final DateTime Function() now;
  SiteChecker({
    required this.client,
    this.llm = const LlmConfig(kind: LlmKind.none),
    this.keys = ForensicKeys.none,
    SiteCache? cache,
    this.webIntel,
    this.timeout = const Duration(seconds: 8),
    DateTime Function()? now,
  })  : cache = cache ?? siteCache,
        now = now ?? DateTime.now;

  bool get canAi => llm.usable;

  /// Reads the page in the isolated reader (or uses [page]) and works out
  /// what the site is for. Never throws; offline it reads the address only.
  Future<(PurposeResult, PageSample)> purpose(Uri url, {PageFetch? page, bool network = true, StepLogger? log}) async {
    if (officialBrandFor(url.host.toLowerCase()) != null) {
      final s = PageSample.address(url);
      return (classifyPurpose(s), s);
    }
    var fetched = page;
    if (fetched == null && network) {
      try {
        fetched = await fetchIsolated(url, client: client, timeout: timeout).timeout(timeout * 2);
      } catch (_) {}
    }
    final html = fetched?.html;
    final sample = html != null && (fetched!.status ?? 500) < 500 ? PageSample.fromHtml(html, fetched.finalUrl) : PageSample.address(url);
    var result = classifyPurpose(sample);
    if (canAi && network && sample.fetched && sample.text.length >= 80) {
      final s = log?.call('$purposeTool: AI', 'Asking ${llm.displayName} what the site is for (the page text only, nothing about you)',
          sentOffDevice: llm.leavesDevice);
      final ai = LlmClient(llm, client: client);
      try {
        final j = await ai.completeJson(system: purposeAiSystem, user: sample.forAi(), timeout: const Duration(seconds: 15));
        final parsed = parsePurposeAi(j);
        if (parsed != null) result = mergeAi(result, parsed);
        s
          ?..result = parsed == null
              ? 'AI gave no usable answer'
              : 'AI says: ${purposeLabel(parsed.$1).toLowerCase()} (${(parsed.$2 * 100).round()}% sure)'
          ..status = StepStatus.done;
      } catch (_) {
        s
          ?..result = 'AI unavailable, using the word rules only'
          ..status = StepStatus.failed;
      }
    }
    return (result, sample);
  }

  /// The site's rank in the Tranco top-sites list; null when it is not in
  /// the top million. Throws when Tranco cannot be reached.
  Future<int?> tranco(String domain) async {
    final res = await client.get(trancoUri(domain), headers: {'Accept': 'application/json'}).timeout(timeout);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
    return parseTranco(res.body);
  }

  /// The whole check for one link, logged step by step. [page], [ageDays]
  /// and [listings] reuse what earlier checks found. Never throws.
  Future<SiteReport> check(
    Uri url, {
    PageFetch? page,
    int? ageDays,
    List<ReputationHit>? listings,
    bool network = true,
    bool webSearch = true,
    required StepLogger log,
    void Function()? onChange,
  }) async {
    final host = url.host.toLowerCase();
    final domain = registrableDomain(host);
    final at = now();
    final saved = await cache.get(domain, at);
    if (saved != null) {
      final h = at.difference(saved.checkedAt).inHours;
      log(purposeTool, 'Looking for a saved check of $domain')
        ..result = 'Checked ${h == 0 ? 'less than an hour' : '$h h'} ago, reused (kept 24 h): ${saved.purpose.headline}; reputation ${saved.reputationLabel.toLowerCase()}'
        ..status = StepStatus.done;
      onChange?.call();
      return saved;
    }

    final ps = log(purposeTool, network ? 'Reading $host in the isolated reader to see what the site is for' : 'Reading the address $host to see what the site is for',
        sentOffDevice: network && officialBrandFor(host) == null && page == null);
    onChange?.call();
    final (found, sample) = await purpose(url, page: page, network: network, log: log);
    ps
      ..result = '${found.headline} (${found.confidenceLabel.toLowerCase()} confidence, from ${basisLabel(found.basis).toLowerCase()})'
      ..status = StepStatus.done;
    onChange?.call();

    var checked = false;
    int? rank;
    if (network && officialBrandFor(host) == null) {
      final ts = log(popularityTool, 'Asking the Tranco top-sites list how popular $domain is', sentOffDevice: true);
      onChange?.call();
      try {
        rank = await tranco(domain);
        checked = true;
        ts
          ..result = rank == null ? 'Not in the top 1 million websites' : 'Rank #$rank worldwide${rank <= wellKnownRank ? ' (a well-known site)' : ''}'
          ..status = StepStatus.done;
      } catch (_) {
        ts
          ..result = 'Could not reach Tranco, skipped'
          ..status = StepStatus.failed;
      }
      onChange?.call();
    }

    var hits = listings ?? const <ReputationHit>[];
    if (listings == null && network && officialBrandFor(host) == null && (keys.safeBrowsing.isNotEmpty || keys.virusTotal.isNotEmpty || keys.abuseCh.isNotEmpty)) {
      hits = await checkReputation(url.toString(), keys: keys, client: client, log: log).timeout(timeout * 2, onTimeout: () => const <ReputationHit>[]);
    }

    WebIntelResult? web;
    final w = webIntel;
    if (w != null && network && webSearch) {
      if (officialBrandFor(host) != null || (rank != null && rank <= wellKnownRank)) {
        log(webTool, 'Searching the web for reports about $domain')
          ..result = 'Skipped: a well-known site (pages about it are usually warnings about fakes, not about the site itself)'
          ..status = StepStatus.skipped;
      } else {
        web = await w
            .lookup(WebIdentifier.domain(domain), log: log, onChange: onChange)
            .timeout(timeout * 4, onTimeout: () => WebIntelResult(identifier: WebIdentifier.domain(domain), status: WebStatus.unavailable, checkedAt: at));
      }
    }

    final report = SiteReport(
      domain: domain,
      url: url.toString(),
      purpose: withWebPurpose(found, web, url),
      trancoChecked: checked,
      trancoRank: rank,
      ageDays: ageDays,
      listings: hits,
      web: web,
      mcmcBlocked: sample.mcmcBlocked,
      checkedAt: at,
    );
    final rs = log(reputationTool, 'Combining what the site is for with how the internet sees it');
    rs
      ..result = '${report.levelLabel}: ${report.purpose.headline}. Reputation ${report.reputationLabel.toLowerCase()}'
          '${report.reputationScore == null ? '' : ' (${report.reputationScore}/100)'}'
      ..status = StepStatus.done;
    onChange?.call();
    if (sample.fetched || checked) await cache.put(report);
    return report;
  }
}

// ------------------------------------------------------------ Check tab

/// Findings for the Check tab, pointing at the link's place in the text.
List<Finding> siteFindings(SiteReport r) => [
      for (final x in r.reasons(official: false))
        Finding(category: x.category, title: x.title, explanation: x.why, weight: x.weight, tool: x.isRisk ? purposeTool : reputationTool),
    ];

/// The scam type shown on the result screen for a risky site.
String scamTypeFor(PurposeResult p) => switch (p.purpose) {
      SitePurpose.gambling => 'Illegal online gambling site',
      SitePurpose.investment => p.severe ? 'Investment scam (guaranteed returns)' : 'Investment site',
      SitePurpose.moneyLending => p.severe ? 'Illegal money lending (Ah Long)' : 'Money lending site',
      SitePurpose.fakeShop => 'Fake online shop',
      SitePurpose.phishing => p.brand == null ? 'Account phishing' : '${p.brand} phishing',
      SitePurpose.adult => 'Adult site',
      SitePurpose.piracy => 'Pirated streaming site',
      SitePurpose.jobScam => p.severe ? 'Job task scam' : 'Part-time job offer',
      _ => 'Unclear',
    };

/// The lowest verdict the sites allow.
RiskLevel? siteFloor(List<SiteReport> sites) {
  RiskLevel? out;
  for (final s in sites) {
    for (final r in s.reasons(official: false)) {
      final f = r.floor;
      if (f != null && (out == null || f.index > out.index)) out = f;
    }
  }
  return out;
}

final _bySites = Expando<List<SiteReport>>('sites');

/// Site checks of a finished investigation, for the result screen.
List<SiteReport> sitesOf(Object inv) => _bySites[inv] ?? const [];

void attachSites(Object inv, List<SiteReport> sites) {
  if (sites.isNotEmpty) _bySites[inv] = sites;
}
