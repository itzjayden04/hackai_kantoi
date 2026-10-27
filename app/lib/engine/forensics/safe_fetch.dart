import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'net_guard.dart';

/// How Kantoi opens a suspicious page without a real browser: its own HTTP
/// client, with no cookies, no saved logins, no downloads (it stops reading
/// after [maxPageBytes] and never writes to disk), no scripts run, a short
/// timeout, and only HTML is read.
const isolationNote =
    'Opened in Kantoi\'s isolated reader: no cookies, no saved logins, no downloads, no scripts, nothing saved, short timeout';

const maxPageBytes = 1024 * 1024;

const mobileMyUserAgent =
    'Mozilla/5.0 (Linux; Android 14; SM-A546E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';
const desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36';

class PageFetch {
  final Uri requested;
  final Uri finalUrl;
  final int? status;
  final String? contentType;
  /// The page HTML, only when the server said it is HTML.
  final String? html;
  final int bytes;
  final bool truncated;
  final List<(Uri, int?)> hops;
  const PageFetch({
    required this.requested,
    required this.finalUrl,
    required this.status,
    required this.contentType,
    required this.html,
    required this.bytes,
    required this.truncated,
    required this.hops,
  });

  bool get isHtml => html != null;
}

/// Fetches [url] the isolated way, following up to [maxHops] redirects one at
/// a time. Throws on network failure or timeout; callers log it and carry on.
/// Every hop is checked first: a hop into a private network throws
/// [BlockedAddress] and is never requested.
Future<PageFetch> fetchIsolated(
  Uri url, {
  required http.Client client,
  String userAgent = mobileMyUserAgent,
  String acceptLanguage = 'ms-MY,ms;q=0.9,en-MY;q=0.8,en;q=0.7',
  Duration timeout = const Duration(seconds: 8),
  int maxHops = 8,
}) async {
  var current = url;
  final hops = <(Uri, int?)>[];
  for (var i = 0; i <= maxHops; i++) {
    await ensurePublicHost(current);
    final req = http.Request('GET', current)
      ..followRedirects = false
      ..headers.addAll({
        'User-Agent': userAgent,
        'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5',
        'Accept-Language': acceptLanguage,
      });
    final res = await client.send(req).timeout(timeout);
    hops.add((current, res.statusCode));
    final loc = res.headers['location'];
    if (res.statusCode >= 300 && res.statusCode < 400 && loc != null && i < maxHops) {
      await _discard(res);
      current = current.resolve(loc.trim());
      continue;
    }
    final type = res.headers['content-type'];
    final html = type == null || type.contains('html');
    if (!html) {
      // Never download files: stop as soon as we know it is not a web page.
      await _discard(res);
      return PageFetch(
          requested: url, finalUrl: current, status: res.statusCode, contentType: type, html: null, bytes: 0, truncated: false, hops: hops);
    }
    final (bytes, truncated) = await _readCapped(res.stream, maxPageBytes, timeout);
    return PageFetch(
      requested: url,
      finalUrl: current,
      status: res.statusCode,
      contentType: type,
      html: utf8.decode(bytes, allowMalformed: true),
      bytes: bytes.length,
      truncated: truncated,
      hops: hops,
    );
  }
  throw StateError('Too many redirects');
}

Future<void> _discard(http.StreamedResponse res) async {
  try {
    await res.stream.listen(null).cancel();
  } catch (_) {}
}

Future<(List<int>, bool)> _readCapped(Stream<List<int>> stream, int cap, Duration timeout) async {
  final out = <int>[];
  final done = Completer<bool>();
  late StreamSubscription<List<int>> sub;
  sub = stream.listen(
    (chunk) {
      final room = cap - out.length;
      if (chunk.length >= room) {
        out.addAll(chunk.take(room));
        sub.cancel();
        if (!done.isCompleted) done.complete(true);
      } else {
        out.addAll(chunk);
      }
    },
    onDone: () {
      if (!done.isCompleted) done.complete(false);
    },
    onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    },
    cancelOnError: true,
  );
  final truncated = await done.future.timeout(timeout, onTimeout: () {
    sub.cancel();
    return true;
  });
  return (out, truncated);
}
