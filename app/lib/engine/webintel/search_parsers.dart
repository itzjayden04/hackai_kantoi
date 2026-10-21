/// Reads public search result pages (DuckDuckGo's HTML version and Bing)
/// into titles, links and snippets. No keys, no logins.
library;

import 'dart:convert';

import 'web_models.dart';

class SearchHit {
  final String title;
  final String url;
  final String snippet;
  const SearchHit(this.title, this.url, this.snippet);
  String get text => '$title $snippet';
  @override
  String toString() => '$title <$url>';
}

/// Thrown when a search engine answers with a robot check instead of results.
class SearchBlocked implements Exception {
  final String engine;
  const SearchBlocked(this.engine);
  @override
  String toString() => '$engine asked for a robot check';
}

Uri ddgSearchUri(String query) => Uri.https('html.duckduckgo.com', '/html/', {'q': query, 'kl': 'my-en'});

Uri bingSearchUri(String query) => Uri.https('www.bing.com', '/search', {'q': query, 'setlang': 'en', 'cc': 'MY'});

/// Results from html.duckduckgo.com. Ads are dropped and DuckDuckGo's
/// redirect links are unwrapped to the real page address.
List<SearchHit> parseDuckDuckGo(String html) {
  if (html.contains('anomaly-modal') || html.contains('bots use DuckDuckGo')) throw const SearchBlocked('DuckDuckGo');
  final anchors = RegExp(r'<a[^>]*class="[^"]*result__a[^"]*"[^>]*>([\s\S]*?)</a>', caseSensitive: false).allMatches(html).toList();
  final out = <SearchHit>[];
  for (var i = 0; i < anchors.length; i++) {
    final a = anchors[i];
    final blockStart = html.lastIndexOf('<div class="result', a.start);
    if (blockStart >= 0 && html.substring(blockStart, a.start).contains('result--ad')) continue;
    final href = RegExp(r'''href="([^"]+)"''').firstMatch(a.group(0)!)?.group(1);
    final url = href == null ? null : _ddgTarget(_unescapeAttr(href));
    if (url == null) continue;
    final end = i + 1 < anchors.length ? anchors[i + 1].start : html.length;
    final seg = html.substring(a.end, end);
    final snip = RegExp(r'class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)</(?:a|div|td)>', caseSensitive: false).firstMatch(seg)?.group(1) ?? '';
    out.add(SearchHit(stripHtml(a.group(1)!), url, stripHtml(snip)));
  }
  return out;
}

String? _ddgTarget(String href) {
  final u = Uri.tryParse(href.startsWith('//') ? 'https:$href' : href);
  if (u == null) return null;
  if (u.host.endsWith('duckduckgo.com')) {
    if (u.path.startsWith('/y.js')) return null; // advert
    final real = u.queryParameters['uddg'];
    return real == null ? null : _httpOnly(real);
  }
  return _httpOnly(u.toString());
}

/// Results from www.bing.com. Bing's tracking links (bing.com/ck/a) carry the
/// real address base64-encoded in "u".
List<SearchHit> parseBing(String html) {
  final blocks = html.split(RegExp(r'<li class="b_algo', caseSensitive: false));
  if (blocks.length <= 1 && (html.contains('b_captcha') || html.contains('/challenge') || html.toLowerCase().contains('captcha'))) {
    throw const SearchBlocked('Bing');
  }
  final out = <SearchHit>[];
  for (final b in blocks.skip(1)) {
    final body = b.split(RegExp(r'</li>\s*<li class="b_(?:algo|ad|ans)', caseSensitive: false)).first;
    final a = RegExp(r'<h2[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>', caseSensitive: false).firstMatch(body);
    if (a == null) continue;
    final url = _bingTarget(_unescapeAttr(a.group(1)!));
    if (url == null) continue;
    final snip = RegExp(r'<p[^>]*>([\s\S]*?)</p>', caseSensitive: false).firstMatch(body.substring(a.end))?.group(1) ??
        RegExp(r'class="b_caption"[^>]*>([\s\S]*?)</div>', caseSensitive: false).firstMatch(body)?.group(1) ??
        '';
    out.add(SearchHit(stripHtml(a.group(2)!), url, stripHtml(snip)));
  }
  return out;
}

String? _bingTarget(String href) {
  final u = Uri.tryParse(href);
  if (u == null) return null;
  if (u.host.endsWith('bing.com') && u.path.startsWith('/ck/')) {
    var enc = u.queryParameters['u'];
    if (enc == null || !enc.startsWith('a1')) return null;
    enc = enc.substring(2).replaceAll('-', '+').replaceAll('_', '/');
    while (enc!.length % 4 != 0) {
      enc += '=';
    }
    try {
      return _httpOnly(utf8.decode(base64.decode(enc)));
    } catch (_) {
      return null;
    }
  }
  if (u.host.endsWith('bing.com')) return null;
  return _httpOnly(href);
}

String? _httpOnly(String s) {
  final u = Uri.tryParse(s);
  if (u == null || (u.scheme != 'https' && u.scheme != 'http') || u.host.isEmpty) return null;
  return u.toString();
}

String _unescapeAttr(String s) => s.replaceAll('&amp;', '&').replaceAll('&#x2F;', '/').replaceAll('&#47;', '/');
