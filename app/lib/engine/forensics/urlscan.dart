import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// What urlscan.io's remote, disposable browser saw when it opened the link.
class UrlscanResult {
  final String uuid;
  final bool malicious;
  final int score;
  final List<String> brands;
  final String? title;
  final String? effectiveUrl;
  final String? screenshotUrl;
  final String? country;
  final String? server;
  const UrlscanResult({
    required this.uuid,
    this.malicious = false,
    this.score = 0,
    this.brands = const [],
    this.title,
    this.effectiveUrl,
    this.screenshotUrl,
    this.country,
    this.server,
  });

  String get verdictText => malicious
      ? 'urlscan.io rates this page malicious${brands.isEmpty ? '' : ' (imitates ${brands.join(', ')})'}'
      : brands.isNotEmpty
          ? 'urlscan.io sees ${brands.join(', ')} branding'
          : 'urlscan.io found nothing known to be bad';
}

/// Submission body: unlisted (not public), browsing from Malaysia.
Map<String, dynamic> urlscanSubmission(String url) => {'url': url, 'visibility': 'unlisted', 'country': 'my'};

/// The scan id from urlscan.io's submission answer.
String? parseUrlscanSubmit(String body) => (jsonDecode(body) as Map<String, dynamic>)['uuid'] as String?;

UrlscanResult parseUrlscanResult(String uuid, String body) {
  final j = jsonDecode(body) as Map<String, dynamic>;
  final overall = (j['verdicts'] as Map?)?['overall'] as Map? ?? const {};
  final brandList = <String>{
    for (final key in ['overall', 'urlscan'])
      for (final b in (((j['verdicts'] as Map?)?[key] as Map?)?['brands'] as List? ?? const []))
        if (b is Map && b['name'] is String) b['name'] as String else if (b is String) b,
  };
  final page = j['page'] as Map? ?? const {};
  final task = j['task'] as Map? ?? const {};
  return UrlscanResult(
    uuid: uuid,
    malicious: overall['malicious'] == true,
    score: (overall['score'] as num?)?.toInt() ?? 0,
    brands: brandList.toList(),
    title: (page['title'] as String?)?.trim().isEmpty == true ? null : page['title'] as String?,
    effectiveUrl: page['url'] as String?,
    screenshotUrl: task['screenshotURL'] as String? ?? 'https://urlscan.io/screenshots/$uuid.png',
    country: page['country'] as String?,
    server: page['server'] as String?,
  );
}

/// Submits [url] to urlscan.io and polls until the scan is ready or
/// [maxWait] passes. Returns null if it never finished.
Future<UrlscanResult?> runUrlscan(
  String url, {
  required String apiKey,
  required http.Client client,
  Duration maxWait = const Duration(seconds: 40),
  Duration firstWait = const Duration(seconds: 10),
  Duration pollEvery = const Duration(seconds: 3),
}) async {
  final sub = await client
      .post(Uri.parse('https://urlscan.io/api/v1/scan/'),
          headers: {'API-Key': apiKey, 'Content-Type': 'application/json'}, body: jsonEncode(urlscanSubmission(url)))
      .timeout(const Duration(seconds: 10));
  if (sub.statusCode != 200) throw StateError('urlscan.io refused the scan (${sub.statusCode})');
  final uuid = parseUrlscanSubmit(sub.body);
  if (uuid == null) throw StateError('urlscan.io gave no scan id');
  final deadline = DateTime.now().add(maxWait);
  await Future<void>.delayed(firstWait);
  while (true) {
    final res = await client
        .get(Uri.parse('https://urlscan.io/api/v1/result/$uuid/'), headers: {'API-Key': apiKey})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return parseUrlscanResult(uuid, res.body);
    if (res.statusCode != 404) throw StateError('urlscan.io error ${res.statusCode}');
    if (DateTime.now().isAfter(deadline)) return null;
    await Future<void>.delayed(pollEvery);
  }
}
