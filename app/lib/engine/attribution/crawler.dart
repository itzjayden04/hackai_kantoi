/// Kantoi's passive crawler. It reads public data only: certificate logs,
/// public threat feeds, domain registries, DNS, the front page of suspicious
/// sites (if robots.txt allows) and news feeds. No logins, no forms, no social
/// media profiles and no automated queries to government portals.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../forensics/net_guard.dart';
import '../models.dart';
import '../url_analyzer.dart' show StepLogger;
import 'fingerprint.dart';
import 'intel_models.dart';

const crawlerAgent = 'KantoiBot/1.0 (+https://github.com/itzjayden04/hackai_kantoi; scam research, respects robots.txt)';
const _timeout = Duration(seconds: 12);

/// Brand words watched in Certificate Transparency logs, a few per crawl.
const ctWatchWords = [
  'poslaju', 'maybank2u', 'cimbclicks', 'touchngo', 'jtexpress', 'lhdn', 'myeg', 'pbebank', 'rhbbank', 'bankislam',
  'hasil', 'kwsp', 'shopee', 'lazada', 'mybsn', 'jpj',
];

/// Public news feeds checked for scam stories. Government portals are left
/// out on purpose; their advisories reach users through the news.
const newsFeeds = [
  ('The Star', 'https://www.thestar.com.my/rss/News/Nation'),
  ('Free Malaysia Today', 'https://www.freemalaysiatoday.com/category/nation/feed/'),
  ('Malay Mail', 'https://www.malaymail.com/feed/rss/malaysia'),
];

/// The crawler never sends automated requests to government websites.
bool crawlAllowed(Uri u) {
  final h = u.host.toLowerCase();
  return u.scheme == 'https' || u.scheme == 'http' ? !(h.endsWith('.gov.my') || h == 'gov.my') : false;
}

// ---------------------------------------------------------------- parsers

class CtHit {
  final String domain;
  final String brand;
  final DateTime notBefore;
  final String issuer;
  const CtHit(this.domain, this.brand, this.notBefore, this.issuer);
}

/// New certificates from crt.sh JSON for look-alikes of Malaysian brands,
/// newer than [since]. Official brand domains are dropped.
List<CtHit> parseCrtSh(String body, {required DateTime since}) {
  final out = <String, CtHit>{};
  final List list;
  try {
    list = jsonDecode(body) as List;
  } catch (_) {
    return const [];
  }
  for (final row in list) {
    if (row is! Map) continue;
    final nb = DateTime.tryParse('${row['not_before'] ?? row['entry_timestamp'] ?? ''}');
    if (nb == null || nb.isBefore(since)) continue;
    final names = '${row['name_value'] ?? ''}\n${row['common_name'] ?? ''}'.split(RegExp(r'\s+'));
    for (var n in names) {
      n = n.trim().toLowerCase().replaceFirst('*.', '');
      if (n.isEmpty || !n.contains('.')) continue;
      final key = domainKey(n);
      final brand = key == null ? null : lookalikeBrand(n);
      if (key == null || brand == null || !malaysianBrands.contains(brand)) continue;
      final issuer = RegExp(r'O=([^,]+)').firstMatch('${row['issuer_name'] ?? ''}')?.group(1) ?? '';
      final old = out[key];
      if (old == null || nb.isBefore(old.notBefore)) out[key] = CtHit(key, brand, nb, issuer.replaceAll('"', ''));
    }
  }
  return out.values.toList()..sort((a, b) => b.notBefore.compareTo(a.notBefore));
}

/// OpenPhish community feed: one URL per line. Keeps Malaysian ones.
List<String> parseOpenPhish(String body) =>
    body.split('\n').map((l) => l.trim()).where((l) => l.startsWith('http') && malaysianRelevant(l)).toList();

/// URLhaus "recent URLs" JSON. Keeps Malaysian ones.
List<(String, DateTime?)> parseUrlhaus(String body) {
  try {
    final j = jsonDecode(body) as Map<String, dynamic>;
    return [
      for (final u in (j['urls'] as List? ?? const []))
        if (u is Map && malaysianRelevant('${u['url']}'))
          ('${u['url']}', DateTime.tryParse('${u['date_added'] ?? ''}'.replaceFirst(' UTC', 'Z').replaceFirst(' ', 'T')))
    ];
  } catch (_) {
    return const [];
  }
}

class RdapDomain {
  final String? registrar;
  final DateTime? created;
  final List<String> nameservers;
  const RdapDomain(this.registrar, this.created, this.nameservers);
}

RdapDomain? parseRdapDomain(String body) {
  try {
    final j = jsonDecode(body) as Map<String, dynamic>;
    DateTime? created;
    String? registrar;
    for (final ev in (j['events'] as List? ?? const [])) {
      if (ev is Map && ev['eventAction'] == 'registration') created = DateTime.tryParse('${ev['eventDate']}');
    }
    for (final ent in (j['entities'] as List? ?? const [])) {
      if (ent is Map && (ent['roles'] as List? ?? const []).contains('registrar')) {
        final v = ent['vcardArray'];
        if (v is List && v.length > 1) {
          for (final f in v[1] as List) {
            if (f is List && f.first == 'fn') registrar = f.last.toString();
          }
        }
      }
    }
    final ns = [
      for (final n in (j['nameservers'] as List? ?? const []))
        if (n is Map && n['ldhName'] != null) '${n['ldhName']}'.toLowerCase().replaceFirst(RegExp(r'\.$'), '')
    ];
    return RdapDomain(registrar, created, ns);
  } catch (_) {
    return null;
  }
}

/// Answers from a DNS-over-HTTPS JSON reply (dns.google). [type] 1 = A, 2 = NS.
List<String> parseDoh(String body, int type) {
  try {
    final j = jsonDecode(body) as Map<String, dynamic>;
    return [
      for (final a in (j['Answer'] as List? ?? const []))
        if (a is Map && a['type'] == type) '${a['data']}'.toLowerCase().replaceFirst(RegExp(r'\.$'), '')
    ];
  } catch (_) {
    return const [];
  }
}

/// Hosting network name and country from an RDAP IP reply.
(String?, String?) parseRdapIp(String body) {
  try {
    final j = jsonDecode(body) as Map<String, dynamic>;
    return (j['name'] as String?, j['country'] as String?);
  } catch (_) {
    return (null, null);
  }
}

/// robots.txt rules that apply to Kantoi: the KantoiBot group if present,
/// otherwise the "*" group. Each rule is (allow, path prefix).
List<(bool, String)> parseRobots(String body) {
  final groups = <String, List<(bool, String)>>{};
  var agents = <String>[];
  var inRules = false;
  for (var line in body.split('\n')) {
    line = line.split('#').first.trim();
    if (line.isEmpty) continue;
    final i = line.indexOf(':');
    if (i < 0) continue;
    final k = line.substring(0, i).trim().toLowerCase(), v = line.substring(i + 1).trim();
    if (k == 'user-agent') {
      if (inRules) agents = [];
      inRules = false;
      agents.add(v.toLowerCase());
    } else if (k == 'allow' || k == 'disallow') {
      inRules = true;
      for (final a in agents) {
        final g = groups.putIfAbsent(a, () => []);
        if (v.isNotEmpty) g.add((k == 'allow', v));
      }
    }
  }
  return groups['kantoibot'] ?? groups['*'] ?? const [];
}

/// Longest matching rule wins; no rule means allowed.
bool robotsAllows(List<(bool, String)> rules, String path) {
  (bool, String)? best;
  for (final r in rules) {
    final p = r.$2.replaceAll('*', '');
    if (path.startsWith(p) && (best == null || p.length > best.$2.length)) best = r;
  }
  return best?.$1 ?? true;
}

String? parseTitle(String html) {
  final m = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html);
  final t = m?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t == null || t.isEmpty ? null : _unescape(t);
}

String _unescape(String s) =>
    s.replaceAll('&amp;', '&').replaceAll('&#39;', "'").replaceAll('&quot;', '"').replaceAll('&lt;', '<').replaceAll('&gt;', '>');

/// The favicon address a page declares, or /favicon.ico.
Uri faviconUri(String html, Uri page) {
  for (final m in RegExp(r'<link[^>]+>', caseSensitive: false).allMatches(html)) {
    final tag = m.group(0)!;
    if (!RegExp(r'''rel\s*=\s*["'][^"']*icon''', caseSensitive: false).hasMatch(tag)) continue;
    final href = RegExp(r'''href\s*=\s*["']([^"']+)''', caseSensitive: false).firstMatch(tag)?.group(1);
    if (href != null) return page.resolve(_unescape(href));
  }
  return page.resolve('/favicon.ico');
}

/// A 64-bit average hash of an image as 16 hex digits: similar pictures
/// differ in only a few bits. Falls back to a SHA-256 prefix if the image
/// cannot be decoded.
String imageFingerprint(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      final small = img.grayscale(img.copyResize(decoded, width: 8, height: 8, interpolation: img.Interpolation.average));
      final px = [for (var y = 0; y < 8; y++) for (var x = 0; x < 8; x++) small.getPixel(x, y).r.toInt()];
      final avg = px.reduce((a, b) => a + b) / 64;
      final b = StringBuffer();
      for (var i = 0; i < 64; i += 4) {
        var n = 0;
        for (var j = 0; j < 4; j++) {
          if (px[i + j] >= avg) n |= 8 >> j;
        }
        b.write(n.toRadixString(16));
      }
      return b.toString();
    }
  } catch (_) {}
  return sha256.convert(bytes).toString().substring(0, 16);
}

const _scamWords = [
  'scam', 'scammer', 'penipuan', 'tipu', 'fraud', 'macau', 'mule', 'phishing', 'syndicate', 'sindiket', 'duped', 'cheated',
  'lost rm', 'losses', 'swindle', 'impersonat',
];

/// Names the scam type a headline is about, in the same words as the
/// investigator, or null if it is not a scam story.
String? classifyHeadline(String title) {
  final t = title.toLowerCase();
  if (!_scamWords.any(t.contains)) return null;
  if (t.contains('macau') || t.contains('police') && t.contains('impersonat') || t.contains('officer')) return 'Fake officer (Macau) scam';
  if (t.contains('parcel') || t.contains('courier') || t.contains('pos laju')) return 'Parcel fee scam';
  if (t.contains('job') || t.contains('task') || t.contains('part-time')) return 'Job task scam';
  if (t.contains('love') || t.contains('romance')) return 'Love and investment scam';
  if (t.contains('invest') || t.contains('crypto') || t.contains('trading')) return 'Investment scam';
  if (t.contains('phishing') || t.contains('apk') || t.contains('banking') || t.contains('link')) return 'Bank phishing';
  if (t.contains('mule')) return 'Mule accounts';
  if (t.contains('tax') || t.contains('lhdn') || t.contains('refund')) return 'Tax refund scam';
  return 'Other scams';
}

/// Scam stories from an RSS feed.
List<NewsItem> parseRss(String body, String source) {
  final out = <NewsItem>[];
  for (final m in RegExp(r'<item[\s>][\s\S]*?</item>', caseSensitive: false).allMatches(body)) {
    final item = m.group(0)!;
    String? tag(String name) {
      final x = RegExp('<$name[^>]*>([\\s\\S]*?)</$name>', caseSensitive: false).firstMatch(item)?.group(1);
      if (x == null) return null;
      return _unescape(x.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '').replaceAll(RegExp(r'<[^>]+>'), '').trim());
    }

    final title = tag('title');
    if (title == null) continue;
    final type = classifyHeadline(title);
    if (type == null) continue;
    out.add(NewsItem(title: title, link: tag('link') ?? '', source: source, at: _rfc822(tag('pubDate')) ?? DateTime.now(), scamType: type));
  }
  return out;
}

DateTime? _rfc822(String? s) {
  if (s == null) return null;
  final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2})(?::\d{2})?(?: ([+-])(\d{2})(\d{2}))?').firstMatch(s);
  if (m == null) return DateTime.tryParse(s);
  const mon = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  final mi = mon.indexOf(m.group(2)!.toLowerCase());
  if (mi < 0) return null;
  final t = DateTime.utc(int.parse(m.group(3)!), mi + 1, int.parse(m.group(1)!), int.parse(m.group(4)!), int.parse(m.group(5)!));
  if (m.group(6) == null) return t;
  final off = Duration(hours: int.parse(m.group(7)!), minutes: int.parse(m.group(8)!));
  return m.group(6) == '+' ? t.subtract(off) : t.add(off);
}

// ---------------------------------------------------------------- fetching

/// Fetches with a timeout, a size cap and Kantoi's own user agent. Throws on
/// anything other than a 200 reply.
Future<String> fetchText(http.Client c, Uri u, {Map<String, String> headers = const {}, int maxBytes = 3 << 20, Duration timeout = _timeout}) async {
  final bytes = await fetchBytes(c, u, headers: headers, maxBytes: maxBytes, timeout: timeout);
  return utf8.decode(bytes, allowMalformed: true);
}

Future<Uint8List> fetchBytes(http.Client c, Uri u, {Map<String, String> headers = const {}, int maxBytes = 3 << 20, Duration timeout = _timeout}) async {
  if (!crawlAllowed(u)) throw StateError('Government website, not crawled');
  await ensurePublicHost(u);
  final req = http.Request('GET', u)
    ..followRedirects = true
    ..maxRedirects = 4
    ..headers.addAll({'User-Agent': crawlerAgent, ...headers});
  final res = await c.send(req).timeout(timeout);
  if (res.statusCode != 200) {
    unawaited(res.stream.drain<void>().catchError((_) {}));
    throw StateError('HTTP ${res.statusCode}');
  }
  final b = BytesBuilder(copy: false);
  await for (final chunk in res.stream.timeout(timeout)) {
    b.add(chunk);
    if (b.length > maxBytes) break;
  }
  return b.takeBytes();
}

/// Checks robots.txt before fetching a page. A missing robots.txt allows
/// everything; one that cannot be read is treated as "no".
Future<bool> robotsOk(http.Client c, Uri page, Map<String, List<(bool, String)>> cache) async {
  final origin = '${page.scheme}://${page.authority}';
  var rules = cache[origin];
  if (rules == null) {
    try {
      await ensurePublicHost(page);
      final req = http.Request('GET', Uri.parse('$origin/robots.txt'))..headers['User-Agent'] = crawlerAgent;
      final res = await c.send(req).timeout(const Duration(seconds: 6));
      final body = await res.stream.bytesToString().timeout(const Duration(seconds: 6));
      rules = res.statusCode == 200 ? parseRobots(body) : const [];
      if (res.statusCode >= 500) return false;
    } catch (_) {
      return false;
    }
    cache[origin] = rules;
  }
  return robotsAllows(rules, page.path.isEmpty ? '/' : page.path);
}

class DomainFacts {
  String? registrar;
  DateTime? created;
  List<String> nameservers = [];
  List<String> ips = [];
  String? network;
  String? country;
  bool get any => registrar != null || created != null || nameservers.isNotEmpty || ips.isNotEmpty;
}

/// Registration (RDAP), nameservers and addresses (DNS over HTTPS) and the
/// hosting network (RDAP for the address). Each part fails on its own.
Future<DomainFacts> lookupDomain(http.Client c, String domain, {bool registry = true}) async {
  final f = DomainFacts();
  Future<void> part(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {}
  }

  await Future.wait([
    if (registry)
      part(() async {
        final r = parseRdapDomain(await fetchText(c, Uri.parse('https://rdap.org/domain/$domain'), timeout: const Duration(seconds: 8)));
        if (r == null) return;
        f
          ..registrar = r.registrar
          ..created = r.created;
        if (r.nameservers.isNotEmpty) f.nameservers = r.nameservers;
      }),
    part(() async {
      final ns = parseDoh(await fetchText(c, Uri.parse('https://dns.google/resolve?name=$domain&type=NS'), timeout: const Duration(seconds: 5)), 2);
      if (ns.isNotEmpty) f.nameservers = ns;
    }),
    part(() async {
      f.ips = parseDoh(await fetchText(c, Uri.parse('https://dns.google/resolve?name=$domain&type=A'), timeout: const Duration(seconds: 5)), 1)
          .where((ip) => RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip))
          .take(4)
          .toList();
    }),
  ]);
  f.nameservers.sort();
  if (f.ips.isNotEmpty) {
    await part(() async {
      final (net, cc) = parseRdapIp(await fetchText(c, Uri.parse('https://rdap.org/ip/${f.ips.first}'), timeout: const Duration(seconds: 8)));
      f
        ..network = net
        ..country = cc;
    });
  }
  return f;
}

class PageSnapshot {
  final String? title;
  final int shape;
  final String? favicon;
  const PageSnapshot(this.title, this.shape, this.favicon);
}

/// The front page only: title, page shape and favicon fingerprint. No forms
/// are filled, no links followed, nothing logged in to.
Future<PageSnapshot?> snapshotPage(http.Client c, String domain, Map<String, List<(bool, String)>> robots) async {
  final page = Uri.parse('https://$domain/');
  if (!await robotsOk(c, page, robots)) return null;
  final html = await fetchText(c, page, maxBytes: 400 << 10, timeout: const Duration(seconds: 8));
  String? icon;
  try {
    final iu = faviconUri(html, page);
    if (await robotsOk(c, iu, robots)) {
      icon = imageFingerprint(await fetchBytes(c, iu, maxBytes: 200 << 10, timeout: const Duration(seconds: 6)));
    }
  } catch (_) {}
  return PageSnapshot(parseTitle(html), pageShape(html), icon);
}

/// Runs one step of the crawl and records it in the activity log. A failure
/// is logged and the crawl carries on.
Future<T?> crawlStep<T>(StepLogger log, String tool, String action, Future<T> Function() run, String Function(T) describe) async {
  final s = log(tool, action, sentOffDevice: true);
  try {
    final r = await run();
    s
      ..result = describe(r)
      ..status = StepStatus.done;
    return r;
  } catch (e) {
    s
      ..result = 'Could not reach it, skipped (${e.toString().split('\n').first})'
      ..status = StepStatus.failed;
    return null;
  }
}
