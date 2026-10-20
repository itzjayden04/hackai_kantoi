import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'tls_info.dart';
import 'tls_probe.dart';

/// Where a website lives: its address, hosting network and country, and its
/// security certificate.
class HostFacts {
  final String host;
  final String? ip;
  final String? network;
  final String? country; // ISO 3166 two-letter code
  final TlsInfo? tls;
  final List<String> notes;
  const HostFacts(this.host, {this.ip, this.network, this.country, this.tls, this.notes = const []});
}

const _timeout = Duration(seconds: 6);

final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

/// IPv4 addresses from a DNS-over-HTTPS JSON answer (dns.google format).
List<String> parseDohAnswer(String body) {
  final j = jsonDecode(body) as Map<String, dynamic>;
  if (j['Status'] != 0) return const [];
  return [
    for (final a in (j['Answer'] as List? ?? const []))
      if (a is Map && a['type'] == 1 && a['data'] is String && _ipv4.hasMatch(a['data'] as String)) a['data'] as String,
  ];
}

/// Resolves [host] to IPv4 addresses with Google's public DNS-over-HTTPS
/// service, so the answer is the same whatever the local network does.
Future<List<String>> resolveA(String host, http.Client client) async {
  if (_ipv4.hasMatch(host)) return [host];
  final res = await client
      .get(Uri.https('dns.google', '/resolve', {'name': host, 'type': 'A'}), headers: {'Accept': 'application/dns-json'})
      .timeout(_timeout);
  if (res.statusCode != 200) throw StateError('DNS lookup failed (${res.statusCode})');
  return parseDohAnswer(res.body);
}

/// Hosting network and country from an RDAP IP record.
(String?, String?) parseIpRdap(String body) {
  final j = jsonDecode(body) as Map<String, dynamic>;
  String? org;
  for (final e in (j['entities'] as List? ?? const [])) {
    if (e is! Map) continue;
    final roles = (e['roles'] as List? ?? const []).map((r) => '$r').toSet();
    if (!roles.contains('registrant') && !roles.contains('administrative')) continue;
    final v = e['vcardArray'];
    if (v is List && v.length > 1 && v[1] is List) {
      for (final f in v[1] as List) {
        if (f is List && f.isNotEmpty && f.first == 'fn' && f.last is String) {
          org ??= f.last as String;
        }
      }
    }
  }
  final name = j['name'] as String?;
  var country = (j['country'] as String?)?.toUpperCase();
  if (country != null && country.length != 2) country = null;
  final network = org == null ? name : (name == null || org.toLowerCase().contains(name.toLowerCase()) ? org : '$org ($name)');
  return (network, country);
}

/// Hosting network and country from the free ipwho.is service.
(String?, String?) parseIpWhoIs(String body) {
  final j = jsonDecode(body) as Map<String, dynamic>;
  if (j['success'] == false) return (null, null);
  final conn = j['connection'] as Map? ?? const {};
  final org = (conn['org'] ?? conn['isp']) as String?;
  final asn = conn['asn'];
  return (org == null ? null : (asn == null ? org : '$org (AS$asn)'), (j['country_code'] as String?)?.toUpperCase());
}

/// Looks up the facts for one host. Each part fails soft; [notes] says what
/// could not be found.
Future<HostFacts> lookupHost(String host, http.Client client, {bool tls = true}) async {
  final notes = <String>[];
  String? ip, network, country;
  TlsInfo? cert;

  Future<void> addressPart() async {
    try {
      final ips = await resolveA(host, client);
      if (ips.isEmpty) {
        notes.add('no address found');
        return;
      }
      ip = ips.first;
    } catch (_) {
      notes.add('address lookup failed');
      return;
    }
    try {
      final res = await client.get(Uri.parse('https://rdap.org/ip/$ip'), headers: {'Accept': 'application/rdap+json'}).timeout(_timeout);
      if (res.statusCode == 200) (network, country) = parseIpRdap(res.body);
    } catch (_) {}
    if (country == null || network == null) {
      try {
        final res = await client.get(Uri.parse('https://ipwho.is/$ip')).timeout(_timeout);
        if (res.statusCode == 200) {
          final (n, c) = parseIpWhoIs(res.body);
          network ??= n;
          country ??= c;
        }
      } catch (_) {}
    }
    if (network == null && country == null) notes.add('hosting details unavailable');
  }

  Future<void> tlsPart() async {
    if (!tls || !tlsProbeSupported) return;
    try {
      cert = await probeTls(host);
      if (cert == null) notes.add('no certificate');
    } catch (_) {
      notes.add('no secure connection');
    }
  }

  await Future.wait([addressPart(), tlsPart()]);
  return HostFacts(host, ip: ip, network: network, country: country, tls: cert, notes: notes);
}

/// Country flag emoji for a two-letter code, e.g. "MY" -> 🇲🇾.
String flagFor(String? code) {
  if (code == null || code.length != 2) return '';
  final c = code.toUpperCase();
  return String.fromCharCodes([0x1F1E6 + c.codeUnitAt(0) - 65, 0x1F1E6 + c.codeUnitAt(1) - 65]);
}
