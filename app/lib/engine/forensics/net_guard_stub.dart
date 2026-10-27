import 'net_address.dart';

/// The web build cannot resolve names itself; the browser's own rules apply,
/// and addresses written into the link are still checked.
const bool runningFlutterTest = false;

/// For tests: a resolver to use instead of none.
Future<List<List<int>>> Function(String host)? debugResolveHost;

Future<void> ensurePublicHost(Uri uri, {Duration timeout = const Duration(seconds: 4)}) async {
  final host = uri.host;
  checkHostName(host);
  final resolve = debugResolveHost;
  if (resolve == null || host.isEmpty || literalAddress(host) != null) return;
  List<List<int>> addresses;
  try {
    addresses = await resolve(host).timeout(timeout);
  } catch (_) {
    return;
  }
  checkResolved(host, addresses);
}
