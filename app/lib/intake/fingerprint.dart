import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../engine/models.dart';

String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

/// What VirusTotal knows about a file fingerprint.
class HashVerdict {
  final bool known;
  final int malicious;
  final int suspicious;
  final int harmless;
  final int total;
  final String? name;
  final String? label;
  const HashVerdict({required this.known, this.malicious = 0, this.suspicious = 0, this.harmless = 0, this.total = 0, this.name, this.label});
}

/// Parses VirusTotal's `GET /api/v3/files/{sha256}` reply.
HashVerdict parseVirusTotal(int status, String body) {
  if (status == 404) return const HashVerdict(known: false);
  if (status != 200) throw Exception('VirusTotal error $status');
  final a = (jsonDecode(body) as Map<String, dynamic>)['data']?['attributes'] as Map<String, dynamic>? ?? {};
  final s = a['last_analysis_stats'] as Map<String, dynamic>? ?? {};
  int n(String k) => (s[k] as num?)?.toInt() ?? 0;
  return HashVerdict(
    known: true,
    malicious: n('malicious'),
    suspicious: n('suspicious'),
    harmless: n('harmless'),
    total: s.values.whereType<num>().fold<int>(0, (x, y) => x + y.toInt()),
    name: a['meaningful_name'] as String?,
    label: (a['popular_threat_classification'] as Map<String, dynamic>?)?['suggested_threat_label'] as String?,
  );
}

/// Looks up only the fingerprint, never the file. Returns the finding (if
/// any) and the text for the activity log.
Future<(Finding?, String)> lookupHash(String hash, String apiKey, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(Uri.parse('https://www.virustotal.com/api/v3/files/$hash'), headers: {'x-apikey': apiKey})
        .timeout(const Duration(seconds: 12));
    final v = parseVirusTotal(res.statusCode, res.body);
    return (hashFinding(v), hashSummary(v));
  } finally {
    if (client == null) c.close();
  }
}

String hashSummary(HashVerdict v) => !v.known
    ? 'Not seen before by VirusTotal. Only the file\'s fingerprint was checked online.'
    : '${v.malicious} of ${v.total} virus scanners flag it${v.label != null ? ' (${v.label})' : ''}. Only the file\'s fingerprint was checked online.';

Finding? hashFinding(HashVerdict v) {
  if (!v.known) return null;
  if (v.malicious >= 3) {
    return Finding(
      category: CueCategory.file,
      title: 'Known harmful file',
      explanation: '${v.malicious} virus scanners have already flagged this exact file${v.label != null ? ' as ${v.label}' : ''}. Delete it.',
      weight: 45,
      tool: 'VirusTotal fingerprint check',
    );
  }
  if (v.malicious + v.suspicious >= 1) {
    return Finding(
      category: CueCategory.file,
      title: 'Some virus scanners flag this file',
      explanation: '${v.malicious + v.suspicious} virus scanner(s) flagged this exact file. Treat it with care.',
      weight: 12,
      tool: 'VirusTotal fingerprint check',
    );
  }
  if (v.total > 20) {
    return const Finding(
      category: CueCategory.legitimacy,
      title: 'Known clean file',
      explanation: 'Virus scanners have checked this exact file before and found nothing harmful.',
      weight: -4,
      tool: 'VirusTotal fingerprint check',
    );
  }
  return null;
}
