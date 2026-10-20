/// Data types for Kantoi's threat intel: entities seen in scams, the links
/// between them, and the campaigns those links form. Everything is about
/// infrastructure and scripts, never about named people.
library;

import '../models.dart';

enum NodeType { domain, ip, phone, bankAccount, wallet, handle, photo, template }

String nodeTypeLabel(NodeType t) => switch (t) {
      NodeType.domain => 'Website',
      NodeType.ip => 'Server address',
      NodeType.phone => 'Phone number',
      NodeType.bankAccount => 'Bank account',
      NodeType.wallet => 'Crypto wallet',
      NodeType.handle => 'Social handle',
      NodeType.photo => 'Profile photo',
      NodeType.template => 'Message script',
    };

/// Where an entity came from. Crawled entries are public data; reports are
/// approved by a Kantoi user; seen entries were checked on this device.
enum IntelSource { demo, report, ct, openphish, urlhaus, seen }

String sourceLabel(IntelSource s) => switch (s) {
      IntelSource.demo => 'Demo data',
      IntelSource.report => 'Kantoi report',
      IntelSource.ct => 'New certificate (CT log)',
      IntelSource.openphish => 'OpenPhish feed',
      IntelSource.urlhaus => 'URLhaus feed',
      IntelSource.seen => 'Checked on this device',
    };

/// One node of the entity graph. [key] is normalised so the same account or
/// domain written two ways is one node.
class IntelEntity {
  final NodeType type;
  final String key;
  final IntelSource source;
  final bool synthetic;
  DateTime firstSeen;
  DateTime lastSeen;

  /// How strongly the evidence says this entity is used in scams, 0 to 1.
  double evidence;
  String? brand;

  // Domain enrichment.
  String? registrar;
  DateTime? created;
  List<String> nameservers;
  List<String> ips;
  String? network;
  String? country;
  String? pageTitle;
  String? faviconHash;
  int? pageShape;
  bool enriched;

  // Message scripts.
  String? snippet;
  List<int> sketch;

  IntelEntity({
    required this.type,
    required this.key,
    required this.source,
    required this.firstSeen,
    DateTime? lastSeen,
    this.synthetic = false,
    this.evidence = 0,
    this.brand,
    this.registrar,
    this.created,
    this.nameservers = const [],
    this.ips = const [],
    this.network,
    this.country,
    this.pageTitle,
    this.faviconHash,
    this.pageShape,
    this.enriched = false,
    this.snippet,
    this.sketch = const [],
  }) : lastSeen = lastSeen ?? firstSeen;

  String get id => '${type.name}:$key';

  /// What the UI shows. Bank accounts are shortened, since mule accounts are
  /// often held by recruited victims.
  String get display => switch (type) {
        NodeType.bankAccount => 'Account ending ${key.length > 4 ? key.substring(key.length - 4) : key}',
        NodeType.phone => '+$key',
        NodeType.template => snippet ?? 'Message script',
        NodeType.wallet => key.length > 14 ? '${key.substring(0, 6)}…${key.substring(key.length - 6)}' : key,
        _ => key,
      };

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'key': key,
        'source': source.name,
        'synthetic': synthetic,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'evidence': evidence,
        'brand': ?brand,
        'registrar': ?registrar,
        'created': ?created?.toIso8601String(),
        if (nameservers.isNotEmpty) 'nameservers': nameservers,
        if (ips.isNotEmpty) 'ips': ips,
        'network': ?network,
        'country': ?country,
        'pageTitle': ?pageTitle,
        'faviconHash': ?faviconHash,
        'pageShape': ?pageShape,
        if (enriched) 'enriched': true,
        'snippet': ?snippet,
        if (sketch.isNotEmpty) 'sketch': sketch,
      };

  factory IntelEntity.fromJson(Map<String, dynamic> j) => IntelEntity(
        type: NodeType.values.byName(j['type'] as String),
        key: j['key'] as String,
        source: IntelSource.values.firstWhere((s) => s.name == j['source'], orElse: () => IntelSource.seen),
        synthetic: j['synthetic'] == true,
        firstSeen: DateTime.parse(j['firstSeen'] as String),
        lastSeen: DateTime.tryParse(j['lastSeen'] as String? ?? ''),
        evidence: (j['evidence'] as num?)?.toDouble() ?? 0,
        brand: j['brand'] as String?,
        registrar: j['registrar'] as String?,
        created: DateTime.tryParse(j['created'] as String? ?? ''),
        nameservers: (j['nameservers'] as List? ?? const []).cast<String>(),
        ips: (j['ips'] as List? ?? const []).cast<String>(),
        network: j['network'] as String?,
        country: j['country'] as String?,
        pageTitle: j['pageTitle'] as String?,
        faviconHash: j['faviconHash'] as String?,
        pageShape: j['pageShape'] as int?,
        enriched: j['enriched'] == true,
        snippet: j['snippet'] as String?,
        sketch: (j['sketch'] as List? ?? const []).cast<int>(),
      );
}

/// A report that a user approved (or a demo report). It links the scammer's
/// entities to one message script.
class IntelReport {
  final String id;
  final DateTime at;
  final String scamType;
  final String? brand;
  final String channel;
  final List<String> targets;
  final List<String> tactics;

  /// 0 to 1, from the strength of the evidence, not from how many people
  /// reported it.
  final double evidence;
  final List<String> entityIds;
  final bool synthetic;
  const IntelReport({
    required this.id,
    required this.at,
    required this.scamType,
    required this.channel,
    required this.evidence,
    required this.entityIds,
    this.brand,
    this.targets = const [],
    this.tactics = const [],
    this.synthetic = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'scamType': scamType,
        'brand': ?brand,
        'channel': channel,
        'targets': targets,
        'tactics': tactics,
        'evidence': evidence,
        'entityIds': entityIds,
        'synthetic': synthetic,
      };

  factory IntelReport.fromJson(Map<String, dynamic> j) => IntelReport(
        id: j['id'] as String,
        at: DateTime.parse(j['at'] as String),
        scamType: j['scamType'] as String? ?? 'Scam',
        brand: j['brand'] as String?,
        channel: j['channel'] as String? ?? 'Message',
        targets: (j['targets'] as List? ?? const []).cast<String>(),
        tactics: (j['tactics'] as List? ?? const []).cast<String>(),
        evidence: (j['evidence'] as num?)?.toDouble() ?? 0,
        entityIds: (j['entityIds'] as List? ?? const []).cast<String>(),
        synthetic: j['synthetic'] == true,
      );
}

/// A news story or public advisory about a scam wave.
class NewsItem {
  final String title;
  final String link;
  final String source;
  final DateTime at;
  final String scamType;
  final bool synthetic;
  const NewsItem({required this.title, required this.link, required this.source, required this.at, required this.scamType, this.synthetic = false});

  Map<String, dynamic> toJson() =>
      {'title': title, 'link': link, 'source': source, 'at': at.toIso8601String(), 'scamType': scamType, 'synthetic': synthetic};
  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        title: j['title'] as String,
        link: j['link'] as String? ?? '',
        source: j['source'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        scamType: j['scamType'] as String? ?? 'Scam',
        synthetic: j['synthetic'] == true,
      );
}

enum EdgeKind { nameserver, hosting, regWeek, pageTemplate, favicon, payout, contact, link, script, photo }

String edgeLabel(EdgeKind k) => switch (k) {
      EdgeKind.nameserver => 'Same nameserver',
      EdgeKind.hosting => 'Same hosting address',
      EdgeKind.regWeek => 'Same registration week',
      EdgeKind.pageTemplate => 'Same page template',
      EdgeKind.favicon => 'Same website icon',
      EdgeKind.payout => 'Same payout account',
      EdgeKind.contact => 'Same contact',
      EdgeKind.link => 'Same link',
      EdgeKind.script => 'Same script text',
      EdgeKind.photo => 'Same profile photo',
    };

/// A link between two entities, with the reason and the evidence behind it.
class IntelEdge {
  final String a;
  final String b;
  final EdgeKind kind;
  final String evidence;

  /// 0 to 1: how strongly this link suggests the same people are behind both.
  final double strength;
  const IntelEdge(this.a, this.b, this.kind, this.evidence, this.strength);

  String other(String id) => id == a ? b : a;
}

class Campaign {
  final String id;
  final String label;
  final String scamType;
  final String? brand;
  final Set<String> entityIds;
  final List<IntelReport> reports;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final List<String> targets;
  final List<String> tactics;
  final List<String> channels;
  final bool synthetic;
  final Map<NodeType, int> counts;
  const Campaign({
    required this.id,
    required this.label,
    required this.scamType,
    required this.entityIds,
    required this.reports,
    required this.firstSeen,
    required this.lastSeen,
    required this.counts,
    this.brand,
    this.targets = const [],
    this.tactics = const [],
    this.channels = const [],
    this.synthetic = false,
  });

  int get domains => counts[NodeType.domain] ?? 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'scamType': scamType,
        'brand': brand,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'reports': reports.length,
        'entities': entityIds.length,
        'targets': targets,
        'tactics': tactics,
        'channels': channels,
        'synthetic': synthetic,
      };
}

/// A small graph to draw: one campaign, or what an investigation touched.
class Subgraph {
  final List<IntelEntity> nodes;
  final List<IntelEdge> edges;
  final Set<String> highlight;
  const Subgraph(this.nodes, this.edges, {this.highlight = const {}});
  bool get isEmpty => nodes.isEmpty;
}

/// One thing in the checked item that Kantoi already knows about.
class IntelMatch {
  final String value;
  final IntelEntity entity;
  final EdgeKind? via;
  final String why;
  final double strength;
  final int? start;
  final int? end;
  const IntelMatch({required this.value, required this.entity, required this.why, required this.strength, this.via, this.start, this.end});
}

/// The answer to "who's behind it?" for one investigation.
class AttributionResult {
  final Campaign? campaign;
  final double confidence;
  final List<IntelMatch> matches;
  final int linkedDomains;
  final int linkedReports;
  final Subgraph graph;
  final List<Finding> findings;
  const AttributionResult({
    this.campaign,
    this.confidence = 0,
    this.matches = const [],
    this.linkedDomains = 0,
    this.linkedReports = 0,
    this.graph = const Subgraph([], []),
    this.findings = const [],
  });

  static const none = AttributionResult();

  bool get found => matches.isNotEmpty;
  bool get demo => campaign?.synthetic ?? matches.any((m) => m.entity.synthetic);

  /// The one plain sentence for the result screen.
  String get sentence {
    final pct = (confidence * 100).round();
    if (campaign != null) {
      final otherDomains = matches.any((m) => m.entity.type == NodeType.domain) ? linkedDomains - 1 : linkedDomains;
      return 'This matches a known scam campaign: "${campaign!.label}" (Kantoi is $pct% sure). '
          'It is linked to ${otherDomains < 0 ? 0 : otherDomains} other website${otherDomains == 1 ? '' : 's'} '
          'and $linkedReports report${linkedReports == 1 ? '' : 's'}.';
    }
    if (matches.isNotEmpty) {
      final m = matches.first;
      return '${nodeTypeLabel(m.entity.type)} ${m.entity.display} is already in the Kantoi scam database '
          '(${sourceLabel(m.entity.source).toLowerCase()}).';
    }
    return 'Nothing here matches a known scam campaign yet.';
  }

  Map<String, dynamic> toJson() => {
        'campaign': campaign?.toJson(),
        'confidence': double.parse(confidence.toStringAsFixed(2)),
        'linkedDomains': linkedDomains,
        'linkedReports': linkedReports,
        'sentence': sentence,
        'demo': demo,
        'matches': [
          for (final m in matches) {'type': m.entity.type.name, 'value': m.entity.display, 'why': m.why, 'strength': m.strength}
        ],
      };
}
