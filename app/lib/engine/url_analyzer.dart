import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'punycode.dart';
import 'forensics/homoglyphs.dart' show foldConfusables;
import 'forensics/net_guard.dart';

import 'models.dart';

/// Official domains of brands Malaysian scams imitate most. A host on (or
/// under) one of these counts as a legitimacy signal.
const Map<String, List<String>> brands = {
  'Maybank': ['maybank2u.com.my', 'maybank.com', 'maybank.com.my', 'maybank2u.com'],
  'CIMB': ['cimbclicks.com.my', 'cimb.com.my', 'cimb.com'],
  'Public Bank': ['pbebank.com', 'publicbank.com.my'],
  'RHB': ['rhbgroup.com', 'rhbbank.com.my'],
  'Hong Leong Bank': ['hlb.com.my', 'hongleong.com.my'],
  'AmBank': ['ambank.com.my', 'ambankgroup.com'],
  'Bank Islam': ['bankislam.com', 'bankislam.biz'],
  'BSN': ['bsn.com.my', 'mybsn.com.my'],
  "Touch 'n Go": ['touchngo.com.my', 'tngdigital.com.my'],
  'Boost': ['myboost.com.my', 'boost.com.my'],
  'Grab': ['grab.com'],
  'Shopee': ['shopee.com.my', 'shopee.com'],
  'Lazada': ['lazada.com.my', 'lazada.com'],
  'Pos Malaysia': ['pos.com.my', 'poslaju.com.my'],
  'J&T Express': ['jtexpress.my'],
  'DHL': ['dhl.com', 'dhl.com.my'],
  'LHDN': ['hasil.gov.my'],
  'JPJ': ['jpj.gov.my'],
  'PDRM': ['rmp.gov.my'],
  'KWSP': ['kwsp.gov.my'],
  'MyEG': ['myeg.com.my'],
  'Bank Negara': ['bnm.gov.my'],
  'PayPal': ['paypal.com'],
  'Apple': ['apple.com', 'icloud.com'],
  'Google': ['google.com', 'google.com.my', 'youtube.com', 'goo.gl'],
  'Microsoft': ['microsoft.com', 'live.com', 'office.com', 'outlook.com'],
  'Facebook': ['facebook.com', 'fb.com', 'instagram.com', 'meta.com'],
  'WhatsApp': ['whatsapp.com', 'wa.me'],
  'Telegram': ['telegram.org', 't.me'],
  'Netflix': ['netflix.com'],
  // More Malaysian banks, couriers, utilities and agencies (official domains).
  'Affin Bank': ['affinbank.com.my', 'affinalways.com'],
  'Alliance Bank': ['alliancebank.com.my'],
  'OCBC': ['ocbc.com.my'],
  'UOB': ['uob.com.my'],
  'HSBC': ['hsbc.com.my'],
  'Standard Chartered': ['sc.com'],
  'Bank Rakyat': ['bankrakyat.com.my'],
  'Agrobank': ['agrobank.com.my'],
  'MBSB Bank': ['mbsbbank.com'],
  'GDEX': ['gdexpress.com'],
  'Ninja Van': ['ninjavan.co'],
  'City-Link': ['citylinkexpress.com'],
  'TNB': ['tnb.com.my', 'mytnb.com.my'],
  'MCMC': ['mcmc.gov.my'],
  'SSM': ['ssm.com.my'],
  'PERKESO': ['perkeso.gov.my'],
  'JPN': ['jpn.gov.my'],
  'Imigresen': ['imi.gov.my'],
};

/// Words in a hostname that point at a brand, used to catch imitations such as
/// "maybank-secure-login.xyz".
const Map<String, String> _brandKeywords = {
  'maybank': 'Maybank', 'm2u': 'Maybank', 'cimb': 'CIMB', 'publicbank': 'Public Bank', 'pbe': 'Public Bank',
  'rhb': 'RHB', 'hongleong': 'Hong Leong Bank', 'ambank': 'AmBank', 'bankislam': 'Bank Islam',
  'touchngo': "Touch 'n Go", 'tngo': "Touch 'n Go", 'tng': "Touch 'n Go", 'ewallet': "Touch 'n Go",
  'shopee': 'Shopee', 'lazada': 'Lazada', 'poslaju': 'Pos Malaysia', 'posmalaysia': 'Pos Malaysia',
  'jtexpress': 'J&T Express', 'dhl': 'DHL', 'lhdn': 'LHDN', 'hasil': 'LHDN', 'jpj': 'JPJ', 'pdrm': 'PDRM',
  'kwsp': 'KWSP', 'myeg': 'MyEG', 'banknegara': 'Bank Negara', 'paypal': 'PayPal', 'apple': 'Apple',
  'icloud': 'Apple', 'microsoft': 'Microsoft', 'office365': 'Microsoft', 'facebook': 'Facebook',
  'instagram': 'Facebook', 'whatsapp': 'WhatsApp', 'telegram': 'Telegram', 'netflix': 'Netflix', 'grab': 'Grab',
  'gdex': 'GDEX', 'ninjavan': 'Ninja Van', 'citylink': 'City-Link', 'ocbc': 'OCBC', 'hsbc': 'HSBC', 'bankrakyat': 'Bank Rakyat',
  'perkeso': 'PERKESO', 'mytnb': 'TNB', 'imigresen': 'Imigresen',
};

const _shorteners = {
  'bit.ly', 'tinyurl.com', 'cutt.ly', 'is.gd', 't.co', 'ow.ly', 'rebrand.ly', 'shorturl.at', 'tiny.cc',
  's.id', 'rb.gy', 'bit.do', 'v.gd', 'qrco.de', 'linktr.ee', 'shorturl.asia', 'urlz.fr', 'gg.gg',
};
const _riskyTlds = {
  'xyz', 'top', 'icu', 'buzz', 'cc', 'tk', 'ml', 'ga', 'cf', 'gq', 'vip', 'club', 'shop', 'online', 'site',
  'live', 'life', 'fun', 'link', 'click', 'rest', 'work', 'loan', 'win', 'bid', 'cyou', 'sbs', 'cfd',
};
const _multiPartSuffixes = {
  'com.my', 'gov.my', 'edu.my', 'org.my', 'net.my', 'name.my', 'mil.my', 'co.uk', 'org.uk', 'com.sg',
  'gov.sg', 'edu.sg', 'com.au', 'co.id', 'com.cn', 'com.hk', 'co.th', 'com.ph', 'co.jp', 'co.in', 'com.vn',
};

/// Free hosting and site builders where every customer gets a subdomain.
const _userHosting = {
  'web.app', 'firebaseapp.com', 'vercel.app', 'netlify.app', 'github.io', 'pages.dev', 'blogspot.com',
  'wixsite.com', 'weebly.com', '000webhostapp.com', 'herokuapp.com', 'glitch.me', 'ngrok-free.app',
  'workers.dev', 'square.site', 'webflow.io', 'framer.website', 'my.id', 'carrd.co', 'wordpress.com',
  'notion.site', 'gitbook.io', 'onrender.com', 'fly.dev', 'replit.app', 'azurewebsites.net', 'appspot.com',
  'r2.dev', 'myshopify.com', 'godaddysites.com', 'mystrikingly.com', 'business.site', 'linkr.bio', 'bio.link',
};

/// Link shorteners, free hosting and link-in-bio sites: anyone can make a
/// link or page on them, so how popular the platform is says nothing about
/// one link on it.
bool anyoneCanPublishOn(String host) {
  final h = host.toLowerCase();
  final reg = registrableDomain(h);
  return _shorteners.contains(h) || _shorteners.contains(reg) || _userHosting.contains(reg);
}

String registrableDomain(String host) {
  final parts = host.split('.');
  if (parts.length <= 2) return host;
  final last2 = parts.sublist(parts.length - 2).join('.');
  if (_multiPartSuffixes.contains(last2) && parts.length >= 3) {
    return parts.sublist(parts.length - 3).join('.');
  }
  return last2;
}

String? officialBrandFor(String host) {
  for (final e in brands.entries) {
    for (final d in e.value) {
      if (host == d || host.endsWith('.$d')) return e.key;
    }
  }
  return null;
}

/// Undo common character swaps so "rnaybank" and "maybаnk" both read "maybank".
/// Cyrillic and Greek look-alikes and number swaps come from homoglyphs.dart;
/// [oneAsI] reads "1" as "i" ("c1mb") instead of "l".
String _deconfuse(String s, {bool oneAsI = false}) {
  var out = foldConfusables(s, oneAsI: oneAsI);
  return out.replaceAll('rn', 'm').replaceAll('vv', 'w').replaceAll('-', '');
}

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

String _decodeHost(String host) {
  return host.split('.').map((l) {
    if (!l.startsWith('xn--')) return l;
    try {
      return punycodeDecode(l.substring(4));
    } catch (_) {
      return l;
    }
  }).join('.');
}

Uri? _parse(String raw) {
  var s = raw.trim();
  if (!RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(s)) s = 'http://$s';
  final u = Uri.tryParse(s);
  if (u == null || u.host.isEmpty) return null;
  return u;
}

class UrlAnalysis {
  final UrlReport report;
  final List<Finding> findings;
  const UrlAnalysis(this.report, this.findings);
}

typedef StepLogger = LogStep Function(String tool, String action, {bool sentOffDevice});

/// Inspects one link: static checks on the text of the URL first (no network),
/// then the redirect chain and domain registration age.
Future<UrlAnalysis> analyzeUrl(
  String raw, {
  required StepLogger log,
  http.Client? client,
  bool network = true,
}) async {
  final findings = <Finding>[];
  final uri = _parse(raw);
  if (uri == null) {
    return UrlAnalysis(UrlReport(input: raw, finalUrl: raw, host: raw, hops: const []), findings);
  }

  void add(CueCategory c, String title, String why, int w) => findings.add(
      Finding(category: c, title: title, explanation: why, weight: w, tool: 'Link inspector'));

  final staticStep = log('Link inspector', 'Inspecting ${uri.host}');
  final hops = <UrlHop>[UrlHop(uri.toString(), null)];
  var finalUri = uri;

  // Follow redirects one hop at a time so every hop can be shown.
  if (network) {
    final s = log('Redirect follower', 'Following where ${uri.host} leads', sentOffDevice: true);
    final c = client ?? http.Client();
    try {
      var current = uri;
      for (var i = 0; i < 8; i++) {
        // Never follow a link or redirect into the phone's own network.
        await ensurePublicHost(current);
        final req = http.Request('GET', current)
          ..followRedirects = false
          ..headers['User-Agent'] =
              'Mozilla/5.0 (Linux; Android 14; SM-A546E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';
        final res = await c.send(req).timeout(const Duration(seconds: 6));
        // Never download the body: stop reading as soon as the headers arrive.
        await res.stream.listen(null).cancel();
        hops[hops.length - 1] = UrlHop(current.toString(), res.statusCode);
        final loc = res.headers['location'];
        if (res.statusCode >= 300 && res.statusCode < 400 && loc != null) {
          current = current.resolve(loc);
          hops.add(UrlHop(current.toString(), null));
          continue;
        }
        break;
      }
      finalUri = current;
      s
        ..result = hops.length > 1 ? '${hops.length - 1} redirect(s), ends at ${finalUri.host}' : 'No redirects'
        ..status = StepStatus.done;
    } on BlockedAddress catch (e) {
      // Stay on the last public hop; the blocked one is shown but not opened.
      finalUri = hops.length > 1 ? Uri.parse(hops[hops.length - 2].url) : uri;
      add(CueCategory.link, 'Points into your own network',
          'The link${hops.length > 1 ? ' redirects to' : ' goes to'} ${e.address}, ${e.reason}. Real websites never do this; '
              'it can be a trick to reach your router or other devices. Kantoi did not open it.',
          16);
      s
        ..result = 'Stopped: ${e.plain}'
        ..status = StepStatus.done;
    } catch (e) {
      s
        ..result = 'Could not reach the site (it may be offline or blocking checks)'
        ..status = StepStatus.failed;
    } finally {
      if (client == null) c.close();
    }
  }

  // Static checks run on every host in the chain.
  final hosts = <String>{uri.host.toLowerCase(), finalUri.host.toLowerCase()};
  String? imitates;
  var official = false;
  for (final rawHost in hosts) {
    final host = _decodeHost(rawHost);
    final reg = registrableDomain(host);
    final officialBrand = officialBrandFor(host);
    if (officialBrand != null) {
      official = true;
      continue;
    }
    if (rawHost.contains('xn--')) {
      add(CueCategory.obfuscation, 'Disguised web address',
          '$rawHost is written in encoded form (punycode) and reads as "$host", which can hide look-alike letters.', 14);
    }
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
      add(CueCategory.link, 'Bare IP address', 'The link points to a raw number address instead of a named website. Real companies do not do this.', 14);
    }
    if (_shorteners.contains(reg) || _shorteners.contains(host)) {
      add(CueCategory.link, 'Shortened link', '$host hides the real destination. Kantoi follows it to see where it really goes.', 6);
    }
    final tld = reg.split('.').last;
    if (_riskyTlds.contains(tld)) {
      add(CueCategory.link, 'Cheap, high-risk domain ending', '".$tld" domains are cheap to register and heavily used for scam sites.', 8);
    }
    if (host.split('.').length >= 5) {
      add(CueCategory.link, 'Very long address', 'The address has many parts, a trick to push the real domain out of view.', 6);
    }
    // Brand imitation: brand word in a domain the brand does not own, or a
    // near-miss spelling of an official domain.
    final clean = _deconfuse(host);
    final cleanI = _deconfuse(host, oneAsI: true);
    for (final k in _brandKeywords.entries) {
      if (k.key.length >= 4 && (clean.contains(k.key) || cleanI.contains(k.key)) ||
          RegExp('(^|[.-])${k.key}([.-]|\$)').hasMatch(host) ||
          RegExp('(^|[.-])${k.key}([.-]|\$)').hasMatch(cleanI)) {
        imitates = k.value;
        break;
      }
    }
    if (imitates == null) {
      final label = _deconfuse(reg.split('.').first);
      final labelI = _deconfuse(reg.split('.').first, oneAsI: true);
      for (final e in brands.entries) {
        for (final d in e.value) {
          final dl = d.split('.').first;
          if (dl.length >= 5 && (levenshtein(label, dl) <= 2 && label != dl || labelI == dl && reg.split('.').first != dl)) {
            imitates = e.key;
          }
        }
      }
    }
    if (imitates != null) {
      add(CueCategory.impersonation, 'Pretends to be $imitates',
          '$host uses the name $imitates but is not one of $imitates\'s official websites (${brands[imitates]!.first}).', 22);
    }
  }
  if (uri.userInfo.isNotEmpty || raw.contains('@') && !raw.contains('mailto')) {
    if (uri.userInfo.isNotEmpty) {
      add(CueCategory.link, 'Hidden real address', 'Text before "@" in a link is ignored by browsers and is used to fake a trusted name.', 14);
    }
  }
  if (uri.scheme == 'http' && raw.toLowerCase().startsWith('http://')) {
    add(CueCategory.link, 'Not encrypted', 'The link uses http, not https, so anything typed can be read in transit.', 4);
  }
  if (official) {
    findings.add(const Finding(
        category: CueCategory.legitimacy,
        title: 'Official website',
        explanation: 'The link goes to an official domain of a known Malaysian bank, company or agency.',
        weight: -18,
        tool: 'Official domain list'));
  }
  staticStep
    ..result = official
        ? 'Matches an official domain'
        : imitates != null
            ? 'Imitates $imitates'
            : '${findings.where((f) => f.isRisk).length} warning sign(s) in the address'
    ..status = StepStatus.done;

  // Domain age via RDAP (public registration data).
  int? ageDays;
  String? registrar;
  final reg = registrableDomain(_decodeHost(finalUri.host.toLowerCase()));
  if (network && !official && !RegExp(r'^\d').hasMatch(reg)) {
    final s = log('Domain registry (RDAP)', 'Looking up when $reg was registered', sentOffDevice: true);
    final c = client ?? http.Client();
    try {
      final res = await c.get(Uri.parse('https://rdap.org/domain/$reg')).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        for (final ev in (j['events'] as List? ?? [])) {
          if (ev['eventAction'] == 'registration') {
            final d = DateTime.tryParse(ev['eventDate'] as String? ?? '');
            if (d != null) ageDays = DateTime.now().difference(d).inDays;
          }
        }
        for (final ent in (j['entities'] as List? ?? [])) {
          if ((ent['roles'] as List? ?? []).contains('registrar')) {
            final v = ent['vcardArray'];
            if (v is List && v.length > 1) {
              for (final f in v[1] as List) {
                if (f is List && f.first == 'fn') registrar = f.last.toString();
              }
            }
          }
        }
        s
          ..result = ageDays == null ? 'No registration date published' : 'Registered $ageDays day(s) ago'
          ..status = StepStatus.done;
      } else {
        s
          ..result = 'Registry has no public record for $reg'
          ..status = StepStatus.skipped;
      }
    } catch (_) {
      s
        ..result = 'Registry lookup unavailable'
        ..status = StepStatus.failed;
    } finally {
      if (client == null) c.close();
    }
    if (ageDays != null) {
      if (ageDays < 30) {
        add(CueCategory.link, 'Brand-new website', '$reg was registered only $ageDays day(s) ago. Scam sites are usually days or weeks old.', 22);
      } else if (ageDays < 180) {
        add(CueCategory.link, 'Young website', '$reg is less than 6 months old ($ageDays days).', 8);
      } else if (ageDays > 365 * 3) {
        findings.add(Finding(
            category: CueCategory.legitimacy,
            title: 'Long-established website',
            explanation: '$reg has existed for over ${ageDays ~/ 365} years.',
            weight: -6,
            tool: 'Domain registry (RDAP)'));
      }
    }
  }

  return UrlAnalysis(
    UrlReport(
      input: raw,
      finalUrl: finalUri.toString(),
      host: finalUri.host,
      hops: hops,
      domainAgeDays: ageDays,
      registrar: registrar,
      official: official,
      imitates: imitates,
    ),
    findings,
  );
}

/// Public access to the look-alike helpers for the threat-intel crawler.
const Map<String, String> brandKeywords = _brandKeywords;
String deconfuse(String s) => _deconfuse(s);
String decodeHost(String host) => _decodeHost(host);
