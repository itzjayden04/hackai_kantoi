import 'dart:io';

import 'net_guard.dart';
import 'tls_info.dart';

const tlsProbeSupported = true;

/// Opens a TLS connection to [host]:443 only to read its certificate, then
/// closes it. Nothing is sent over the connection.
Future<TlsInfo?> probeTls(String host, {Duration timeout = const Duration(seconds: 5)}) async {
  X509Certificate? bad;
  SecureSocket? socket;
  // Only public websites: never open a connection into the local network.
  await ensurePublicHost(Uri(scheme: 'https', host: host));
  try {
    socket = await SecureSocket.connect(host, 443, timeout: timeout, onBadCertificate: (c) {
      bad = c;
      return false;
    });
    final c = socket.peerCertificate;
    if (c == null) return null;
    return TlsInfo(issuer: c.issuer, subject: c.subject, validFrom: c.startValidity, validTo: c.endValidity, trusted: true);
  } on HandshakeException {
    final c = bad;
    if (c == null) rethrow;
    return TlsInfo(issuer: c.issuer, subject: c.subject, validFrom: c.startValidity, validTo: c.endValidity, trusted: false);
  } finally {
    socket?.destroy();
  }
}
