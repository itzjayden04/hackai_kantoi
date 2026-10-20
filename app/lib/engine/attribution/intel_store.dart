/// Kantoi's local scam database: seeded with demo data, grown by the crawler
/// and by reports users approve, and saved on the device.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../redaction.dart';
import 'crawler.dart';
import 'fingerprint.dart';
import 'graph.dart';
import 'intel_models.dart';
import 'storage.dart';

const seedAsset = 'assets/intel_seed.json';
const crawlEvery = Duration(hours: 4);

/// Optional abuse.ch key for URLhaus, set at build time. Users can override
/// it in Settings.
const buildAbusechKey = String.fromEnvironment('ABUSECH_AUTH_KEY');

class IntelDb {
  final Map<String, IntelEntity> entities = {};
  final List<IntelReport> reports = [];
  final List<NewsItem> news = [];
  DateTime? lastCrawl;
  int ctCursor = 0;
  int seedVersion = 0;

  /// Adds [e], or merges it into the entity already stored under its id.
  IntelEntity upsert(IntelEntity e) {
    final old = entities[e.id];
    if (old == null) return entities[e.id] = e;
    if (e.firstSeen.isBefore(old.firstSeen)) old.firstSeen = e.firstSeen;
    if (e.lastSeen.isAfter(old.lastSeen)) old.lastSeen = e.lastSeen;
    if (e.evidence > old.evidence) old.evidence = e.evidence;
    old
      ..brand ??= e.brand
      ..registrar ??= e.registrar
      ..created ??= e.created
      ..network ??= e.network
      ..country ??= e.country
      ..pageTitle ??= e.pageTitle
      ..faviconHash ??= e.faviconHash
      ..pageShape ??= e.pageShape
      ..snippet ??= e.snippet
      ..enriched = old.enriched || e.enriched;
    if (e.nameservers.isNotEmpty) old.nameservers = e.nameservers;
    if (e.ips.isNotEmpty) old.ips = e.ips;
    if (old.sketch.isEmpty) old.sketch = e.sketch;
    return old;
  }

  /// Entity evidence comes from the strongest report, plus a small bonus for
  /// other strong reports. Many weak reports never add up to a strong one.
  void recomputeEvidence() {
    final by = <String, List<double>>{};
    for (final r in reports) {
      for (final id in r.entityIds) {
        by.putIfAbsent(id, () => []).add(r.evidence);
      }
    }
    for (final e in entities.values) {
      final ws = by[e.id] ?? const <double>[];
      var derived = 0.0;
      if (ws.isNotEmpty) {
        final strong = ws.where((w) => w >= 0.5).length;
        derived = ws.reduce((a, b) => a > b ? a : b) + 0.05 * (strong - 1).clamp(0, 3);
      }
      final base = switch (e.source) {
        IntelSource.ct => 0.3,
        IntelSource.openphish => 0.65,
        IntelSource.urlhaus => 0.7,
        IntelSource.seen => 0.1,
        _ => 0.0,
      };
      e.evidence = (derived > base ? derived : base).clamp(0.0, 0.98);
    }
  }

  /// Keeps the store small: drops the oldest crawled entries that no report
  /// or campaign needs.
  void prune({int max = 4000}) {
    if (entities.length <= max) return;
    final used = {for (final r in reports) ...r.entityIds};
    final drop = entities.values.where((e) => !e.synthetic && !used.contains(e.id) && e.evidence < 0.5).toList()
      ..sort((a, b) => a.lastSeen.compareTo(b.lastSeen));
    for (final e in drop.take(entities.length - max)) {
      entities.remove(e.id);
    }
  }

  Map<String, dynamic> toJson() => {
        'seedVersion': seedVersion,
        'lastCrawl': lastCrawl?.toIso8601String(),
        'ctCursor': ctCursor,
        'entities': entities.values.map((e) => e.toJson()).toList(),
        'reports': reports.map((r) => r.toJson()).toList(),
        'news': news.map((n) => n.toJson()).toList(),
      };

  static IntelDb fromJson(Map<String, dynamic> j) {
    final db = IntelDb()
      ..seedVersion = j['seedVersion'] as int? ?? 0
      ..lastCrawl = DateTime.tryParse(j['lastCrawl'] as String? ?? '')
      ..ctCursor = j['ctCursor'] as int? ?? 0;
    for (final e in (j['entities'] as List? ?? const [])) {
      final x = IntelEntity.fromJson(e as Map<String, dynamic>);
      db.entities[x.id] = x;
    }
    db.reports.addAll((j['reports'] as List? ?? const []).map((r) => IntelReport.fromJson(r as Map<String, dynamic>)));
    db.news.addAll((j['news'] as List? ?? const []).map((n) => NewsItem.fromJson(n as Map<String, dynamic>)));
    return db;
  }

  /// Loads the bundled demo data. Dates are stored as "days ago" so the demo
  /// always looks current.
  void addSeed(Map<String, dynamic> j, {DateTime? now}) {
    final t = now ?? DateTime.now();
    DateTime ago(dynamic d) => t.subtract(Duration(hours: ((d as num? ?? 0) * 24).round()));
    seedVersion = j['version'] as int? ?? 1;
    final ipInfo = {for (final i in (j['ips'] as List? ?? const [])) (i as Map)['ip'] as String: i};
    for (final d in (j['domains'] as List? ?? const [])) {
      final m = d as Map<String, dynamic>;
      final ips = (m['ips'] as List? ?? const []).cast<String>();
      upsert(IntelEntity(
        type: NodeType.domain,
        key: m['domain'] as String,
        source: IntelSource.values.byName(m['source'] as String? ?? 'demo'),
        synthetic: true,
        firstSeen: ago(m['daysAgo']),
        brand: m['brand'] as String?,
        registrar: m['registrar'] as String?,
        created: m['createdDaysAgo'] == null ? null : ago(m['createdDaysAgo']),
        nameservers: (m['nameservers'] as List? ?? const []).cast<String>(),
        ips: ips,
        pageTitle: m['title'] as String?,
        pageShape: m['shape'] as int?,
        faviconHash: m['favicon'] as String?,
        enriched: true,
      ));
      for (final ip in ips) {
        final info = ipInfo[ip];
        upsert(IntelEntity(
            type: NodeType.ip,
            key: ip,
            source: IntelSource.demo,
            synthetic: true,
            firstSeen: ago(m['daysAgo']),
            network: info?['network'] as String?,
            country: info?['country'] as String?));
      }
    }
    for (final r in (j['reports'] as List? ?? const [])) {
      final m = r as Map<String, dynamic>;
      final at = ago(m['daysAgo']);
      final ids = <String>[];
      final text = m['text'] as String?;
      if (text != null) ids.add(upsert(templateEntity(text, IntelSource.demo, at, synthetic: true)).id);
      for (final ref in (m['entities'] as List? ?? const []).cast<String>()) {
        final e = entityFromRef(ref, IntelSource.demo, at, synthetic: true);
        if (e != null) ids.add(upsert(e).id);
      }
      reports.add(IntelReport(
        id: m['id'] as String,
        at: at,
        scamType: m['scamType'] as String,
        brand: m['brand'] as String?,
        channel: m['channel'] as String? ?? 'Message',
        targets: (m['targets'] as List? ?? const []).cast<String>(),
        tactics: (m['tactics'] as List? ?? const []).cast<String>(),
        evidence: (m['evidence'] as num).toDouble(),
        entityIds: ids,
        synthetic: true,
      ));
    }
    for (final n in (j['news'] as List? ?? const [])) {
      final m = n as Map<String, dynamic>;
      news.add(NewsItem(
          title: m['title'] as String,
          link: '',
          source: 'Kantoi demo data',
          at: ago(m['daysAgo']),
          scamType: m['scamType'] as String,
          synthetic: true));
    }
    recomputeEvidence();
  }
}

/// A message script as a graph node: a fingerprint of its wording plus a
/// short snippet with personal details masked.
IntelEntity templateEntity(String text, IntelSource source, DateTime at, {bool synthetic = false, Set<String> ownValues = const {}}) {
  final norm = normaliseScript(text);
  var snippet = redact(text, findPii(text, ownValues: ownValues))
      .replaceAll(RegExp(r'\b(Mr|Mrs|Ms|Miss|Encik|Puan|Cik|Dear|Hi|Hello)\s+[A-Z][a-z]+', caseSensitive: false), r'$1 [name]')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (snippet.length > 110) snippet = '${snippet.substring(0, 107)}…';
  return IntelEntity(
    type: NodeType.template,
    key: fnv32(norm).toRadixString(16),
    source: source,
    synthetic: synthetic,
    firstSeen: at,
    snippet: snippet,
    sketch: scriptSketch(text),
  );
}

/// Turns "account:5123 4567 8901" style references into entities.
IntelEntity? entityFromRef(String ref, IntelSource source, DateTime at, {bool synthetic = false}) {
  final i = ref.indexOf(':');
  if (i < 0) return null;
  final kind = ref.substring(0, i), v = ref.substring(i + 1);
  final (NodeType, String)? tk = switch (kind) {
    'domain' => domainKey(v) == null ? null : (NodeType.domain, domainKey(v)!),
    'account' => (NodeType.bankAccount, accountKey(v)),
    'phone' => (NodeType.phone, phoneKey(v)),
    'handle' => (NodeType.handle, handleKey(v)),
    'wallet' => (NodeType.wallet, walletKey(v)),
    'photo' => (NodeType.photo, v.toLowerCase()),
    _ => null,
  };
  if (tk == null || tk.$2.isEmpty) return null;
  return IntelEntity(
      type: tk.$1, key: tk.$2, source: source, synthetic: synthetic, firstSeen: at, brand: tk.$1 == NodeType.domain ? lookalikeBrand(v) : null);
}

/// The result of a "Before you pay" check.
class QuickCheckResult {
  final String input;
  final String kind;
  final List<IntelEntity> hits;
  final Campaign? campaign;
  final int reports;
  const QuickCheckResult({required this.input, required this.kind, this.hits = const [], this.campaign, this.reports = 0});
  bool get found => hits.isNotEmpty;
  bool get demo => hits.any((h) => h.synthetic);
}

class TrendBoard {
  final List<(String, int)> topTypes;
  final List<IntelEntity> lookalikes;
  final List<Campaign> campaigns;
  final List<NewsItem> news;
  const TrendBoard(this.topTypes, this.lookalikes, this.campaigns, this.news);
}

class IntelService extends ChangeNotifier {
  final String? _seedOverride;
  final bool persist;
  IntelService({String? seedJson, this.persist = true}) : _seedOverride = seedJson;

  IntelDb db = IntelDb();
  bool loaded = false;
  Future<void>? _loading;
  IntelGraph? _graph;
  bool crawling = false;
  List<LogStep> crawlLog = [];
  String _userAbusechKey = '';
  Timer? _saveTimer;

  IntelGraph get graph => _graph ??= IntelGraph(db.entities.values, db.reports);
  String get abusechKey => _userAbusechKey.isNotEmpty ? _userAbusechKey : buildAbusechKey;
  String get userAbusechKey => _userAbusechKey;
  bool get hasDemoData => db.entities.values.any((e) => e.synthetic);

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    String? saved;
    if (persist) {
      try {
        saved = await readIntelFile();
      } catch (_) {}
      try {
        _userAbusechKey = (await SharedPreferences.getInstance()).getString('abusechKey') ?? '';
      } catch (_) {}
    }
    if (saved != null) {
      try {
        db = IntelDb.fromJson(jsonDecode(saved) as Map<String, dynamic>);
      } catch (_) {
        db = IntelDb();
      }
    }
    if (db.seedVersion == 0) {
      try {
        final seed = _seedOverride ?? await rootBundle.loadString(seedAsset);
        db.addSeed(jsonDecode(seed) as Map<String, dynamic>);
        _scheduleSave();
      } catch (_) {}
    }
    loaded = true;
    _graph = null;
    notifyListeners();
  }

  void _changed() {
    _graph = null;
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    if (!persist) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        await writeIntelFile(jsonEncode(db.toJson()));
      } catch (_) {}
    });
  }

  Future<void> setAbusechKey(String k) async {
    _userAbusechKey = k.trim();
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString('abusechKey', _userAbusechKey);
    } catch (_) {}
  }

  /// Clears everything learned on this device and reloads the demo data.
  Future<void> reset() async {
    db = IntelDb();
    _loading = null;
    if (persist) {
      try {
        await writeIntelFile(jsonEncode(db.toJson()));
      } catch (_) {}
    }
    await ensureLoaded();
  }

  /// Remembers look-alike domains checked on this device, so later crawls
  /// can enrich them and link them to campaigns.
  void rememberSeen(Iterable<IntelEntity> es) {
    var any = false;
    for (final e in es) {
      db.upsert(e);
      any = true;
    }
    if (any) {
      db.recomputeEvidence();
      _changed();
    }
  }

  // ------------------------------------------------------ community reports

  static String reportIdFor(Investigation inv) => 'r-${fnv32('${inv.artefact.text}|${inv.artefact.receivedAt.toIso8601String()}').toRadixString(16)}';

  bool hasReport(Investigation inv) => db.reports.any((r) => r.id == reportIdFor(inv));

  /// How much a report's evidence is worth, 0 to 1. It rests on what Kantoi
  /// actually found (score, look-alike links, new domains, payment details),
  /// so a fake report of a harmless message carries almost no weight.
  static double reportEvidence(Investigation inv) {
    var w = ((inv.verdict.score - 40) / 60).clamp(0.0, 1.0) * 0.7;
    if (w == 0) return 0;
    if (inv.urls.any((u) => u.imitates != null)) w += 0.1;
    if (inv.urls.any((u) => (u.domainAgeDays ?? 9999) < 60)) w += 0.08;
    if (inv.artefact.entities.any((e) => e.type == EntityType.bankAccount || e.type == EntityType.cryptoWallet)) w += 0.05;
    if (inv.findings.where((f) => f.isRisk).map((f) => f.category).toSet().length >= 3) w += 0.05;
    if (inv.log.any((s) => s.tool == 'AI analyst' && s.status == StepStatus.done)) w += 0.05;
    return double.parse(w.clamp(0.0, 0.95).toStringAsFixed(2));
  }

  /// Adds the scammer-side details of an approved report to the database.
  /// [exclude] holds values the user chose to hide; they are never stored.
  /// Returns null when the evidence is too weak to keep.
  IntelReport? addCommunityReport(Investigation inv, {Set<String> exclude = const {}, Set<String> ownValues = const {}}) {
    final w = reportEvidence(inv);
    if (w < 0.1) return null;
    final at = DateTime.now();
    final hidden = {for (final x in {...exclude, ...ownValues}) x.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '').toLowerCase()};
    bool isHidden(String v) => hidden.contains(v.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '').toLowerCase());
    final ids = <String>[];
    final tpl = templateEntity(inv.artefact.text, IntelSource.report, at, ownValues: ownValues);
    if (tpl.sketch.length >= 3) ids.add(db.upsert(tpl).id);
    final refs = <String>[
      for (final e in inv.artefact.entities)
        if (!isHidden(e.value))
          ...switch (e.type) {
            EntityType.url => ['domain:${e.value}'],
            EntityType.phone => ['phone:${e.value}'],
            EntityType.bankAccount => ['account:${e.value}'],
            EntityType.cryptoWallet => ['wallet:${e.value}'],
            EntityType.handle => ['handle:${e.value}'],
            _ => const <String>[],
          },
      for (final u in inv.urls) 'domain:${u.finalUrl}',
    ];
    for (final ref in refs) {
      final e = entityFromRef(ref, IntelSource.report, at);
      if (e != null && !ids.contains(e.id)) ids.add(db.upsert(e).id);
    }
    if (ids.isEmpty) return null;
    final t = inv.verdict.scamType.toLowerCase();
    final report = IntelReport(
      id: reportIdFor(inv),
      at: at,
      scamType: inv.verdict.scamType,
      brand: inv.urls.map((u) => u.imitates).whereType<String>().firstOrNull,
      channel: switch (inv.artefact.source) {
        Source.whatsappWeb => 'WhatsApp',
        Source.telegramWeb => 'Telegram',
        Source.chatExport => 'WhatsApp',
        _ => inv.artefact.entities.any((e) => e.type == EntityType.handle) ? 'Telegram' : 'Message',
      },
      targets: [
        if (t.contains('parcel')) 'Online shoppers',
        if (t.contains('phishing')) 'Bank customers',
        if (t.contains('job') || t.contains('task')) 'Job seekers',
        if (t.contains('officer') || t.contains('macau')) 'Older adults',
        if (t.contains('love') || t.contains('romance')) 'Single adults',
        if (t.contains('invest')) 'Savers and investors',
      ],
      tactics: inv.findings.where((f) => f.isRisk).map((f) => cueLabel(f.category)).toSet().take(5).toList(),
      evidence: w,
      entityIds: ids,
    );
    db.reports.removeWhere((r) => r.id == report.id);
    db.reports.add(report);
    db.recomputeEvidence();
    _changed();
    return report;
  }

  /// Takes back a report the user no longer wants to share.
  void removeReport(Investigation inv) {
    final id = reportIdFor(inv);
    final r = db.reports.where((r) => r.id == id).firstOrNull;
    if (r == null) return;
    db.reports.remove(r);
    final still = {for (final x in db.reports) ...x.entityIds};
    for (final e in r.entityIds) {
      if (!still.contains(e) && db.entities[e]?.source == IntelSource.report) db.entities.remove(e);
    }
    db.recomputeEvidence();
    _changed();
  }

  // ------------------------------------------------------ quick self-check

  /// "Before you pay": looks up an account, phone, wallet, handle or website.
  QuickCheckResult quickCheck(String input) {
    final s = input.trim();
    final digits = s.replaceAll(RegExp(r'[\s-]'), '');
    final candidates = <(String, String)>[];
    if (RegExp(r'^\+?\d{8,18}$').hasMatch(digits)) {
      final d = digits.replaceFirst('+', '');
      if (RegExp(r'^(0|60|1)1?\d{7,10}$').hasMatch(d) && (d.startsWith('01') || d.startsWith('601') || d.startsWith('1'))) {
        candidates.add(('phone number', 'phone:${phoneKey(d)}'));
      }
      candidates.add(('bank account', 'bankAccount:${accountKey(d)}'));
    } else if (RegExp(r'^(0x[a-fA-F0-9]{40}|T[1-9A-HJ-NP-Za-km-z]{33}|bc1[a-z0-9]{25,59})$').hasMatch(s)) {
      candidates.add(('crypto wallet', 'wallet:${walletKey(s)}'));
    } else if (s.startsWith('@') || s.contains('t.me/')) {
      candidates.add(('handle', 'handle:${handleKey(s)}'));
    } else if (s.contains('.')) {
      final k = domainKey(s);
      if (k != null) candidates.add(('website', 'domain:$k'));
    }
    final g = graph;
    final hits = [for (final c in candidates) ?g.nodes[c.$2]].where((e) => e.source != IntelSource.seen).toList();
    final kind = hits.isNotEmpty
        ? candidates.firstWhere((c) => c.$2 == hits.first.id).$1
        : candidates.isEmpty
            ? 'detail'
            : candidates.first.$1;
    final campaign = hits.map((h) => g.campaignOf[h.id]).whereType<Campaign>().firstOrNull;
    final reports = db.reports.where((r) => r.entityIds.any((id) => hits.any((h) => h.id == id))).length;
    return QuickCheckResult(input: s, kind: kind, hits: hits, campaign: campaign, reports: reports);
  }

  /// Compares a profile photo with photos seen in scam reports.
  QuickCheckResult checkPhoto(Uint8List bytes) {
    final fp = imageFingerprint(bytes);
    final g = graph;
    final hits = g.nodes.values.where((e) => e.type == NodeType.photo && hexDistance(e.key, fp) <= 10).toList();
    final campaign = hits.map((h) => g.campaignOf[h.id]).whereType<Campaign>().firstOrNull;
    final reports = db.reports.where((r) => r.entityIds.any((id) => hits.any((h) => h.id == id))).length;
    return QuickCheckResult(input: 'profile photo', kind: 'profile photo', hits: hits, campaign: campaign, reports: reports);
  }

  // ------------------------------------------------------ trend board

  TrendBoard trends({DateTime? now}) {
    final t = now ?? DateTime.now();
    final week = t.subtract(const Duration(days: 7));
    final votes = <String, int>{};
    for (final r in db.reports.where((r) => r.at.isAfter(week) && r.evidence >= 0.3)) {
      votes[r.scamType] = (votes[r.scamType] ?? 0) + 1;
    }
    for (final n in db.news.where((n) => n.at.isAfter(week))) {
      votes[n.scamType] = (votes[n.scamType] ?? 0) + 1;
    }
    final top = (votes.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => (e.key, e.value)).take(5).toList();
    final look = db.entities.values.where((e) => e.type == NodeType.domain && e.brand != null && e.source != IntelSource.seen).toList()
      ..sort((a, b) => b.firstSeen.compareTo(a.firstSeen));
    final active = graph.campaigns.where((c) => t.difference(c.lastSeen).inDays <= 45).take(8).toList();
    final news = List.of(db.news)..sort((a, b) => b.at.compareTo(a.at));
    return TrendBoard(top, look.take(8).toList(), active, news.take(8).toList());
  }

  // ------------------------------------------------------ crawler

  bool get crawlDue => db.lastCrawl == null || DateTime.now().difference(db.lastCrawl!) > crawlEvery;

  /// Runs the passive crawler. Every online step is logged; any step that
  /// fails is skipped and the rest carry on.
  Future<void> crawl({bool force = false, http.Client? client}) async {
    await ensureLoaded();
    if (crawling || !force && !crawlDue) return;
    crawling = true;
    crawlLog = [];
    notifyListeners();
    final c = client ?? http.Client();
    LogStep log(String tool, String action, {bool sentOffDevice = false}) {
      final s = LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice);
      crawlLog = [...crawlLog, s];
      notifyListeners();
      return s;
    }

    final now = DateTime.now();
    var added = 0;
    try {
      // 1. Certificate Transparency: new look-alike certificates.
      for (var i = 0; i < 3; i++) {
        final w = ctWatchWords[(db.ctCursor + i) % ctWatchWords.length];
        final hits = await crawlStep(
            log,
            'Certificate watcher',
            'Looking for new "$w" look-alike certificates (crt.sh)',
            () async => parseCrtSh(
                await fetchText(c, Uri.https('crt.sh', '/', {'q': '%$w%', 'output': 'json', 'exclude': 'expired'}),
                    timeout: const Duration(seconds: 25), maxBytes: 12 << 20),
                since: now.subtract(const Duration(days: 14))),
            (List<CtHit> h) => h.isEmpty ? 'No new look-alikes' : '${h.length} new look-alike(s), newest ${h.first.domain}');
        for (final h in (hits ?? const <CtHit>[]).take(25)) {
          db.upsert(IntelEntity(type: NodeType.domain, key: h.domain, source: IntelSource.ct, firstSeen: h.notBefore, brand: h.brand));
          added++;
        }
      }
      db.ctCursor = (db.ctCursor + 3) % ctWatchWords.length;

      // 2. Public threat feeds, filtered to Malaysia.
      final op = await crawlStep(log, 'Threat feeds', 'Reading the OpenPhish community feed',
          () async => parseOpenPhish(await fetchText(c, Uri.parse('https://openphish.com/feed.txt'))), (List<String> l) => '${l.length} Malaysian link(s)');
      for (final u in (op ?? const <String>[]).take(40)) {
        final k = domainKey(u);
        if (k == null) continue;
        db.upsert(IntelEntity(type: NodeType.domain, key: k, source: IntelSource.openphish, firstSeen: now, brand: lookalikeBrand(hostOf(u) ?? k)));
        added++;
      }
      if (abusechKey.isEmpty) {
        log('Threat feeds', 'URLhaus feed')
          ..result = 'Skipped: no abuse.ch key set'
          ..status = StepStatus.skipped;
      } else {
        final uh = await crawlStep(
            log,
            'Threat feeds',
            'Reading recent URLhaus links',
            () async => parseUrlhaus(
                await fetchText(c, Uri.parse('https://urlhaus-api.abuse.ch/v1/urls/recent/limit/1000/'), headers: {'Auth-Key': abusechKey})),
            (List<(String, DateTime?)> l) => '${l.length} Malaysian link(s)');
        for (final (u, at) in (uh ?? const <(String, DateTime?)>[]).take(40)) {
          final k = domainKey(u);
          if (k == null) continue;
          db.upsert(IntelEntity(type: NodeType.domain, key: k, source: IntelSource.urlhaus, firstSeen: at ?? now, brand: lookalikeBrand(hostOf(u) ?? k)));
          added++;
        }
      }

      // 3. Enrich new domains: registration, DNS, hosting network.
      final pending = db.entities.values.where((e) => e.type == NodeType.domain && !e.synthetic && !e.enriched).toList()
        ..sort((a, b) => b.firstSeen.compareTo(a.firstSeen));
      final robots = <String, List<(bool, String)>>{};
      for (final d in pending.take(6)) {
        final f = await crawlStep(log, 'Domain enrichment', 'Looking up registration, DNS and hosting for ${d.key}', () => lookupDomain(c, d.key),
            (DomainFacts f) => [
                  if (f.registrar != null) f.registrar!,
                  if (f.created != null) 'registered ${shortDate(f.created!)}',
                  if (f.nameservers.isNotEmpty) '${f.nameservers.length} nameserver(s)',
                  if (f.network != null) 'hosted by ${f.network}${f.country == null ? '' : ' (${f.country})'}',
                ].join(', ').ifEmpty('No public records'));
        d.enriched = true;
        if (f == null) continue;
        db.upsert(IntelEntity(
            type: NodeType.domain, key: d.key, source: d.source, firstSeen: d.firstSeen, registrar: f.registrar, created: f.created, nameservers: f.nameservers, ips: f.ips));
        for (final ip in f.ips) {
          db.upsert(IntelEntity(type: NodeType.ip, key: ip, source: d.source, firstSeen: now, network: f.network, country: f.country));
        }
        // 4. Snapshot look-alike pages (front page only, robots.txt first).
        if (d.brand != null && f.ips.isNotEmpty) {
          final snap = await crawlStep(log, 'Page snapshot', 'Saving the title and icon of ${d.key} (robots.txt respected)',
              () => snapshotPage(c, d.key, robots), (PageSnapshot? p) => p == null ? 'robots.txt asks crawlers to stay out, skipped' : 'Title: ${p.title ?? 'none'}');
          if (snap != null) {
            db.upsert(IntelEntity(
                type: NodeType.domain, key: d.key, source: d.source, firstSeen: d.firstSeen, pageTitle: snap.title, pageShape: snap.shape, faviconHash: snap.favicon));
          }
        }
      }

      // 5. News and public advisories (major news sites, not government portals).
      for (final (name, url) in newsFeeds) {
        final items = await crawlStep(log, 'News watcher', 'Reading scam stories from $name', () async {
          final u = Uri.parse(url);
          if (!await robotsOk(c, u, robots)) throw StateError('robots.txt asks crawlers to stay out');
          return parseRss(await fetchText(c, u), name);
        }, (List<NewsItem> l) => l.isEmpty ? 'No scam stories today' : '${l.length} scam stor${l.length == 1 ? 'y' : 'ies'}');
        for (final n in items ?? const <NewsItem>[]) {
          if (!db.news.any((x) => x.title == n.title)) db.news.add(n);
        }
      }
      db.news.sort((a, b) => b.at.compareTo(a.at));
      if (db.news.length > 60) db.news.removeRange(60, db.news.length);

      db
        ..lastCrawl = now
        ..recomputeEvidence()
        ..prune();
      _graph = null;
      log('Scam map', 'Updating campaigns')
        ..result = '$added new item(s), ${graph.campaigns.length} campaign(s) in the map'
        ..status = StepStatus.done;
    } finally {
      crawling = false;
      if (client == null) c.close();
      _changed();
    }
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

final intel = IntelService();
