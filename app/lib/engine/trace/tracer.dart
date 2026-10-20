/// The live trace: starting from a link, number, account, email or message,
/// Kantoi runs real passive lookups one after another and builds a map of
/// what it finds. Every lookup is logged, times out on its own and fails
/// soft, so the trace always finishes, even offline. No active scanning.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../attribution/crawler.dart' show fetchText, parseDoh, parseRdapDomain;
import '../attribution/fingerprint.dart' show domainKey, lookalikeBrand, phoneKey, accountKey;
import '../attribution/graph.dart' show IntelGraph, shortDate;
import '../attribution/intel_models.dart';
import '../forensics/allowlist.dart' show matchSender;
import '../forensics/hop_facts.dart' show parseIpRdap, parseIpWhoIs;
import '../forensics/keys.dart';
import '../forensics/reputation.dart';
import '../forensics/tls_info.dart';
import '../models.dart';
import '../url_analyzer.dart' show analyzeUrl, brands, officialBrandFor, registrableDomain;
import 'trace_input.dart';
import 'trace_models.dart';

const semakMuleUrl = 'https://semakmule.rmp.gov.my/';

const _freeMail = {
  'gmail.com', 'yahoo.com', 'yahoo.com.my', 'hotmail.com', 'outlook.com', 'live.com', 'icloud.com', 'proton.me',
  'protonmail.com', 'aol.com', 'mail.com', 'gmx.com', 'yandex.com', 'qq.com', '163.com', 'zoho.com',
};

final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

class Tracer {
  final http.Client client;
  /// The local intel store, for links to known scam cases.
  final IntelGraph? graph;
  final ForensicKeys keys;
  /// Reads a site's certificate over a raw socket. Null skips the check.
  final Future<TlsInfo?> Function(String host)? tlsProbe;
  final Duration timeout;
  final Duration slowTimeout;
  final int maxNodes;
  /// A short pause between lookups so each one can be seen on the map.
  final Duration pace;

  Tracer({
    required this.client,
    this.graph,
    this.keys = ForensicKeys.none,
    this.tlsProbe,
    this.timeout = const Duration(seconds: 7),
    this.slowTimeout = const Duration(seconds: 12),
    this.maxNodes = 60,
    this.pace = Duration.zero,
  });

  final _out = StreamController<TraceEvent>();
  final Map<String, TraceNode> _nodes = {};
  final Set<String> _edges = {};
  int _ids = 0, _done = 0, _total = 0;
  bool _paused = false, _cancelled = false, _fullLogged = false;
  Completer<void>? _resume;
  TraceLookup? _last;

  bool get paused => _paused;

  void pause() => _paused = true;

  void resume() {
    _paused = false;
    _resume?.complete();
    _resume = null;
  }

  void cancel() {
    _cancelled = true;
    resume();
  }

  /// Starts the trace. Listen once; the stream closes after [TraceFinished].
  Stream<TraceEvent> run(String input) {
    unawaited(_go(input));
    return _out.stream;
  }

  void _emit(TraceEvent e) {
    if (!_out.isClosed) _out.add(e);
  }

  Future<void> _go(String input) async {
    try {
      final parsed = parseTraceInput(input);
      final seeds = parsed.seeds;
      final what = parsed.message
          ? 'Message'
          : seeds.isEmpty
              ? 'Text'
              : switch (seeds.first.kind) {
                  SeedKind.url => 'Link',
                  SeedKind.phone => 'Phone number',
                  SeedKind.account => 'Bank account',
                  SeedKind.email => 'Email address',
                };
      _emit(TraceStarted(input.trim(), what));
      String? parent;
      if (parsed.message || seeds.isEmpty) {
        final preview = input.trim().replaceAll(RegExp(r'\s+'), ' ');
        parent = _node(TraceKind.message, 'msg', preview.length > 40 ? '${preview.substring(0, 39)}…' : preview);
        await _lookup<List<TraceSeed>>('Entity extractor', 'Pulling links, numbers, accounts and emails out of the message',
            online: false, nodeId: parent, run: () async => seeds, describe: (s) {
          if (s.isEmpty) return 'Found nothing to trace. Paste a link, phone number, bank account or email.';
          final n = <String, int>{};
          for (final x in s) {
            n[x.kind.name] = (n[x.kind.name] ?? 0) + 1;
          }
          return 'Found ${n.entries.map((e) => '${e.value} ${_seedWord(e.key, e.value)}').join(', ')}';
        });
      }
      for (final s in seeds) {
        if (_cancelled) break;
        switch (s.kind) {
          case SeedKind.url:
            await _traceUrl(s.value, parent);
          case SeedKind.phone:
            await _tracePhone(s.value, parent);
          case SeedKind.account:
            await _traceAccount(s.value, parent);
          case SeedKind.email:
            await _traceEmail(s.value, parent);
        }
      }
    } catch (_) {
      // A bug in one step must never leave the trace hanging.
    }
    _emit(TraceFinished(cancelled: _cancelled));
    await _out.close();
  }

  static String _seedWord(String kind, int n) => switch (kind) {
        'url' => n == 1 ? 'link' : 'links',
        'phone' => n == 1 ? 'phone number' : 'phone numbers',
        'account' => n == 1 ? 'bank account' : 'bank accounts',
        _ => n == 1 ? 'email' : 'emails',
      };

  // ------------------------------------------------------------ plumbing

  /// Adds a node (or returns the existing one) linked from [parent]. Null
  /// when the map is full.
  String? _node(TraceKind kind, String key, String label,
      {String? parent, String edge = '', bool flagged = false, bool demo = false, String? country, List<(String, String)> facts = const []}) {
    final id = '${kind.name}:$key';
    var n = _nodes[id];
    if (n == null) {
      if (_nodes.length >= maxNodes) {
        if (!_fullLogged) {
          _fullLogged = true;
          final s = LogStep(tool: 'Map', action: 'Adding more to the map', result: 'The map is full ($maxNodes items). The rest are left out to keep it readable.', status: StepStatus.skipped);
          _emit(TraceLookupEvent(TraceLookup(_ids++, s, null)));
        }
        return null;
      }
      n = TraceNode(id: id, kind: kind, label: label, parent: parent, flagged: flagged, demo: demo, country: country);
      _nodes[id] = n;
    } else if (flagged) {
      n.flagged = true;
    }
    for (final (k, v) in facts) {
      n.addFact(k, v);
    }
    _emit(TraceNodeEvent(n));
    if (parent != null && parent != id && _nodes.containsKey(parent) && _edges.add('$parent>$id')) {
      _emit(TraceEdgeEvent(TraceEdge(parent, id, edge)));
    }
    return id;
  }

  void _fact(String? id, String k, String v) {
    final n = id == null ? null : _nodes[id];
    if (n == null) return;
    n.addFact(k, v);
    _emit(TraceNodeEvent(n));
  }

  void _flag(String title, String why, int weight, {String? nodeId, bool demo = false}) {
    if (nodeId != null && weight > 0) {
      final n = _nodes[nodeId];
      if (n != null) {
        n.flagged = true;
        _emit(TraceNodeEvent(n));
      }
    }
    // A strong warning turns the lookup that found it red in the feed.
    final l = _last;
    if (weight >= 10 && l != null && !l.alarming) {
      l.alarming = true;
      _emit(TraceLookupEvent(l));
    }
    _emit(TraceFlagEvent(TraceFlag(title, why, weight, nodeId: nodeId, demo: demo)));
  }

  Future<void> _gate() async {
    while (_paused && !_cancelled) {
      _resume ??= Completer<void>();
      await _resume!.future;
    }
  }

  /// Runs one lookup with its own timeout and logs it. Returns null when it
  /// failed or timed out; the trace carries on either way.
  Future<T?> _lookup<T>(String tool, String asked,
      {required bool online, String? nodeId, required Future<T> Function() run, required String Function(T) describe, Duration? limit}) async {
    _total++;
    _emit(TraceProgressEvent(_done, _total));
    await _gate();
    if (_cancelled) return null;
    final l = TraceLookup(_ids++, LogStep(tool: tool, action: asked, sentOffDevice: online), nodeId);
    _emit(TraceLookupEvent(l));
    final wait = limit ?? timeout;
    T? r;
    try {
      r = await run().timeout(wait);
      l.step
        ..result = describe(r as T)
        ..status = StepStatus.done;
    } on TimeoutException {
      l.step
        ..result = 'No answer within ${wait.inSeconds} s, skipped'
        ..status = StepStatus.failed;
    } catch (e) {
      l.step
        ..result = online ? 'Could not reach it (offline or blocked), skipped' : 'Could not check it, skipped'
        ..status = StepStatus.failed;
    }
    _done++;
    _last = l;
    _emit(TraceLookupEvent(l));
    _emit(TraceProgressEvent(_done, _total));
    if (pace > Duration.zero) await Future<void>.delayed(pace);
    return r;
  }

  Future<String> _get(Uri u, {Map<String, String> headers = const {}}) async {
    final res = await client.get(u, headers: headers);
    if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
    return res.body;
  }

  // ------------------------------------------------------------ links

  Future<void> _traceUrl(String raw, String? parent) async {
    var text = raw.trim();
    if (!RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(text)) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return;
    final start = _node(TraceKind.url, uri.toString(), _short(uri), parent: parent, edge: 'contains link');

    var (brand, official) = await _lookalike(text, start);

    // Redirect chain.
    final hops = await _lookup<List<(Uri, int?)>>('Redirect follower', 'Following where ${uri.host} leads, one hop at a time (page not opened)',
        online: true, nodeId: start, run: () => _redirects(uri), describe: (h) {
      if (h.length <= 1) return 'No redirects (status ${h.firstOrNull?.$2 ?? '?'})';
      return '${h.length - 1} redirect(s), ends at ${h.last.$1.host}';
    });
    var last = start;
    final hosts = <String>[uri.host.toLowerCase()];
    if (hops != null) {
      _fact(start, 'Answer', hops.first.$2 == null ? 'no answer' : 'HTTP ${hops.first.$2}');
      for (final (u, status) in hops.skip(1).take(6)) {
        last = _node(TraceKind.url, u.toString(), _short(u), parent: last, edge: 'redirects to', facts: [('Answer', status == null ? 'no answer' : 'HTTP $status')]) ?? last;
        if (u.host.isNotEmpty && !hosts.contains(u.host.toLowerCase())) hosts.add(u.host.toLowerCase());
      }
      if (hops.length > 1) {
        final fin = hops.last.$1;
        if (registrableDomain(fin.host.toLowerCase()) != registrableDomain(uri.host.toLowerCase())) {
          final (b, o) = await _lookalike(fin.toString(), last);
          brand ??= b;
          official = o;
        }
      }
    }

    // Reputation services, only when a key is set.
    if (keys.safeBrowsing.isNotEmpty || keys.virusTotal.isNotEmpty || keys.abuseCh.isNotEmpty) {
      final target = hops?.last.$1.toString() ?? uri.toString();
      final steps = <TraceLookup>[];
      _total++;
      await _gate();
      final hits = await checkReputation(target, keys: keys, client: client, log: (tool, action, {bool sentOffDevice = false}) {
        final l = TraceLookup(_ids++, LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice), last);
        steps.add(l);
        _emit(TraceLookupEvent(l));
        return l.step;
      }).timeout(slowTimeout, onTimeout: () => <ReputationHit>[]);
      for (final s in steps) {
        if (s.step.status == StepStatus.running) {
          s.step
            ..result = 'No answer in time, skipped'
            ..status = StepStatus.failed;
        }
        _emit(TraceLookupEvent(s));
      }
      _done++;
      _emit(TraceProgressEvent(_done, _total));
      for (final h in hits) {
        _flag('Listed by ${h.service}', h.summary, h.weight, nodeId: last);
      }
    }

    // Each website in the chain.
    final domains = <String>[];
    for (final h in hosts) {
      if (_ipv4.hasMatch(h)) {
        await _traceIp(h, last ?? start);
        continue;
      }
      final d = registrableDomain(h);
      if (!domains.contains(d)) domains.add(d);
    }
    for (final d in domains.take(3)) {
      if (_cancelled) return;
      final host = hosts.firstWhere((h) => registrableDomain(h) == d, orElse: () => d);
      final from = hops == null ? start : _nodes.keys.where((k) => k.startsWith('url:') && Uri.tryParse(k.substring(4))?.host.toLowerCase() == host).lastOrNull;
      await _traceDomain(d, host, from ?? start, brand: brand, official: official || officialBrandFor(d) != null);
    }
  }

  /// The look-alike check, on the phone: brand names, look-alike letters,
  /// risky endings and the official domain list.
  Future<(String?, bool)> _lookalike(String text, String? nodeId) async {
    final host = Uri.tryParse(text)?.host ?? text;
    final st = await _lookup('Look-alike check', 'Comparing $host with official bank, courier and agency websites (look-alike letters too)',
        online: false, nodeId: nodeId, run: () => analyzeUrl(text, log: _noLog, network: false), describe: (a) {
      if (a.report.official) return 'Official website';
      final risks = a.findings.where((f) => f.isRisk).map((f) => f.title).toList();
      return risks.isEmpty ? 'No look-alike signs in the address' : risks.join('; ');
    });
    if (st == null) return (null, false);
    for (final f in st.findings) {
      _flag(f.title, f.explanation, f.weight, nodeId: f.isRisk ? nodeId : null);
    }
    final brand = st.report.imitates;
    if (brand != null) {
      _node(TraceKind.brand, brand, 'Imitates $brand', parent: nodeId, edge: 'pretends to be', flagged: true, facts: [
        ('Brand', brand),
        ('Official websites', (brands[brand] ?? const []).join(', ')),
      ]);
    }
    return (brand, st.report.official);
  }

  static LogStep _noLog(String tool, String action, {bool sentOffDevice = false}) => LogStep(tool: tool, action: action);

  Future<List<(Uri, int?)>> _redirects(Uri start) async {
    final hops = <(Uri, int?)>[];
    var current = start;
    for (var i = 0; i < 8; i++) {
      final req = http.Request('GET', current)
        ..followRedirects = false
        ..headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';
      final res = await client.send(req).timeout(timeout);
      // Headers only: the page itself is never downloaded.
      try {
        await res.stream.listen(null).cancel();
      } catch (_) {}
      hops.add((current, res.statusCode));
      final loc = res.headers['location'];
      if (res.statusCode >= 300 && res.statusCode < 400 && loc != null) {
        current = current.resolve(loc.trim());
        continue;
      }
      break;
    }
    return hops;
  }

  static String _short(Uri u) {
    final p = u.path.length > 1 ? u.path : '';
    final s = '${u.host}$p';
    return s.length > 34 ? '${s.substring(0, 33)}…' : s;
  }

  // ------------------------------------------------------------ websites

  Future<void> _traceDomain(String domain, String host, String? parent, {String? brand, bool official = false}) async {
    final id = _node(TraceKind.domain, domain, domain, parent: parent, edge: 'on website');
    if (id == null) return;
    if (official) _fact(id, 'Official', 'Listed as an official website of ${officialBrandFor(domain) ?? 'a known brand'}');

    // Registration (RDAP).
    final rdap = await _lookup('Domain registry (RDAP)', 'Asking the registry when $domain was registered and by whom',
        online: true, nodeId: id, run: () async => parseRdapDomain(await _get(Uri.parse('https://rdap.org/domain/$domain'), headers: {'Accept': 'application/rdap+json'})),
        describe: (r) {
      if (r == null) return 'No public record';
      final age = r.created == null ? null : DateTime.now().difference(r.created!).inDays;
      return [
        if (age != null) 'Registered ${_ago(age)} (${shortDate(r.created!)})' else 'No registration date published',
        if (r.registrar != null) 'via ${r.registrar}',
      ].join(' ');
    });
    final ns = <String>{};
    if (rdap != null) {
      if (rdap.created != null) {
        final age = DateTime.now().difference(rdap.created!).inDays;
        _fact(id, 'Registered', '${shortDate(rdap.created!)} (${_ago(age)})');
        if (!official) {
          if (age < 30) {
            _flag('Brand-new website', '$domain was registered only ${_ago(age)}. Scam sites are usually days or weeks old.', 22, nodeId: id);
          } else if (age < 180) {
            _flag('Young website', '$domain is less than 6 months old.', 8, nodeId: id);
          } else if (age > 365 * 3) {
            _flag('Long-established website', '$domain has existed for over ${age ~/ 365} years.', -6, nodeId: id);
          }
        }
      }
      if (rdap.registrar != null) _fact(id, 'Registrar', rdap.registrar!);
      ns.addAll(rdap.nameservers);
    }

    // DNS over HTTPS, all four record types at once.
    Future<List<String>?> dig(String type, int code) => _lookup<List<String>>('DNS (dns.google)', '$type records for $domain over DNS-over-HTTPS',
            online: true, nodeId: id, run: () async {
          final body = await _get(Uri.https('dns.google', '/resolve', {'name': domain, 'type': type}), headers: {'Accept': 'application/dns-json'});
          return parseDoh(body, code);
        }, describe: (a) => a.isEmpty ? 'No $type records' : a.take(4).join(', '));
    final dns = await Future.wait([dig('A', 1), dig('AAAA', 28), dig('NS', 2), dig('MX', 15)]);
    final a = (dns[0] ?? const <String>[]).where(_ipv4.hasMatch).take(3).toList();
    final aaaa = (dns[1] ?? const <String>[]).take(1).toList();
    ns.addAll(dns[2] ?? const []);
    final mx = [for (final m in dns[3] ?? const <String>[]) m.split(' ').last].where((m) => m.contains('.')).take(2).toList();
    for (final n in ns.take(3)) {
      _node(TraceKind.nameserver, n, n, parent: id, edge: 'nameserver');
    }
    for (final m in mx) {
      _node(TraceKind.mail, m, m, parent: id, edge: 'mail server');
    }
    if (dns.every((x) => x != null) && a.isEmpty && aaaa.isEmpty && !official) {
      _fact(id, 'Address', 'No server address: the site may already be taken down');
    }
    for (final ip in [...a, ...aaaa]) {
      _node(TraceKind.ip, ip, ip, parent: id, edge: 'resolves to');
    }
    for (final ip in a.take(2)) {
      await _ipOwner(ip);
    }

    // Certificate, read over a raw TLS connection (nothing is sent).
    final probe = tlsProbe;
    if (probe != null) {
      final cert = await _lookup<TlsInfo?>('TLS certificate', 'Reading the security certificate $host shows (connect, read, disconnect)',
          online: true, nodeId: id, run: () => probe(host), describe: (c) {
        if (c == null) return 'No certificate';
        return '${c.issuerName}, issued ${_ago(DateTime.now().difference(c.validFrom).inDays)}${c.trusted ? '' : ', NOT trusted'}';
      });
      if (cert != null) {
        final age = DateTime.now().difference(cert.validFrom).inDays;
        final c = _node(TraceKind.cert, '${cert.issuerName}|${cert.validFrom.toIso8601String()}', cert.issuerName, parent: id, edge: 'certificate', facts: [
          ('Issued by', cert.issuerName),
          ('Issued to', cert.subject),
          ('Valid', '${shortDate(cert.validFrom)} to ${shortDate(cert.validTo)}'),
          ('Trusted by the phone', cert.trusted ? 'Yes' : 'No'),
        ]);
        if (!official) {
          if (!cert.trusted) _flag('Broken security certificate', 'The certificate of $host is not trusted (expired, self-made or for another name).', 10, nodeId: c);
          if (age <= 7 && brand != null) {
            _flag('Brand-new certificate', 'The certificate of $host was issued ${_ago(age)} and the site imitates $brand.', 12, nodeId: c);
          }
          if (cert.freeIssuer && brand != null) {
            _flag('Free certificate on a "$brand" site', '$host uses a free automatic certificate (${cert.issuerName}). Real banks show their verified company name.', 4, nodeId: c);
          }
        }
      }
    }

    // Certificate Transparency: other names on this domain's certificates.
    if (!official) {
      final ct = await _lookup<CtNames>('Certificate logs (crt.sh)', 'Searching public certificate logs for names under $domain',
          online: true, nodeId: id, limit: slowTimeout, run: () async {
        final body = await fetchText(client, Uri.parse('https://crt.sh/?q=${Uri.encodeQueryComponent('%.$domain')}&output=json'),
            maxBytes: 1536 << 10, timeout: slowTimeout);
        return parseCtNames(body, domain);
      }, describe: (c) => c.certs == 0
          ? 'No certificates logged'
          : '${c.certs} certificate(s), ${c.subdomains.length} sub-domain(s), ${c.siblings.length} other website(s) on the same certificates');
      if (ct != null) {
        if (ct.first != null) _fact(id, 'First certificate logged', shortDate(ct.first!));
        for (final s in ct.subdomains.take(5)) {
          _node(TraceKind.subdomain, s, s, parent: id, edge: 'sub-domain');
        }
        for (final s in ct.siblings.take(4)) {
          final b = lookalikeBrand(s);
          final sid = _node(TraceKind.sibling, s, s, parent: id, edge: 'same certificate', facts: [if (b != null) ('Imitates', b)]);
          if (b != null) _flag('Shares a certificate with a $b look-alike', '$domain is on the same certificate as $s, which imitates $b.', 10, nodeId: sid);
        }
      }
    }

    // Kantoi's own scam map, on the phone.
    await _intelDomain(domain, id, [...a], ns.toList());
  }

  Future<void> _ipOwner(String ip) async {
    final id = 'ip:$ip';
    final who = await _lookup<(String?, String?)>('IP owner (ipwho.is)', 'Which network and country $ip belongs to',
        online: true, nodeId: id, run: () async => parseIpWhoIs(await _get(Uri.parse('https://ipwho.is/$ip'))), describe: _ownerText);
    var (net, cc) = who ?? (null, null);
    if (net == null || cc == null) {
      final r = await _lookup<(String?, String?)>('IP registry (RDAP)', 'Asking the internet registry who holds $ip',
          online: true, nodeId: id, run: () async => parseIpRdap(await _get(Uri.parse('https://rdap.org/ip/$ip'), headers: {'Accept': 'application/rdap+json'})),
          describe: _ownerText);
      net ??= r?.$1;
      cc ??= r?.$2;
    }
    String? host;
    if (net != null) {
      host = _node(TraceKind.hosting, net.toLowerCase(), net, parent: id, edge: 'run by', facts: [('Network', net)]);
      _fact(id, 'Network', net);
    }
    if (cc != null) {
      _fact(id, 'Country', countryName(cc));
      _node(TraceKind.country, cc, countryName(cc), parent: host ?? id, edge: 'located in', country: cc);
    }
  }

  static String _ownerText((String?, String?) r) {
    final (n, c) = r;
    if (n == null && c == null) return 'No owner details';
    return [n, if (c != null) countryName(c)].whereType<String>().join(', ');
  }

  Future<void> _traceIp(String ip, String? parent) async {
    _node(TraceKind.ip, ip, ip, parent: parent, edge: 'points to');
    _flag('Bare IP address', 'The link points to a raw number address instead of a named website. Real companies do not do this.', 14, nodeId: 'ip:$ip');
    await _ipOwner(ip);
  }

  Future<void> _intelDomain(String domain, String id, List<String> ips, List<String> ns) async {
    final g = graph;
    if (g == null) return;
    final key = domainKey(domain);
    final self = key == null ? null : g.nodes['domain:$key'];
    final hits = await _lookup<List<(IntelEntity, IntelEdge)>>(
        'Kantoi scam map', 'Looking for $domain, its servers and nameservers in scam cases saved on this phone',
        online: false, nodeId: id, run: () async {
      final probe = IntelEntity(type: NodeType.domain, key: key ?? domain, source: IntelSource.seen, firstSeen: DateTime.now(), ips: ips, nameservers: ns);
      final out = <(IntelEntity, IntelEdge)>[];
      for (final e in g.linksFor(probe, probe: true)) {
        final other = g.nodes[e.other(probe.id)];
        if (e.strength < 0.5 || other == null || other.type != NodeType.domain || other.source == IntelSource.seen || other.id == self?.id) continue;
        out.add((other, e));
        if (out.length >= 5) break;
      }
      return out;
    }, describe: (m) {
      final known = self != null && self.source != IntelSource.seen;
      if (!known && m.isEmpty) return 'No links to saved scam cases';
      final demo = (known && self.synthetic) || m.any((x) => x.$1.synthetic);
      return [if (known) 'This website is in the scam map', if (m.isNotEmpty) 'shares servers with ${m.length} known scam website(s)'].join(', ') +
          (demo ? ' (demo data)' : '');
    });
    if (self != null && self.source != IntelSource.seen) _relatedCase(self, id, 'This website is in the scam map');
    for (final (other, e) in hits ?? const <(IntelEntity, IntelEdge)>[]) {
      final oid = _node(TraceKind.related, other.id, other.display, parent: id, edge: edgeLabel(e.kind).toLowerCase(), demo: other.synthetic, flagged: true, facts: [
        ('Why linked', e.evidence),
        ('Source', sourceLabel(other.source)),
        if (other.brand != null) ('Imitates', other.brand!),
        if (other.synthetic) ('Note', 'Demo data, not a real report'),
      ]);
      _flag('Linked to a known scam website', '${e.evidence}.${other.synthetic ? ' (demo data)' : ''}', other.synthetic ? 6 : 14, nodeId: oid, demo: other.synthetic);
    }
  }

  Future<List<IntelEntity>> _intelHits(List<String> ids) async {
    final g = graph;
    if (g == null) return const [];
    return [for (final i in ids) ?g.nodes[i]].where((e) => e.source != IntelSource.seen).toList();
  }

  void _relatedCase(IntelEntity e, String parent, String why) {
    final g = graph!;
    final c = g.campaignOf[e.id];
    final reports = g.reports.where((r) => r.entityIds.contains(e.id)).length;
    final label = c?.label ?? '${nodeTypeLabel(e.type)} in the scam map';
    final id = _node(TraceKind.related, c?.id ?? e.id, label, parent: parent, edge: 'known case', demo: e.synthetic, flagged: true, facts: [
      ('Why linked', why),
      ('Source', sourceLabel(e.source)),
      if (reports > 0) ('Reports saved on this phone', '$reports'),
      if (c != null) ('Scam type', c.scamType),
      if (c != null) ('First seen', shortDate(c.firstSeen)),
      if (e.synthetic) ('Note', 'Demo data, not a real report'),
    ]);
    _flag(e.synthetic ? 'Matches a demo scam case' : 'Already in the scam map',
        '$why${c == null ? '' : ': "${c.label}"'}.${e.synthetic ? ' (demo data)' : ''}', e.synthetic ? 10 : 30,
        nodeId: id, demo: e.synthetic);
  }

  // ------------------------------------------------------------ numbers

  Future<void> _tracePhone(String raw, String? parent) async {
    final p = analyzePhone(raw);
    final id = _node(TraceKind.phone, p.digits, p.display, parent: parent, edge: 'contains number');
    if (id == null) return;
    await _lookup<PhoneInfo>('Number format check', 'Reading ${p.display} by its format: country code and line type',
        online: false, nodeId: id, run: () async => p, describe: (p) => [
              p.country == null ? (p.callingCode.isEmpty ? 'Unknown country code' : 'Country code +${p.callingCode}') : '${countryName(p.country!)} (+${p.callingCode})',
              p.lineType,
              if (p.area != null) p.area!,
            ].join(', '));
    _fact(id, 'Line type', p.lineType);
    if (p.area != null) _fact(id, 'Area (by prefix)', p.area!);
    if (p.callingCode.isNotEmpty) _fact(id, 'Country code', '+${p.callingCode}');
    if (p.country != null) {
      _node(TraceKind.country, p.country!, countryName(p.country!), parent: id, edge: 'country code', country: p.country);
    }
    if (p.country != null && !p.malaysian) {
      _flag('Overseas number', '${p.display} is a ${countryName(p.country!)} number. Malaysian banks, couriers and police do not call from overseas numbers.', 6, nodeId: id);
    }
    if (p.lineType.startsWith('Internet phone')) {
      _flag('Internet phone number', 'Numbers starting 015 are internet (VoIP) lines, easy to get without meeting anyone. They are often used for fake officer calls.', 4, nodeId: id);
    }
    _fact(id, 'Carrier', 'Not shown: Malaysian numbers can move between networks, so the prefix does not tell the carrier');

    final off = await _lookup('Official contacts list', 'Checking ${p.display} against official bank, courier and agency hotlines',
        online: false, nodeId: id, run: () async => matchSender(raw), describe: (m) => m == null ? 'Not an official hotline Kantoi knows' : "${m.$1.brand}'s official ${m.$2}");
    if (off != null) {
      _fact(id, 'Official', "${off.$1.brand}'s ${off.$2}");
      _flag("${off.$1.brand}'s official number", '${p.display} is listed as ${off.$1.brand}\'s ${off.$2}. Scammers can fake caller ID, so call it back yourself.', -10, nodeId: id);
    }

    final hits = await _lookup('Kantoi scam map', 'Looking for ${p.display} in scam cases saved on this phone',
        online: false, nodeId: id, run: () => _intelHits(['phone:${phoneKey(p.digits)}']), describe: (h) => h.isEmpty ? 'Not in saved scam cases' : 'Found in saved scam cases${h.any((e) => e.synthetic) ? ' (demo data)' : ''}');
    for (final h in hits ?? const <IntelEntity>[]) {
      _relatedCase(h, id, 'This number is in the scam map');
    }
    _semakMuleNote(id, p.display);
  }

  Future<void> _traceAccount(String raw, String? parent) async {
    final a = analyzeAccount(raw);
    final id = _node(TraceKind.account, a.digits, 'Account ${a.masked}', parent: parent, edge: 'contains account');
    if (id == null) return;
    await _lookup<AccountInfo>('Account pattern check', 'Checking the shape of the account number (${a.digits.length} digits)',
        online: false, nodeId: id, run: () async => a, describe: (a) => [
              a.banksByLength.isEmpty ? 'Length does not match a common Malaysian bank' : 'Length used by ${a.banksByLength.join(', ')}',
              ...a.oddities,
            ].join('; '));
    _fact(id, 'Digits', '${a.digits.length}');
    if (a.banksByLength.isNotEmpty) _fact(id, 'Length used by', '${a.banksByLength.join(', ')} (length alone does not prove the bank)');
    _fact(id, 'Owner', 'Not shown: mule accounts are often held by people tricked into lending them');
    for (final o in a.oddities) {
      _flag('Unusual account number', 'This account number looks odd: $o.', 4, nodeId: id);
    }
    final hits = await _lookup('Kantoi scam map', 'Looking for the account in scam cases saved on this phone',
        online: false, nodeId: id, run: () => _intelHits(['bankAccount:${accountKey(a.digits)}']), describe: (h) => h.isEmpty ? 'Not in saved scam cases' : 'Found in saved scam cases${h.any((e) => e.synthetic) ? ' (demo data)' : ''}');
    for (final h in hits ?? const <IntelEntity>[]) {
      _relatedCase(h, id, 'This account is in the scam map');
    }
    _semakMuleNote(id, 'this account');
  }

  void _semakMuleNote(String id, String what) {
    final s = LogStep(
        tool: 'Semak Mule (PDRM)',
        action: 'Police mule account and number check',
        result: 'Semak Mule has no public API and Kantoi never sends automated checks to government websites. Tap "Check on Semak Mule" to look up $what yourself.',
        status: StepStatus.skipped);
    _emit(TraceLookupEvent(TraceLookup(_ids++, s, id)));
    _fact(id, 'Semak Mule', 'Check it yourself at semakmule.rmp.gov.my');
  }

  // ------------------------------------------------------------ email

  Future<void> _traceEmail(String raw, String? parent) async {
    final e = raw.trim().toLowerCase();
    final at = e.lastIndexOf('@');
    if (at <= 0) return;
    final local = e.substring(0, at), domain = e.substring(at + 1);
    final id = _node(TraceKind.email, e, e, parent: parent, edge: 'contains email');
    if (id == null) return;
    final free = _freeMail.contains(domain);
    final check = await _lookup<(String?, bool)>('Sender check', 'Checking who runs $domain and whether $local uses a brand name',
        online: false, nodeId: id, run: () async {
      final official = officialBrandFor(domain);
      return (lookalikeBrand('$local.example') ?? (official == null ? lookalikeBrand(domain) : null), official != null);
    }, describe: (r) => [
          if (r.$2) 'Official ${officialBrandFor(domain)} address',
          if (free) 'Free email service anyone can sign up for',
          if (r.$1 != null) 'Uses the name ${r.$1}',
          if (!r.$2 && !free && r.$1 == null) 'Private domain',
        ].join('; '));
    if (check != null) {
      final (b, official) = check;
      if (official) _flag('Official email domain', '$domain belongs to ${officialBrandFor(domain)}. The sender name can still be faked.', -4, nodeId: id);
      if (b != null && !official) {
        _flag(free ? 'Brand name on a free email' : 'Brand name on a look-alike domain',
            free ? '$e uses the name $b on a free email service. $b does not email you from $domain.' : '$domain uses the name $b but is not an official $b domain.',
            free ? 14 : 18, nodeId: id);
        _node(TraceKind.brand, b, 'Imitates $b', parent: id, edge: 'pretends to be', flagged: true, facts: [('Brand', b)]);
      }
    }
    if (free) {
      _fact(id, 'Provider', 'Free email service ($domain)');
      return;
    }
    await _traceDomain(registrableDomain(domain), domain, id, official: officialBrandFor(domain) != null);
  }

  // ------------------------------------------------------------ helpers

  static String _ago(int days) {
    if (days < 0) return 'with a future date';
    if (days == 0) return 'today';
    if (days == 1) return '1 day ago';
    if (days < 60) return '$days days ago';
    if (days < 730) return '${days ~/ 30} months ago';
    return '${days ~/ 365} years ago';
  }
}

class CtNames {
  final int certs;
  final DateTime? first;
  final List<String> subdomains;
  final List<String> siblings;
  const CtNames(this.certs, this.first, this.subdomains, this.siblings);
}

/// Sub-domains of [domain] and other websites sharing its certificates, from
/// a crt.sh JSON answer. Brand look-alikes come first.
CtNames parseCtNames(String body, String domain) {
  final list = jsonDecode(body) as List;
  final subs = <String>{}, sibs = <String>{};
  DateTime? first;
  for (final row in list) {
    if (row is! Map) continue;
    final nb = DateTime.tryParse('${row['not_before'] ?? ''}');
    if (nb != null && (first == null || nb.isBefore(first))) first = nb;
    for (var n in '${row['name_value'] ?? ''}\n${row['common_name'] ?? ''}'.split(RegExp(r'\s+'))) {
      n = n.trim().toLowerCase().replaceFirst('*.', '');
      if (n.isEmpty || !n.contains('.') || n == domain) continue;
      if (n.endsWith('.$domain')) {
        subs.add(n);
      } else if (registrableDomain(n) != domain) {
        sibs.add(n);
      }
    }
  }
  int rank(String s) => lookalikeBrand(s) != null ? 0 : 1;
  final s = subs.toList()..sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.length - b.length);
  final o = sibs.toList()..sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.compareTo(b));
  return CtNames(list.length, first, s, o);
}
