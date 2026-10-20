/// "This was actually legit / a scam" feedback. It goes into a review queue on
/// the device and never changes results automatically. Only a summary of the
/// investigation is kept: no message text, numbers or names.
library;

import 'models.dart';
import 'relationship.dart';

enum UserLabel { legit, scam }

class ReviewItem {
  final String id;
  final DateTime at;
  final UserLabel label;
  final String kind; // message or relationship
  final Map<String, dynamic> summary;
  const ReviewItem({required this.id, required this.at, required this.label, required this.kind, required this.summary});

  /// The user disagrees with Kantoi's verdict.
  bool get disagrees {
    final level = summary['level'] as String?;
    final risky = level == RiskLevel.suspicious.name || level == RiskLevel.danger.name;
    return label == UserLabel.legit ? risky : !risky;
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'at': at.toIso8601String(), 'label': label.name, 'kind': kind, 'disagrees': disagrees, 'summary': summary};

  factory ReviewItem.fromJson(Map<String, dynamic> j) => ReviewItem(
        id: j['id'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        label: UserLabel.values.firstWhere((l) => l.name == j['label'], orElse: () => UserLabel.scam),
        kind: j['kind'] as String? ?? 'message',
        summary: (j['summary'] as Map?)?.cast<String, dynamic>() ?? {},
      );
}

/// Everything a reviewer needs to see why Kantoi decided what it did, with
/// no personal data: scores, rule names, entity counts and link hosts.
Map<String, dynamic> investigationSummary(Investigation inv) {
  final counts = <String, int>{};
  for (final e in inv.artefact.entities) {
    counts[e.type.name] = (counts[e.type.name] ?? 0) + 1;
  }
  final v = inv.verdict;
  return {
    'source': inv.artefact.source.name,
    'score': v.score,
    'level': v.level.name,
    'confidence': v.confidence,
    'scamType': v.scamType,
    'messageLength': inv.artefact.text.length,
    'aiUsed': inv.log.any((s) => s.tool == 'AI analyst' && s.status == StepStatus.done),
    'findings': [
      for (final f in inv.findings) {'category': f.category.name, 'title': f.title, 'weight': f.weight, 'tool': f.tool},
    ],
    'entityCounts': counts,
    'links': [
      for (final u in inv.urls)
        {
          'host': u.host,
          'official': u.official,
          'imitates': u.imitates,
          'domainAgeDays': u.domainAgeDays,
          'redirects': u.hops.length - 1,
        },
    ],
  };
}

Map<String, dynamic> relationshipSummary(RelationshipReport r) => {
      'score': r.score,
      'level': r.level.name,
      'patternType': r.patternType,
      'daysKnown': r.daysKnown,
      'daysToFirstMoneyAsk': r.daysToFirstMoneyAsk,
      'signals': [for (final s in r.signals) {'group': s.group, 'title': s.title, 'weight': s.weight}],
      'identifierCount': r.identifiers.length,
    };
