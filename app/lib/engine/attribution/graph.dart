/// The entity graph: links entities that share infrastructure or scripts,
/// then groups connected entities into campaigns.
library;

import 'dart:math' as math;

import 'fingerprint.dart';
import 'intel_models.dart';

/// DNS providers used by millions of ordinary sites. Sharing one says nothing.
const _popularNs = [
  'cloudflare.com', 'domaincontrol.com', 'awsdns', 'googledomains.com', 'google.com', 'registrar-servers.com',
  'dnsowl.com', 'name.com', 'dns-parking.com', 'nsone.net', 'azure-dns', 'ultradns', 'akam.net', 'wixdns.net',
  'vercel-dns.com', 'netlify', 'digitalocean.com', 'linode.com', 'dynect.net', 'hostinger', 'parkingcrew.net',
  'bodis.com', 'sedoparking.com', 'afternic.com', 'gname-dns.com', 'share-dns', 'dnspod', 'hichina.com',
];

bool popularNameserver(String ns) => _popularNs.any(ns.toLowerCase().contains);

/// Links weaker than this are shown as evidence but do not merge campaigns.
const clusterThreshold = 0.4;

/// Edge strengths when a scam report connects its message to an entity.
double _reportStrength(EdgeKind k) => switch (k) {
      EdgeKind.payout => 0.9,
      EdgeKind.contact => 0.85,
      EdgeKind.photo => 0.8,
      _ => 0.85,
    };

EdgeKind _reportKind(NodeType t) => switch (t) {
      NodeType.bankAccount || NodeType.wallet => EdgeKind.payout,
      NodeType.phone || NodeType.handle => EdgeKind.contact,
      NodeType.photo => EdgeKind.photo,
      _ => EdgeKind.link,
    };

String _verb(EdgeKind k) => switch (k) {
      EdgeKind.payout => 'asks for payment to',
      EdgeKind.contact => 'gives the contact',
      EdgeKind.photo => 'uses the profile photo',
      _ => 'links to',
    };

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1].substring(0, 3)} ${d.year}';

int _week(DateTime d) => d.toUtc().millisecondsSinceEpoch ~/ (7 * 24 * 3600 * 1000);

class IntelGraph {
  final Map<String, IntelEntity> nodes = {};
  final Map<String, IntelEdge> _edges = {};
  final Map<String, List<IntelEdge>> adj = {};
  final List<IntelReport> reports;
  final List<Campaign> campaigns = [];
  final Map<String, Campaign> campaignOf = {};

  // Indexes for linking new entities.
  final Map<String, List<IntelEntity>> _byNs = {};
  final Map<String, List<IntelEntity>> _byWeek = {};
  final Map<String, List<IntelEntity>> _byTitle = {};
  final List<IntelEntity> _shaped = [];
  final List<IntelEntity> _iconed = [];
  final List<IntelEntity> _templates = [];
  final List<IntelEntity> _photos = [];
  final Map<String, int> _ipUse = {};
  final Map<String, int> _nsUse = {};

  IntelGraph(Iterable<IntelEntity> entities, this.reports) {
    for (final e in entities) {
      nodes[e.id] = e;
    }
    // Count how widely each nameserver and address is shared, so a shared
    // cloud provider does not tie unrelated sites together.
    for (final e in nodes.values.where((e) => e.type == NodeType.domain)) {
      for (final ip in e.ips) {
        _ipUse[ip] = (_ipUse[ip] ?? 0) + 1;
      }
      for (final ns in e.nameservers) {
        _nsUse[ns] = (_nsUse[ns] ?? 0) + 1;
      }
    }
    for (final e in nodes.values.toList()) {
      for (final l in linksFor(e)) {
        _add(l);
      }
      _index(e);
    }
    for (final r in reports) {
      _linkReport(r);
    }
    _cluster();
  }

  List<IntelEdge> get edges => _edges.values.toList();

  void _add(IntelEdge e) {
    if (e.a == e.b) return;
    final k = e.a.compareTo(e.b) < 0 ? '${e.a}|${e.b}|${e.kind.name}' : '${e.b}|${e.a}|${e.kind.name}';
    final old = _edges[k];
    if (old != null && old.strength >= e.strength) return;
    if (old != null) {
      adj[old.a]?.remove(old);
      adj[old.b]?.remove(old);
    }
    _edges[k] = e;
    adj.putIfAbsent(e.a, () => []).add(e);
    adj.putIfAbsent(e.b, () => []).add(e);
  }

  void _index(IntelEntity e) {
    switch (e.type) {
      case NodeType.domain:
        for (final ns in e.nameservers) {
          _byNs.putIfAbsent(ns, () => []).add(e);
        }
        if (e.created != null) _byWeek.putIfAbsent('${_week(e.created!)}', () => []).add(e);
        final t = titleKey(e.pageTitle ?? '');
        if (t.length >= 6) _byTitle.putIfAbsent(t, () => []).add(e);
        if (e.pageShape != null) _shaped.add(e);
        if (e.faviconHash != null) _iconed.add(e);
      case NodeType.template:
        if (e.sketch.isNotEmpty) _templates.add(e);
      case NodeType.photo:
        _photos.add(e);
      default:
    }
  }

  IntelEntity? _ipNode(String ip, IntelEntity from, bool probe) {
    if (probe) return nodes['ip:$ip'];
    return nodes.putIfAbsent(
        'ip:$ip',
        () => IntelEntity(
            type: NodeType.ip, key: ip, source: from.source, synthetic: from.synthetic, firstSeen: from.firstSeen, evidence: from.evidence * 0.5));
  }

  /// Links between [e] and entities already in the graph, by shared
  /// infrastructure, look-alike pages or matching scripts. A [probe] (an
  /// item being checked) is compared without being added.
  List<IntelEdge> linksFor(IntelEntity e, {bool probe = false}) {
    final out = <IntelEdge>[];
    if (e.type == NodeType.domain) {
      for (final ns in e.nameservers) {
        if (popularNameserver(ns)) continue;
        final peers = (_byNs[ns] ?? const []).where((p) => p.id != e.id).toList();
        // Linking to a few recent peers is enough to connect the group.
        for (final p in peers.reversed.take(6)) {
          final s = (_nsUse[ns] ?? 0) > 25 ? 0.3 : 0.7;
          out.add(IntelEdge(e.id, p.id, EdgeKind.nameserver, 'Both use the nameserver $ns', s));
        }
      }
      for (final ip in e.ips) {
        final ipNode = _ipNode(ip, e, probe);
        if (ipNode == null) continue;
        final shared = _ipUse[ip] ?? 1;
        final where = [ipNode.network, ipNode.country].whereType<String>().join(', ');
        out.add(IntelEdge(e.id, ipNode.id, EdgeKind.hosting,
            '${e.key} points to $ip${where.isEmpty ? '' : ' ($where)'}${shared > 1 ? ', shared by $shared known scam websites' : ''}',
            shared > 20 ? 0.15 : 0.6));
      }
      if (e.created != null) {
        final peers = (_byWeek['${_week(e.created!)}'] ?? const []).where((p) => p.id != e.id).toList();
        for (final p in peers.reversed.take(40)) {
          final sim = nameSimilarity(e.key, p.key);
          final sameBrand = e.brand != null && e.brand == p.brand;
          if (!sameBrand && sim < 0.6) continue;
          out.add(IntelEdge(
              e.id,
              p.id,
              EdgeKind.regWeek,
              'Both registered in the week of ${shortDate(e.created!)}${sameBrand ? ' and both imitate ${e.brand}' : ' with similar names'}',
              // Same brand alone is common to unrelated crews, so it is weak.
              sim >= 0.75 ? 0.6 : sim >= 0.6 ? 0.45 : 0.35));
        }
      }
      final t = titleKey(e.pageTitle ?? '');
      if (t.length >= 6) {
        for (final p in (_byTitle[t] ?? const <IntelEntity>[]).where((p) => p.id != e.id).toList().reversed.take(6)) {
          // Copied brand titles are common, so a title alone is weak.
          out.add(IntelEdge(e.id, p.id, EdgeKind.pageTemplate, 'Both pages have the title "${e.pageTitle}"', 0.35));
        }
      }
      if (e.pageShape != null) {
        for (final p in _shaped.where((p) => p.id != e.id)) {
          final d = hamming32(e.pageShape!, p.pageShape!);
          if (d <= 3) {
            out.add(IntelEdge(e.id, p.id, EdgeKind.pageTemplate,
                d == 0 ? 'Both pages are built from the same template' : 'Both pages are built almost the same way', d == 0 ? 0.7 : 0.6));
          }
        }
      }
      if (e.faviconHash != null) {
        for (final p in _iconed.where((p) => p.id != e.id)) {
          final d = hexDistance(e.faviconHash!, p.faviconHash!);
          // Look-alikes copy the real brand's icon, so this only supports
          // other links.
          if (d <= 4) out.add(IntelEdge(e.id, p.id, EdgeKind.favicon, 'Both show the same website icon', 0.3));
        }
      }
    }
    if (e.type == NodeType.template && e.sketch.isNotEmpty) {
      for (final p in _templates.where((p) => p.id != e.id)) {
        final sim = scriptSimilarity(e.sketch, p.sketch);
        if (sim >= 0.3) {
          out.add(IntelEdge(e.id, p.id, EdgeKind.script, 'The two messages share about ${(sim * 100).round()}% of their wording',
              math.min(0.95, 0.3 + 0.65 * sim)));
        }
      }
    }
    if (e.type == NodeType.photo) {
      for (final p in _photos.where((p) => p.id != e.id)) {
        final d = hexDistance(e.key, p.key);
        if (d <= 8) out.add(IntelEdge(e.id, p.id, EdgeKind.photo, 'The same profile photo (fingerprints differ by $d of 64 points)', 0.8));
      }
    }
    return out;
  }

  void _linkReport(IntelReport r) {
    final ids = r.entityIds.where(nodes.containsKey).toList();
    if (ids.isEmpty) return;
    final hub = ids.firstWhere((i) => i.startsWith('template:'), orElse: () => ids.first);
    for (final id in ids) {
      if (id == hub) continue;
      final n = nodes[id]!;
      final k = _reportKind(n.type);
      _add(IntelEdge(hub, id, k, 'Report of ${shortDate(r.at)}: the message ${_verb(k)} ${n.display} (evidence ${r.evidence.toStringAsFixed(1)})',
          _reportStrength(k) * r.evidence));
    }
  }

  void _cluster() {
    final parent = <String, String>{for (final k in nodes.keys) k: k};
    String find(String x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]!]!;
        x = parent[x]!;
      }
      return x;
    }

    for (final e in _edges.values) {
      if (e.strength < clusterThreshold) continue;
      final a = find(e.a), b = find(e.b);
      if (a != b) parent[a] = b;
    }
    final groups = <String, Set<String>>{};
    for (final k in nodes.keys) {
      groups.putIfAbsent(find(k), () => {}).add(k);
    }
    final reportsByEntity = <String, List<IntelReport>>{};
    for (final r in reports) {
      for (final id in r.entityIds) {
        reportsByEntity.putIfAbsent(id, () => []).add(r);
      }
    }
    for (final g in groups.values) {
      final rs = <String, IntelReport>{};
      for (final id in g) {
        for (final r in reportsByEntity[id] ?? const <IntelReport>[]) {
          rs[r.id] = r;
        }
      }
      final domains = g.where((i) => i.startsWith('domain:')).length;
      if (!(rs.isNotEmpty && g.length >= 2 || domains >= 2 && g.length >= 3)) continue;
      final c = _profile(g, rs.values.toList());
      campaigns.add(c);
      for (final id in g) {
        campaignOf[id] = c;
      }
    }
    campaigns.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  }

  Campaign _profile(Set<String> ids, List<IntelReport> rs) {
    final ents = ids.map((i) => nodes[i]!).toList();
    var first = ents.map((e) => e.firstSeen).reduce((a, b) => a.isBefore(b) ? a : b);
    var last = ents.map((e) => e.lastSeen).reduce((a, b) => a.isAfter(b) ? a : b);
    for (final r in rs) {
      if (r.at.isBefore(first)) first = r.at;
      if (r.at.isAfter(last)) last = r.at;
    }
    final typeVotes = <String, double>{};
    for (final r in rs) {
      typeVotes[r.scamType] = (typeVotes[r.scamType] ?? 0) + r.evidence;
    }
    final type = _top(typeVotes);
    final brandVotes = <String, double>{};
    for (final r in rs.where((r) => r.brand != null)) {
      brandVotes[r.brand!] = (brandVotes[r.brand!] ?? 0) + 1 + r.evidence;
    }
    for (final e in ents.where((e) => e.brand != null)) {
      brandVotes[e.brand!] = (brandVotes[e.brand!] ?? 0) + 0.5;
    }
    final brand = _top(brandVotes);
    final channels = _ranked(rs.map((r) => r.channel));
    // The month with the most activity names the wave.
    final months = _ranked([...rs.map((r) => r.at), if (rs.isEmpty) ...ents.map((e) => e.firstSeen)].map((d) => _months[d.month - 1]));
    final scamType = type ?? (brand != null ? 'Fake $brand website' : 'Scam websites');
    final counts = <NodeType, int>{};
    for (final e in ents) {
      counts[e.type] = (counts[e.type] ?? 0) + 1;
    }
    final sorted = ids.toList()..sort();
    return Campaign(
      id: 'c${fnv32(sorted.first).toRadixString(16)}',
      label: campaignLabel(scamType, brand, channels.isEmpty ? (counts[NodeType.domain] ?? 0) > 0 ? 'Website' : 'Message' : channels.first,
          months.isEmpty ? _months[last.month - 1] : months.first),
      scamType: scamType,
      brand: brand,
      entityIds: ids,
      reports: rs..sort((a, b) => b.at.compareTo(a.at)),
      firstSeen: first,
      lastSeen: last,
      targets: _ranked(rs.expand((r) => r.targets)).take(4).toList(),
      tactics: _ranked(rs.expand((r) => r.tactics)).take(5).toList(),
      channels: channels.take(4).toList(),
      synthetic: ents.every((e) => e.synthetic),
      counts: counts,
    );
  }

  /// A drawable piece of the graph around [seeds]: their campaign (if any)
  /// and direct links, at most [limit] nodes, nearest first.
  Subgraph around(Iterable<String> seeds, {int limit = 60, Iterable<IntelEdge> extra = const [], Map<String, IntelEntity> extraNodes = const {}}) {
    final all = {...nodes, ...extraNodes};
    final adjacency = <String, List<IntelEdge>>{for (final e in adj.entries) e.key: List.of(e.value)};
    for (final e in extra) {
      adjacency.putIfAbsent(e.a, () => []).add(e);
      adjacency.putIfAbsent(e.b, () => []).add(e);
    }
    final keep = <String>{};
    final queue = <String>[...seeds.where(all.containsKey)];
    keep.addAll(queue);
    while (queue.isNotEmpty && keep.length < limit) {
      final cur = queue.removeAt(0);
      final out = List.of(adjacency[cur] ?? const <IntelEdge>[])..sort((a, b) => b.strength.compareTo(a.strength));
      for (final e in out) {
        final o = e.other(cur);
        if (keep.contains(o) || !all.containsKey(o)) continue;
        // Stay inside the campaign unless the link is direct from a seed.
        if (!seeds.contains(cur) && e.strength < clusterThreshold) continue;
        keep.add(o);
        queue.add(o);
        if (keep.length >= limit) break;
      }
    }
    final es = <IntelEdge>[
      for (final e in [..._edges.values, ...extra])
        if (keep.contains(e.a) && keep.contains(e.b)) e
    ];
    return Subgraph([for (final k in keep) all[k]!], es, highlight: seeds.toSet());
  }

  Subgraph campaignGraph(Campaign c) {
    final hub = c.entityIds.firstWhere((i) => i.startsWith('template:'), orElse: () => c.entityIds.first);
    return around([hub], limit: 80);
  }
}

String? _top(Map<String, double> votes) {
  if (votes.isEmpty) return null;
  return (votes.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
}

List<String> _ranked(Iterable<String> xs) {
  final c = <String, int>{};
  for (final x in xs) {
    c[x] = (c[x] ?? 0) + 1;
  }
  return (c.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key).toList();
}

const _shortBrand = {'Pos Malaysia': 'Pos Laju', 'J&T Express': 'J&T', 'Hong Leong Bank': 'Hong Leong'};

/// A campaign name in plain words, e.g. "Fake Pos Laju fee SMS, October wave".
String campaignLabel(String scamType, String? brand, String channel, String month) {
  final b = brand == null ? null : _shortBrand[brand] ?? brand;
  final t = scamType.toLowerCase();
  final base = t.contains('parcel')
      ? 'Fake ${b ?? 'parcel'} fee'
      : t.contains('refund') || t.contains('tax')
          ? 'Fake ${b ?? 'tax'} refund'
          : t.contains('officer') || t.contains('macau') || t.contains('police')
              ? 'Fake ${b ?? 'police'} officer'
              : t.contains('job') || t.contains('task')
                  ? 'Fake part-time job'
                  : t.contains('love') || t.contains('romance')
                      ? '"Wrong number" crypto romance'
                      : t.contains('phishing') || t.contains('login')
                          ? 'Fake ${b ?? 'bank'} login'
                          : t.startsWith('fake ') && b != null && t.contains('website')
                              ? 'Fake $b'
                              : scamType;
  final ch = switch (channel.toLowerCase()) {
    'sms' => ' SMS',
    'phone call' || 'call' => ' calls',
    'website' => ' websites',
    'message' => ' messages',
    _ => ' on $channel',
  };
  return '$base$ch, $month wave';
}
