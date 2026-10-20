import 'tls_info.dart';

/// Browsers do not let a web page read certificates, so the web build skips
/// this check.
const tlsProbeSupported = false;

Future<TlsInfo?> probeTls(String host, {Duration timeout = const Duration(seconds: 5)}) async => null;
