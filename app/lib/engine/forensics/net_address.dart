/// Which network addresses a suspicious link may lead Kantoi to. Kantoi opens
/// scam links on the user's own phone, so a link (or a redirect) that points
/// at the phone itself, the home router or another device on the same network
/// must never be followed: that would let a scammer use Kantoi to reach
/// things that are not on the public internet.
///
/// Pure Dart (no dart:io), so the same rules run on every platform.
library;

/// Thrown instead of fetching a link that points into a private network.
class BlockedAddress implements Exception {
  final String host;
  final String address;
  final String reason;
  const BlockedAddress(this.host, this.address, this.reason);

  /// One plain-English line for the activity log.
  String get plain => host == address
      ? '$host is $reason, not a public website. Kantoi never opens those.'
      : '$host leads to $address, $reason, not a public website. Kantoi never opens those.';

  @override
  String toString() => 'BlockedAddress: $host -> $address ($reason)';
}

/// Name endings that only work inside a home, office or phone network.
const _localSuffixes = ['.localhost', '.local', '.internal', '.intranet', '.lan', '.home', '.home.arpa', '.corp', '.localdomain'];

/// The bytes of [host] when it is written as an address rather than a name:
/// dotted IPv4, IPv6 (with or without brackets), or the short and numeric
/// IPv4 forms that resolvers also accept ("2130706433", "0x7f.1", "127.1").
List<int>? literalAddress(String host) {
  var h = host.trim().toLowerCase();
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
  if (h.contains(':')) {
    try {
      return Uri.parseIPv6Address(h.split('%').first);
    } catch (_) {
      return null;
    }
  }
  return _inetAton(h);
}

/// inet_aton: one to four parts, each decimal, octal (leading 0) or hex (0x).
List<int>? _inetAton(String h) {
  if (h.isEmpty || h.endsWith('.')) return null;
  final parts = h.split('.');
  if (parts.length > 4) return null;
  final values = <int>[];
  for (final p in parts) {
    int? v;
    if (RegExp(r'^0x[0-9a-f]+$').hasMatch(p)) {
      v = p.length > 10 ? null : int.tryParse(p.substring(2), radix: 16);
    } else if (RegExp(r'^0[0-7]*$').hasMatch(p)) {
      v = p.length > 12 ? null : int.tryParse(p, radix: 8);
    } else if (RegExp(r'^[1-9][0-9]*$').hasMatch(p)) {
      v = p.length > 10 ? null : int.tryParse(p);
    }
    if (v == null) return null;
    values.add(v);
  }
  // The last part fills the remaining bytes.
  final head = values.sublist(0, values.length - 1);
  if (head.any((v) => v > 255)) return null;
  final restBytes = 4 - head.length;
  final last = values.last;
  if (last >= (1 << (8 * restBytes))) return null;
  return [
    ...head,
    for (var i = restBytes - 1; i >= 0; i--) (last >> (8 * i)) & 0xff,
  ];
}

/// Why [b] (4 or 16 bytes) is not a public internet address, or null when it is.
String? nonPublicReason(List<int> b) {
  if (b.length == 4) return _v4(b);
  if (b.length != 16) return 'not a valid address';
  bool zeros(int from, int to) => b.sublist(from, to).every((x) => x == 0);
  if (zeros(0, 10) && b[10] == 0xff && b[11] == 0xff) return _v4(b.sublist(12)); // ::ffff:a.b.c.d
  if (zeros(0, 15) && b[15] == 1) return 'this phone itself (loopback)';
  if (zeros(0, 16)) return 'an empty address';
  if (zeros(0, 12)) return _v4(b.sublist(12)); // old ::a.b.c.d form
  if (b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b && zeros(4, 12)) return _v4(b.sublist(12)); // NAT64
  if (b[0] == 0x20 && b[1] == 0x02) return _v4(b.sublist(2, 6)); // 6to4
  if ((b[0] & 0xfe) == 0xfc) return 'a private network address';
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return 'a link-local address on this network';
  if (b[0] == 0xff) return 'a multicast address';
  return null;
}

String? _v4(List<int> b) {
  final a = b[0], c = b[1];
  if (a == 0) return 'an empty address';
  if (a == 10 || (a == 172 && c >= 16 && c <= 31) || (a == 192 && c == 168)) return 'a private network address (like a home router)';
  if (a == 127) return 'this phone itself (loopback)';
  if (a == 100 && c >= 64 && c <= 127) return 'an address inside the mobile carrier\'s network';
  if (a == 169 && c == 254) return 'a link-local address on this network';
  if (a == 192 && c == 0 && b[2] == 0) return 'a reserved address';
  if (a == 198 && (c == 18 || c == 19)) return 'a reserved test address';
  if (a >= 224) return 'a multicast or reserved address';
  return null;
}

/// Writes address bytes the usual way.
String formatAddress(List<int> b) {
  if (b.length == 4) return b.join('.');
  final groups = [for (var i = 0; i < 16; i += 2) ((b[i] << 8) | b[i + 1]).toRadixString(16)];
  return groups.join(':').replaceFirst(RegExp(r'(^|:)0(:0)+(:|$)'), '::');
}

/// The checks that need no DNS: addresses written into the link and names
/// that only exist inside a local network. Throws [BlockedAddress].
void checkHostName(String host) {
  final h = host.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (h.isEmpty) return;
  final lit = literalAddress(h);
  if (lit != null) {
    final why = nonPublicReason(lit);
    if (why != null) throw BlockedAddress(host, formatAddress(lit), why);
    return;
  }
  if (h == 'localhost' || !h.contains('.') || _localSuffixes.any(h.endsWith)) {
    throw BlockedAddress(host, host, 'a name that only works inside a home or office network');
  }
}

/// Checks every address a name resolved to. Throws [BlockedAddress].
void checkResolved(String host, Iterable<List<int>> addresses) {
  for (final a in addresses) {
    final why = nonPublicReason(a);
    if (why != null) throw BlockedAddress(host, formatAddress(a), why);
  }
}
