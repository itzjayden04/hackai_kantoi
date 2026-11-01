import '../engine/models.dart';
import '../engine/taxonomy.dart';
import '../report/scam_report.dart';
import 'outbox.dart';

/// Only confident "very likely a scam" results are shared.
const shareMinConfidence = 70;

/// The masked record of one high-confidence detection, or null when the
/// result is not confident enough to teach anyone anything. Holds no message
/// text, no names and no screenshots: the scam kind, the cue categories that
/// fired, the app, the hour, website names and one-way codes of numbers.
Map<String, dynamic>? detectionPayload(Investigation inv, {String? app, String appVersion = '1.2.0'}) {
  final v = inv.verdict;
  if (v.level != RiskLevel.danger || v.confidence < shareMinConfidence) return null;
  final ids = <AttackerId>[];
  for (final e in inv.artefact.entities) {
    final t = switch (e.type) {
      EntityType.phone => IdentifierType.phone,
      EntityType.email => IdentifierType.email,
      EntityType.bankAccount || EntityType.ewallet => IdentifierType.bankAccount,
      EntityType.cryptoWallet => IdentifierType.wallet,
      EntityType.handle => IdentifierType.handle,
      _ => null,
    };
    if (t != null) ids.add(AttackerId(t, e.value));
  }
  final domains = {for (final u in inv.urls) u.host.toLowerCase()}..removeWhere((d) => d.isEmpty);
  final at = inv.artefact.receivedAt;
  return {
    'v': 1,
    'kind': kindOf(inv)?.code,
    'level': v.level.name,
    'score': v.score,
    'confidence': v.confidence,
    'cues': {for (final f in inv.findings) if (f.isRisk) f.category.name}.toList(),
    'app': app ?? inv.artefact.meta['app'],
    'source': inv.artefact.source.name,
    'hour': DateTime(at.year, at.month, at.day, at.hour).toIso8601String(),
    'domains': domains.toList(),
    'identifiers': [
      for (final a in ids) {'type': a.type.name, 'code': identifierCode(a), 'masked': a.masked}
    ],
    'appVersion': appVersion,
  };
}

/// A stable id for a detection, so checking the same message twice is one record.
String detectionId(Investigation inv) =>
    identifierCode(AttackerId(IdentifierType.other, '${inv.artefact.receivedAt.millisecondsSinceEpoch}|${inv.artefact.text.hashCode}'));

/// Queues a detection when sharing is on and the result qualifies.
Future<bool> shareDetection(Investigation inv, {required bool sharingOn, String? app, Outbox? outbox}) async {
  if (!sharingOn) return false;
  final p = detectionPayload(inv, app: app);
  if (p == null) return false;
  await (outbox ?? cloudOutbox).add('detections', detectionId(inv), p);
  return true;
}
