import 'dart:async';
import 'dart:io';

import 'net_address.dart';

/// True inside `flutter test`. Tests use fake web services, so names are not
/// looked up in real DNS there unless a test sets [debugResolveHost].
final bool runningFlutterTest = Platform.environment['FLUTTER_TEST'] == 'true';

/// For tests: replaces the system resolver.
Future<List<List<int>>> Function(String host)? debugResolveHost;

/// Throws [BlockedAddress] when [uri] points at this phone, the home or
/// office network, or the carrier's internal network. Call it before every
/// request (and every redirect hop) to a link taken from a message.
///
/// When the name cannot be resolved the check lets the request go ahead:
/// the request itself then fails the same way.
Future<void> ensurePublicHost(Uri uri, {Duration timeout = const Duration(seconds: 4)}) async {
  final host = uri.host;
  checkHostName(host);
  if (host.isEmpty || literalAddress(host) != null) return;
  final resolve = debugResolveHost ?? (runningFlutterTest ? null : _system);
  if (resolve == null) return;
  List<List<int>> addresses;
  try {
    addresses = await resolve(host).timeout(timeout);
  } catch (_) {
    return;
  }
  checkResolved(host, addresses);
}

Future<List<List<int>>> _system(String host) async => [for (final a in await InternetAddress.lookup(host)) a.rawAddress];
