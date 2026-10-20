/// "Who's behind it?": links a checked item to known campaigns through the
/// infrastructure, accounts and scripts it shares with them.
library;

import 'package:http/http.dart' as http;

import '../models.dart';
import '../url_analyzer.dart' show StepLogger;
import 'crawler.dart';
import 'graph.dart';
import 'intel_models.dart';
import 'intel_store.dart';

export 'intel_models.dart' show AttributionResult;

class _Probe {
  final IntelEntity entity;
  final String raw;
  final int? start;
  final int? end;
  _Probe(this.entity, this.raw, this.start, this.end);
}

List<_Probe> _probes(Artefact a, List<UrlReport> urls, DateTime now) {
  final out = <String, _Probe>{};
  void add(IntelEntity? e, String raw, int? s, int? end) {
    if (e != null && !out.containsKey(e.id)) out[e.id] = _Probe(e, raw, s, end);
  }

  for (final e in a.entities) {
    final ref = switch (e.type) {
      EntityType.url => 'domain',
      EntityType.phone => 'phone',
      EntityType.bankAccount => 'account',
      EntityType.cryptoWallet => 'wallet',
      EntityType.handle => 'handle',
      _ => null,
    };
    if (ref != null) add(entityFromRef('$ref:${e.value}', IntelSource.seen, now), e.value, e.start, e.end);
  }
  for (final u in urls) {
    final pos = a.text.indexOf(u.input);
    final e = entityFromRef('domain:${u.finalUrl}', IntelSource.seen, now);
    if (e != null) {
      final known = out[e.id]?.entity ?? e;
      known
        ..registrar ??= u.registrar
        ..created ??= u.domainAgeDays == null ? null : now.subtract(Duration(days: u.domainAgeDays!))
        ..brand ??= u.imitates;
      add(known, u.finalUrl, pos < 0 ? null : pos, pos < 0 ? null : pos + u.input.length);
    }
  }
  final tpl = templateEntity(a.text, IntelSource.seen, now);
  if (tpl.sketch.length >= 4) add(tpl, 'the message wording', null, null);
  return out.values.toList();
}

/// Looks for the checked item in the local scam database. With [network],
/// new look-alike websites are looked up (nameservers and server address)
/// so they can be tied to campaigns by shared infrastructure.
Future<AttributionResult> attributeArtefact(
  Artefact a,
  List<UrlReport> urls, {
  StepLogger? log,
  bool network = true,
  http.Client? client,
  IntelService? service,
}) async {
  final svc = service ?? intel;
  final step = log?.call('Threat intel', 'Looking for this in known scam campaigns');
  try {
    await svc.ensureLoaded();
    final now = DateTime.now();
    final probes = _probes(a, urls, now);
    final g = svc.graph;

    // Live lookup for new look-alike domains only, at most two.
    if (network && log != null) {
      final fresh = probes
          .where((p) => p.entity.type == NodeType.domain && p.entity.brand != null && !g.nodes.containsKey(p.entity.id))
          .take(2)
          .toList();
      if (fresh.isNotEmpty) {
        final c = client ?? http.Client();
        try {
          for (final p in fresh) {
            final f = await crawlStep(log, 'Threat intel', 'Checking who hosts ${p.entity.key} (nameservers and server address)',
                () => lookupDomain(c, p.entity.key, registry: false), (DomainFacts f) {
              final ns = f.nameservers.where((n) => !popularNameserver(n)).toList();
              return [
                if (ns.isNotEmpty) 'nameserver ${ns.first}',
                if (f.ips.isNotEmpty) 'server ${f.ips.first}',
                if (f.network != null) 'network ${f.network}',
              ].join(', ').ifEmpty('No DNS records found');
            });
            if (f == null) continue;
            p.entity
              ..nameservers = f.nameservers
              ..ips = f.ips
              ..network = f.network
              ..country = f.country
              ..enriched = true;
          }
        } finally {
          if (client == null) c.close();
        }
      }
    }

    final result = matchProbes(g, probes.map((p) => (p.entity, p.raw, p.start, p.end)).toList());
    // Remember look-alike sites checked here so later crawls can link them.
    svc.rememberSeen(probes.where((p) => p.entity.type == NodeType.domain && p.entity.brand != null && !g.nodes.containsKey(p.entity.id)).map((p) => p.entity));
    if (step != null) {
      step
        ..result = result.campaign != null
            ? 'Matches "${result.campaign!.label}"${result.demo ? ' (demo data)' : ''}, ${(result.confidence * 100).round()}% sure'
            : result.found
                ? 'Found ${result.matches.length} link(s) to the scam database, no campaign'
                : 'No match among ${g.nodes.length} known scam details'
        ..status = StepStatus.done;
    }
    return result;
  } catch (e) {
    step
      ?..result = 'Scam database unavailable ($e)'
      ..status = StepStatus.failed;
    return AttributionResult.none;
  }
}

/// Convenience wrapper for a finished investigation.
Future<AttributionResult> attribute(Investigation inv, {StepLogger? log, bool network = false, IntelService? service}) =>
    attributeArtefact(inv.artefact, inv.urls, log: log, network: network, service: service);

/// Scores each campaign by the links the probes have into it. Confidence is
/// 1 minus the chance that every link is a coincidence.
AttributionResult matchProbes(IntelGraph g, List<(IntelEntity, String, int?, int?)> probes) {
  final matches = <IntelMatch>[];
  final extraEdges = <IntelEdge>[];
  final extraNodes = <String, IntelEntity>{};
  final perCampaign = <String, List<IntelMatch>>{};
  final seeds = <String>{};

  for (final (p, raw, s, e) in probes) {
    final known = g.nodes[p.id];
    if (known != null && known.source != IntelSource.seen) {
      final st = 0.5 + 0.45 * known.evidence;
      final m = IntelMatch(
          value: raw, entity: known, why: '${nodeTypeLabel(known.type)} ${known.display} is in the database (${sourceLabel(known.source).toLowerCase()})', strength: st, start: s, end: e);
      matches.add(m);
      seeds.add(known.id);
      final c = g.campaignOf[known.id];
      if (c != null) perCampaign.putIfAbsent(c.id, () => []).add(m);
      continue;
    }
    for (final edge in g.linksFor(p, probe: true)) {
      final other = g.nodes[edge.other(p.id)];
      if (other == null || other.source == IntelSource.seen) continue;
      final st = edge.strength * (0.6 + 0.4 * other.evidence);
      if (st < 0.2) continue;
      final m = IntelMatch(value: raw, entity: other, via: edge.kind, why: edge.evidence, strength: st, start: s, end: e);
      matches.add(m);
      extraEdges.add(edge);
      extraNodes[p.id] = p;
      seeds.add(p.id);
      final c = g.campaignOf[other.id];
      if (c != null) perCampaign.putIfAbsent(c.id, () => []).add(m);
    }
  }
  if (matches.isEmpty) return AttributionResult.none;
  matches.sort((a, b) => b.strength.compareTo(a.strength));

  Campaign? best;
  var conf = 0.0;
  for (final entry in perCampaign.entries) {
    // Several links from the same item through the same entity count once.
    final byEntity = <String, double>{};
    for (final m in entry.value) {
      final k = '${m.entity.id}|${m.value}';
      if ((byEntity[k] ?? 0) < m.strength) byEntity[k] = m.strength;
    }
    final miss = byEntity.values.fold(1.0, (acc, s) => acc * (1 - s));
    final c = (1 - miss).clamp(0.0, 0.97);
    if (c > conf) {
      conf = c;
      best = g.campaigns.firstWhere((x) => x.id == entry.key);
    }
  }

  final findings = <Finding>[];
  final top = best == null ? matches.first : perCampaign[best.id]!.reduce((a, b) => a.strength >= b.strength ? a : b);
  final demoNote = (best?.synthetic ?? top.entity.synthetic) ? ' (demo data)' : '';
  if (best != null && conf >= 0.35) {
    findings.add(Finding(
      category: CueCategory.knownScam,
      title: 'Linked to a known scam campaign',
      explanation: 'Matches "${best.label}"$demoNote. ${top.why}.',
      weight: (15 + 30 * conf).round(),
      tool: 'Threat intel',
      start: top.start,
      end: top.end,
    ));
  } else if (top.via == null && top.entity.evidence >= 0.3) {
    final feed = top.entity.source == IntelSource.openphish || top.entity.source == IntelSource.urlhaus;
    findings.add(Finding(
      category: CueCategory.knownScam,
      title: feed ? 'Listed in a public phishing feed' : top.entity.source == IntelSource.ct ? 'Newly made look-alike website' : 'Reported before',
      explanation: '${top.why}$demoNote.',
      weight: (8 + 25 * top.entity.evidence).round(),
      tool: 'Threat intel',
      start: top.start,
      end: top.end,
    ));
  }

  return AttributionResult(
    campaign: best,
    confidence: best == null ? 0 : conf,
    matches: matches,
    linkedDomains: best?.domains ?? 0,
    linkedReports: best?.reports.length ?? 0,
    graph: g.around(seeds, limit: 50, extra: extraEdges, extraNodes: extraNodes),
    findings: findings,
  );
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
