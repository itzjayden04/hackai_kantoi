import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import '../url_analyzer.dart' show StepLogger;
import 'keys.dart';
import 'virustotal.dart';

export 'virustotal.dart';

/// One reputation service's answer about a link.
class ReputationHit {
  final String service;
  final String summary;
  final int weight;
  const ReputationHit(this.service, this.summary, this.weight);
}

const _timeout = Duration(seconds: 8);

// ---------- Google Safe Browsing v4 ----------

Map<String, dynamic> safeBrowsingRequest(List<String> urls) => {
      'client': {'clientId': 'kantoi', 'clientVersion': '1.0.0'},
      'threatInfo': {
        'threatTypes': ['MALWARE', 'SOCIAL_ENGINEERING', 'UNWANTED_SOFTWARE', 'POTENTIALLY_HARMFUL_APPLICATION'],
        'platformTypes': ['ANY_PLATFORM'],
        'threatEntryTypes': ['URL'],
        'threatEntries': [for (final u in urls) {'url': u}],
      },
    };

/// Threat types Safe Browsing reported, empty when the links are not listed.
Set<String> parseSafeBrowsing(String body) {
  final j = jsonDecode(body) as Map<String, dynamic>;
  return {for (final m in (j['matches'] as List? ?? const [])) if (m is Map && m['threatType'] is String) m['threatType'] as String};
}

String _threatWords(Set<String> t) => t
    .map((x) => switch (x) {
          'SOCIAL_ENGINEERING' => 'phishing or scam',
          'MALWARE' => 'malware',
          'UNWANTED_SOFTWARE' => 'unwanted software',
          _ => 'harmful app',
        })
    .toSet()
    .join(', ');

// VirusTotal lives in virustotal.dart (link, website, fresh scans, limits).

// ---------- URLhaus (abuse.ch) ----------

/// (listed, status, threat) from a URLhaus url or host answer.
(bool, String?, String?) parseUrlhaus(String body) {
  final j = jsonDecode(body) as Map<String, dynamic>;
  if (j['query_status'] != 'ok') return (false, null, null);
  if (j.containsKey('urls')) {
    final urls = (j['urls'] as List? ?? const []);
    final online = urls.where((u) => u is Map && u['url_status'] == 'online').length;
    return (urls.isNotEmpty, '${urls.length} bad link(s) on this host, $online still online', urls.isEmpty ? null : (urls.first as Map)['threat'] as String?);
  }
  return (true, j['url_status'] as String?, j['threat'] as String?);
}

/// Checks [url] with every reputation service that has a key, in parallel.
/// Only the link itself is sent, never the message.
///
/// [vtDepth] decides how much of VirusTotal is used (see [checkVirusTotal]);
/// in [quick] mode VirusTotal never starts a scan that has to be waited for.
Future<List<ReputationHit>> checkReputation(
  String url, {
  required ForensicKeys keys,
  required http.Client client,
  required StepLogger log,
  VtDepth vtDepth = VtDepth.lookup,
  bool quick = false,
  void Function()? onChange,
  VtLimiter? vtLimiter,
  VtCache? vtCache,
  List<Duration>? vtPollDelays,
}) async {
  final host = Uri.tryParse(url)?.host ?? url;
  final hits = <ReputationHit>[];

  Future<void> run(String tool, String action, String key, Future<String> Function(LogStep s) body) async {
    if (key.isEmpty) {
      log(tool, action, sentOffDevice: false)
        ..result = 'Skipped: no API key set (add one in Settings)'
        ..status = StepStatus.skipped;
      return;
    }
    final s = log(tool, action, sentOffDevice: true);
    try {
      s
        ..result = await body(s)
        ..status = StepStatus.done;
    } catch (e) {
      s
        ..result = 'Lookup unavailable'
        ..status = StepStatus.failed;
    }
  }

  await Future.wait([
    run('Google Safe Browsing', 'Checking $host against Google\'s list of dangerous sites', keys.safeBrowsing, (s) async {
      final res = await client
          .post(Uri.parse('https://safebrowsing.googleapis.com/v4/threatMatches:find?key=${Uri.encodeQueryComponent(keys.safeBrowsing)}'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode(safeBrowsingRequest([url])))
          .timeout(_timeout);
      if (res.statusCode != 200) throw StateError('${res.statusCode}');
      final t = parseSafeBrowsing(res.body);
      if (t.isEmpty) return 'Not on Google\'s list';
      hits.add(ReputationHit('Google Safe Browsing', 'Google lists this link as ${_threatWords(t)}', 30));
      return 'Listed as ${_threatWords(t)}';
    }),
    () async {
      if (keys.virusTotal.isEmpty) {
        log('VirusTotal', 'Looking up $host in VirusTotal', sentOffDevice: false)
          ..result = 'Skipped: no API key set (add one in Settings)'
          ..status = StepStatus.skipped;
        return;
      }
      hits.addAll(await checkVirusTotal(url,
          apiKey: keys.virusTotal,
          client: client,
          log: log,
          depth: vtDepth,
          quick: quick,
          limiter: vtLimiter,
          cache: vtCache,
          pollDelays: vtPollDelays ?? const [Duration(seconds: 15), Duration(seconds: 12)],
          timeout: _timeout,
          onChange: onChange));
    }(),
    run('URLhaus', 'Checking $host in the URLhaus list of malware links', keys.abuseCh, (s) async {
      final headers = {'Auth-Key': keys.abuseCh};
      var res = await client.post(Uri.parse('https://urlhaus-api.abuse.ch/v1/url/'), headers: headers, body: {'url': url}).timeout(_timeout);
      if (res.statusCode != 200) throw StateError('${res.statusCode}');
      var (listed, status, threat) = parseUrlhaus(res.body);
      var what = 'This exact link';
      if (!listed) {
        res = await client.post(Uri.parse('https://urlhaus-api.abuse.ch/v1/host/'), headers: headers, body: {'host': host}).timeout(_timeout);
        if (res.statusCode == 200) {
          (listed, status, threat) = parseUrlhaus(res.body);
          what = 'This website';
        }
      }
      if (!listed) return 'Not listed';
      hits.add(ReputationHit('URLhaus', '$what is listed by URLhaus for ${threat?.replaceAll('_', ' ') ?? 'malware'}${status == null ? '' : ' ($status)'}', 22));
      return 'Listed${status == null ? '' : ': $status'}';
    }),
  ]);
  return hits;
}

/// Findings for the services that flagged the link.
List<Finding> reputationFindings(List<ReputationHit> hits) => [
      for (final h in hits)
        Finding(
          category: CueCategory.link,
          title: 'Flagged by ${h.service}',
          explanation: '${h.summary}.',
          weight: h.weight,
          tool: h.service,
        ),
    ];
