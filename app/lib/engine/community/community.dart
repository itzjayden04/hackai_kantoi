/// Community reputation: what other Kantoi users reported about the same
/// website, phone number, bank account, wallet or email.
///
/// The engine only knows the [CommunityIntel] interface. The app plugs in a
/// Firestore-backed one when the user is signed in (see
/// lib/account/community_store.dart); tests plug in a fake. Nothing here
/// talks to the network by itself.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models.dart';
import '../url_analyzer.dart' show anyoneCanPublishOn, officialBrandFor, registrableDomain;

enum IndicatorKind { domain, phone, bankAccount, wallet, email }

String indicatorKindLabel(IndicatorKind k) => switch (k) {
      IndicatorKind.domain => 'website',
      IndicatorKind.phone => 'phone number',
      IndicatorKind.bankAccount => 'bank account',
      IndicatorKind.wallet => 'crypto wallet',
      IndicatorKind.email => 'email address',
    };

/// One thing in a message that other people can report on.
class Indicator {
  final IndicatorKind kind;

  /// The normalised value: "60112345678", "shopee-refund-my.online".
  final String value;

  /// What is shown and stored next to reports. Phone numbers, accounts and
  /// emails are masked so the community store never holds them in full.
  final String display;

  const Indicator(this.kind, this.value, this.display);

  /// The store key: kind plus a SHA-256 of the value, so the raw number or
  /// account never appears in a document path.
  String get key => '${kind.name}_${sha256.convert(utf8.encode('${kind.name}:$value')).toString().substring(0, 40)}';

  @override
  bool operator ==(Object other) => other is Indicator && other.kind == kind && other.value == value;
  @override
  int get hashCode => Object.hash(kind, value);
  @override
  String toString() => '${kind.name}:$display';
}

/// Chat links open a chat with anyone, so the domain says nothing, but the
/// number inside does.
const _chatHosts = {'wa.me', 't.me', 'chat.whatsapp.com', 'api.whatsapp.com', 'm.me'};

String normalisePhone(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('0')) d = '6$d';
  if (d.startsWith('1') && (d.length == 9 || d.length == 10)) d = '60$d';
  return d;
}

String maskDigits(String digits, {int keep = 4}) {
  if (digits.length <= keep) return digits;
  return '${'*' * (digits.length - keep).clamp(0, 6)}${digits.substring(digits.length - keep)}';
}

String _maskPhone(String d) {
  if (d.length < 8) return maskDigits(d);
  final local = d.startsWith('60') ? '0${d.substring(2)}' : '+$d';
  return '${local.substring(0, 3)}-****${local.substring(local.length - 4)}';
}

String _maskEmail(String e) {
  final at = e.indexOf('@');
  if (at <= 0) return e;
  return '${e[0]}***${e.substring(at)}';
}

/// The community key for a link: the registrable domain, or the full host
/// on free hosting (abc.web.app), or host plus path on a shortener
/// (bit.ly/abc). Official brand sites and chat links give none.
Indicator? domainIndicator(String url) {
  final withScheme = url.contains('://') ? url : 'https://$url';
  final u = Uri.tryParse(withScheme);
  if (u == null || u.host.isEmpty || u.host.contains(' ')) return null;
  var host = u.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  if (!host.contains('.')) return null;
  if (_chatHosts.contains(host)) return null;
  if (officialBrandFor(host) != null) return null;
  String value;
  if (anyoneCanPublishOn(host)) {
    final reg = registrableDomain(host);
    final seg = u.pathSegments.where((s) => s.isNotEmpty).firstOrNull;
    // A shortener: the short code is the thing. Free hosting: the subdomain.
    value = host == reg ? (seg == null ? '' : '$host/$seg') : host;
    if (value.isEmpty) return null;
  } else {
    value = registrableDomain(host);
  }
  return Indicator(IndicatorKind.domain, value, value);
}

/// Every reportable thing in [entities], de-duplicated, at most [max].
List<Indicator> indicatorsIn(List<Entity> entities, {Set<String> ownDetails = const {}, int max = 6}) {
  final out = <Indicator>{};
  final own = ownDetails.map((o) => o.replaceAll(RegExp(r'[\s-]'), '').toLowerCase()).toSet();
  bool isOwn(String v) => own.any((o) => o.isNotEmpty && (v.endsWith(o) || o.endsWith(v)));
  for (final e in entities) {
    switch (e.type) {
      case EntityType.url:
        final d = domainIndicator(e.value);
        if (d != null) out.add(d);
        // wa.me/60112345678: report the number.
        final m = RegExp(r'wa\.me/\+?(\d{9,15})', caseSensitive: false).firstMatch(e.value);
        if (m != null) {
          final p = normalisePhone(m.group(1)!);
          if (!isOwn(p)) out.add(Indicator(IndicatorKind.phone, p, _maskPhone(p)));
        }
      case EntityType.phone:
        final p = normalisePhone(e.value);
        if (p.length >= 9 && !isOwn(p)) out.add(Indicator(IndicatorKind.phone, p, _maskPhone(p)));
      case EntityType.bankAccount:
        final d = e.value.replaceAll(RegExp(r'\D'), '');
        if (d.length >= 10 && !isOwn(d)) out.add(Indicator(IndicatorKind.bankAccount, d, maskDigits(d)));
      case EntityType.cryptoWallet:
        final w = e.value.trim();
        out.add(Indicator(IndicatorKind.wallet, w, w.length > 12 ? '${w.substring(0, 6)}…${w.substring(w.length - 4)}' : w));
      case EntityType.email:
        final m = e.value.trim().toLowerCase();
        if (!isOwn(m)) out.add(Indicator(IndicatorKind.email, m, _maskEmail(m)));
      default:
        break;
    }
  }
  return out.take(max).toList();
}

/// Indicators from loose identifiers someone pasted (the relationship check):
/// links, emails, phone numbers and account numbers, one per entry.
List<Indicator> indicatorsFromIdentifiers(List<String> ids, {int max = 8}) {
  final out = <Indicator>{};
  for (final raw in ids) {
    final v = raw.trim();
    if (v.isEmpty) continue;
    if (v.contains('@') && v.contains('.') && !v.startsWith('@')) {
      final m = v.toLowerCase();
      out.add(Indicator(IndicatorKind.email, m, _maskEmail(m)));
      continue;
    }
    if (v.contains('.') || v.contains('/')) {
      final d = domainIndicator(v);
      if (d != null) out.add(d);
      final m = RegExp(r'wa\.me/\+?(\d{9,15})', caseSensitive: false).firstMatch(v);
      if (m != null) {
        final p = normalisePhone(m.group(1)!);
        out.add(Indicator(IndicatorKind.phone, p, _maskPhone(p)));
      }
      continue;
    }
    final digits = v.replaceAll(RegExp(r'\D'), '');
    final phoneLike = RegExp(r'^(\+?60|0)1\d{8,9}$').hasMatch(v.replaceAll(RegExp(r'[\s-]'), ''));
    if (phoneLike) {
      final p = normalisePhone(digits);
      out.add(Indicator(IndicatorKind.phone, p, _maskPhone(p)));
    } else if (digits.length >= 10 && digits.length <= 16) {
      out.add(Indicator(IndicatorKind.bankAccount, digits, maskDigits(digits)));
    }
  }
  return out.take(max).toList();
}

/// How many people reported any of [tallies] as a scam, counting only
/// indicators the community actually rates as scams.
int communityScamReporters(List<CommunityTally> tallies) => tallies
    .where((t) => const {CommunityLevel.some, CommunityLevel.strong}.contains(scoreTally(t).level))
    .fold(0, (a, t) => a + t.scamCount);

/// One person's report.
class CommunityReport {
  final bool scam;
  final DateTime at;
  final String? scamType;
  const CommunityReport({required this.scam, required this.at, this.scamType});
}

/// What the community said about one indicator. Each signed-in, verified
/// account counts once (the store keeps one report per account).
class CommunityTally {
  final Indicator indicator;
  final List<CommunityReport> reports;
  const CommunityTally(this.indicator, this.reports);

  int get scamCount => reports.where((r) => r.scam).length;
  int get legitCount => reports.where((r) => !r.scam).length;
}

/// How much a report counts as it ages: scam numbers and sites are reused
/// for weeks, then dropped, so old reports fade.
double reportWeight(DateTime at, DateTime now) {
  final days = now.difference(at).inDays;
  if (days <= 90) return 1.0;
  if (days <= 180) return 0.6;
  return 0.3;
}

enum CommunityLevel { none, disputed, some, strong }

/// The reputation of one indicator from its reports.
///
/// A Bayesian estimate of "this is a scam", starting from an even prior
/// (one pseudo-report each way), with recency weights. "Strong" needs at
/// least three distinct reporters, so one person (or one fake account)
/// can never brand a number or site as a known scam.
class CommunityScore {
  final double scamWeight;
  final double legitWeight;
  final int reporters;
  const CommunityScore(this.scamWeight, this.legitWeight, this.reporters);

  double get probability => (scamWeight + 1) / (scamWeight + legitWeight + 2);

  CommunityLevel get level {
    if (reporters == 0 || scamWeight == 0) return CommunityLevel.none;
    final scams = scamWeight;
    if (probability < 0.6) return CommunityLevel.disputed;
    if (scams >= 2.5 && probability >= 0.75) return CommunityLevel.strong;
    return CommunityLevel.some;
  }
}

CommunityScore scoreTally(CommunityTally t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  var s = 0.0, l = 0.0;
  for (final r in t.reports) {
    final w = reportWeight(r.at, n);
    if (r.scam) {
      s += w;
    } else {
      l += w;
    }
  }
  return CommunityScore(s, l, t.reports.length);
}

String? _topType(CommunityTally t) {
  final counts = <String, int>{};
  for (final r in t.reports) {
    final s = r.scamType?.trim();
    if (r.scam && s != null && s.isNotEmpty && s != 'Unclear') counts[s] = (counts[s] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
}

const communityTool = 'Community reports';

/// Findings for the risk score.
List<Finding> communityFindings(List<CommunityTally> tallies, {DateTime? now}) {
  final out = <Finding>[];
  for (final t in tallies) {
    final s = scoreTally(t, now: now);
    final label = indicatorKindLabel(t.indicator.kind);
    final type = _topType(t);
    final people = '${t.scamCount} Kantoi user${t.scamCount == 1 ? '' : 's'}';
    switch (s.level) {
      case CommunityLevel.strong:
        out.add(Finding(
          category: CueCategory.knownScam,
          title: 'Reported as a scam by $people',
          explanation: 'This $label (${t.indicator.display}) was reported as a scam by $people'
              '${type == null ? '' : ', mostly as a $type'}. '
              '${t.legitCount == 0 ? 'Nobody marked it as genuine.' : '${t.legitCount} marked it as genuine.'}',
          weight: 30,
          tool: communityTool,
        ));
      case CommunityLevel.some:
        out.add(Finding(
          category: CueCategory.knownScam,
          title: 'Reported as a scam by $people',
          explanation: 'This $label (${t.indicator.display}) was reported as a scam by $people. '
              'Too few reports to be sure, so it only adds a little to the risk.',
          weight: 10,
          tool: communityTool,
        ));
      case CommunityLevel.disputed:
      case CommunityLevel.none:
        break;
    }
  }
  return out;
}

/// The lowest level the community reports allow: many independent scam
/// reports on the same number or site make it at least Suspicious.
RiskLevel? communityFloor(List<CommunityTally> tallies, {DateTime? now}) {
  final levels = tallies.map((t) => scoreTally(t, now: now)).toList();
  if (levels.any((s) => s.level == CommunityLevel.strong && s.scamWeight >= 5)) return RiskLevel.danger;
  if (levels.any((s) => s.level == CommunityLevel.strong)) return RiskLevel.suspicious;
  return null;
}

/// The community store, as the engine sees it.
abstract class CommunityIntel {
  /// Shown in the activity log.
  String get name;

  /// Whether reports can be sent right now (signed in with a verified email).
  bool get canReport;

  /// Why [canReport] is false, in plain words.
  String get whyNot;

  Future<List<CommunityTally>> lookup(List<Indicator> indicators);

  /// Saves (or replaces) this account's report on each indicator. Returns
  /// how many were saved.
  Future<int> report(List<Indicator> indicators, {required bool scam, String? scamType});
}

/// Set by the app when Firebase is configured; null in tests and in the
/// background guard.
CommunityIntel? communityIntel;
