/// Data for a live trace: the map Kantoi builds from real lookups, the
/// lookup log behind it and the warning signs it found.
library;

import '../models.dart';

enum TraceKind { message, url, domain, subdomain, sibling, ip, nameserver, mail, cert, hosting, country, phone, account, email, brand, related, webReport }

String traceKindLabel(TraceKind k) => switch (k) {
      TraceKind.message => 'Message',
      TraceKind.url => 'Link',
      TraceKind.domain => 'Website',
      TraceKind.subdomain => 'Sub-domain',
      TraceKind.sibling => 'Website on the same certificate',
      TraceKind.ip => 'Server address',
      TraceKind.nameserver => 'Nameserver (DNS)',
      TraceKind.mail => 'Mail server (DNS)',
      TraceKind.cert => 'Security certificate',
      TraceKind.hosting => 'Hosting company',
      TraceKind.country => 'Country',
      TraceKind.phone => 'Phone number',
      TraceKind.account => 'Bank account',
      TraceKind.email => 'Email address',
      TraceKind.brand => 'Imitated brand',
      TraceKind.related => 'Known scam case',
      TraceKind.webReport => 'Report on the web',
    };

/// Short tag drawn inside a node.
String traceKindTag(TraceKind k) => switch (k) {
      TraceKind.message => 'MSG',
      TraceKind.url => 'URL',
      TraceKind.domain => 'WEB',
      TraceKind.subdomain => 'SUB',
      TraceKind.sibling => 'WEB',
      TraceKind.ip => 'IP',
      TraceKind.nameserver => 'NS',
      TraceKind.mail => 'MX',
      TraceKind.cert => 'TLS',
      TraceKind.hosting => 'ASN',
      TraceKind.country => 'GEO',
      TraceKind.phone => 'TEL',
      TraceKind.account => 'ACC',
      TraceKind.email => 'MAIL',
      TraceKind.brand => 'FAKE',
      TraceKind.related => 'CASE',
      TraceKind.webReport => 'RPT',
    };

class TraceNode {
  final String id;
  final TraceKind kind;
  final String label;
  final String? parent;
  /// Facts from the lookups, in the order they were found.
  final List<(String, String)> facts = [];
  bool flagged;
  /// From seeded demo data, not a real report.
  final bool demo;
  /// Two-letter country code for country nodes.
  final String? country;
  final DateTime at;
  TraceNode({required this.id, required this.kind, required this.label, this.parent, this.flagged = false, this.demo = false, this.country, DateTime? at})
      : at = at ?? DateTime.now();

  void addFact(String k, String v) {
    final i = facts.indexWhere((f) => f.$1 == k);
    if (i >= 0) {
      facts[i] = (k, v);
    } else {
      facts.add((k, v));
    }
  }
}

class TraceEdge {
  final String from;
  final String to;
  final String label;
  const TraceEdge(this.from, this.to, this.label);
  String get key => '$from>$to';
}

/// One lookup: what was asked, which tool, the answer, and whether it stayed
/// on the phone or went online.
class TraceLookup {
  final int id;
  final LogStep step;
  /// The map node the lookup is about, for the packet animation.
  final String? nodeId;
  /// True when the answer is a warning sign.
  bool alarming = false;
  TraceLookup(this.id, this.step, this.nodeId);
  bool get online => step.sentOffDevice;
  bool get running => step.status == StepStatus.running;
}

/// A warning sign (positive weight) or a reassuring sign (negative weight).
class TraceFlag {
  final String title;
  final String why;
  final int weight;
  final String? nodeId;
  final bool demo;
  const TraceFlag(this.title, this.why, this.weight, {this.nodeId, this.demo = false});
  bool get isRisk => weight > 0;
}

sealed class TraceEvent {
  const TraceEvent();
}

class TraceStarted extends TraceEvent {
  final String target;
  final String kind;
  const TraceStarted(this.target, this.kind);
}

/// A node was added, or new facts were found for it.
class TraceNodeEvent extends TraceEvent {
  final TraceNode node;
  const TraceNodeEvent(this.node);
}

class TraceEdgeEvent extends TraceEvent {
  final TraceEdge edge;
  const TraceEdgeEvent(this.edge);
}

/// A lookup started, or finished (its step status says which).
class TraceLookupEvent extends TraceEvent {
  final TraceLookup lookup;
  const TraceLookupEvent(this.lookup);
}

class TraceFlagEvent extends TraceEvent {
  final TraceFlag flag;
  const TraceFlagEvent(this.flag);
}

class TraceProgressEvent extends TraceEvent {
  final int done;
  final int total;
  const TraceProgressEvent(this.done, this.total);
}

class TraceFinished extends TraceEvent {
  final bool cancelled;
  const TraceFinished({this.cancelled = false});
}

/// Everything a trace found so far, rebuilt from its events.
class TraceState {
  String target = '';
  String kind = '';
  final Map<String, TraceNode> nodes = {};
  final Map<String, TraceEdge> edges = {};
  final List<TraceLookup> lookups = [];
  final List<TraceFlag> flags = [];
  int done = 0;
  int total = 0;
  bool started = false;
  bool finished = false;
  bool cancelled = false;
  DateTime? startedAt;
  DateTime? finishedAt;

  void apply(TraceEvent e) {
    switch (e) {
      case TraceStarted(:final target, :final kind):
        this.target = target;
        this.kind = kind;
        started = true;
        startedAt = DateTime.now();
      case TraceNodeEvent(:final node):
        nodes[node.id] = node;
      case TraceEdgeEvent(:final edge):
        edges[edge.key] = edge;
      case TraceLookupEvent(:final lookup):
        if (!lookups.any((l) => l.id == lookup.id)) lookups.add(lookup);
      case TraceFlagEvent(:final flag):
        flags.add(flag);
      case TraceProgressEvent(:final done, :final total):
        this.done = done;
        this.total = total;
      case TraceFinished(:final cancelled):
        finished = true;
        this.cancelled = cancelled;
        finishedAt = DateTime.now();
    }
  }

  String? get originId => nodes.values.where((n) => n.parent == null).firstOrNull?.id;

  /// Nodes that a lookup is running on right now.
  Set<String> get active => {for (final l in lookups) if (l.running && l.nodeId != null) l.nodeId!};

  double get progress => finished ? 1 : (total == 0 ? 0 : done / total);

  int get score => flags.fold<int>(0, (a, f) => a + f.weight).clamp(0, 100);

  RiskLevel get level => traceLevel(score);

  Set<String> get countries => {for (final n in nodes.values) if (n.kind == TraceKind.country && n.country != null) n.country!};

  /// Entities found besides the thing that was traced.
  int get entityCount => nodes.length - (originId == null ? 0 : 1);

  bool get hasDemo => nodes.values.any((n) => n.demo);
}

RiskLevel traceLevel(int score) => score >= 45
    ? RiskLevel.danger
    : score >= 25
        ? RiskLevel.suspicious
        : score >= 8
            ? RiskLevel.caution
            : RiskLevel.safe;

/// HUD wording: the trace only reports signs it found, it never says "safe".
String traceRiskLabel(int score) => switch (traceLevel(score)) {
      RiskLevel.danger => 'High',
      RiskLevel.suspicious => 'Elevated',
      RiskLevel.caution => 'Some signs',
      RiskLevel.safe => score > 0 ? 'Low' : 'No signs yet',
    };

const countryNames = {
  'MY': 'Malaysia', 'SG': 'Singapore', 'ID': 'Indonesia', 'TH': 'Thailand', 'PH': 'Philippines', 'VN': 'Vietnam',
  'KH': 'Cambodia', 'LA': 'Laos', 'MM': 'Myanmar', 'BN': 'Brunei', 'CN': 'China', 'HK': 'Hong Kong', 'MO': 'Macau',
  'TW': 'Taiwan', 'JP': 'Japan', 'KR': 'South Korea', 'IN': 'India', 'PK': 'Pakistan', 'BD': 'Bangladesh',
  'LK': 'Sri Lanka', 'NP': 'Nepal', 'AU': 'Australia', 'NZ': 'New Zealand', 'US': 'United States', 'CA': 'Canada',
  'GB': 'United Kingdom', 'IE': 'Ireland', 'DE': 'Germany', 'FR': 'France', 'NL': 'Netherlands', 'BE': 'Belgium',
  'LU': 'Luxembourg', 'CH': 'Switzerland', 'SE': 'Sweden', 'FI': 'Finland', 'NO': 'Norway', 'DK': 'Denmark',
  'PL': 'Poland', 'CZ': 'Czechia', 'RO': 'Romania', 'BG': 'Bulgaria', 'UA': 'Ukraine', 'RU': 'Russia', 'TR': 'Turkey',
  'IT': 'Italy', 'ES': 'Spain', 'PT': 'Portugal', 'AE': 'United Arab Emirates', 'SA': 'Saudi Arabia', 'IL': 'Israel',
  'NG': 'Nigeria', 'ZA': 'South Africa', 'EG': 'Egypt', 'BR': 'Brazil', 'MX': 'Mexico', 'AR': 'Argentina',
  'PA': 'Panama', 'SC': 'Seychelles', 'BZ': 'Belize', 'VG': 'British Virgin Islands', 'MD': 'Moldova', 'LT': 'Lithuania',
  'LV': 'Latvia', 'EE': 'Estonia', 'IS': 'Iceland', 'CY': 'Cyprus',
};

String countryName(String code) => countryNames[code.toUpperCase()] ?? code.toUpperCase();
