/// Stops Kantoi's link checks from reaching private network addresses.
/// See net_address.dart for the rules; the platform part resolves names.
library;

export 'net_address.dart';
export 'net_guard_stub.dart' if (dart.library.io) 'net_guard_io.dart';
