import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../engine/attribution/fingerprint.dart' show phoneKey;
import '../engine/attribution/intel_models.dart' show IntelSource;
import '../engine/attribution/intel_store.dart';
import '../intake/image_scan.dart' show decodeQr;
import '../local_store.dart';
import '../state.dart';
import 'guard_core.dart';

/// Runs inside the background engine Android starts for phone protection.
Future<void> runGuardBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.load();
  await localStore.load();
  // The scam list loads in the background; checks before then use patterns only.
  intel.ensureLoaded().ignore();
  final core = GuardCore(knownSite: _knownSite, knownNumber: _knownNumber);
  const channel = MethodChannel('kantoi/guard_bg');
  channel.setMethodCallHandler((call) async {
    final a = Map<String, dynamic>.from(call.arguments as Map? ?? const {});
    try {
      switch (call.method) {
        case 'check':
          return await core.check(
            app: a['app'] as String? ?? '',
            chat: a['chat'] as String? ?? 'Unknown chat',
            sender: a['sender'] as String?,
            text: a['text'] as String? ?? '',
            incoming: a['incoming'] as bool? ?? true,
            ownDetails: appState.ownDetails,
          );
        case 'checkChat':
          return core.checkChat(
            app: a['app'] as String? ?? '',
            chat: a['chat'] as String? ?? '',
            visible: [
              for (final m in (a['messages'] as List? ?? []))
                if (m is Map) ('${m['text'] ?? ''}', m['incoming'] != false),
            ],
          );
        case 'checkSite':
          return await core.checkSite(a['url'] as String? ?? '');
        case 'checkCall':
          return core.checkCall(a['number'] as String?, marked: a['marked'] == true);
        case 'checkApp':
          return core.checkApp(a);
        case 'checkImage':
          final bytes = a['bytes'] as Uint8List?;
          if (bytes == null) return null;
          final qr = await compute(_qrIn, bytes);
          if (qr == null) return {'qr': null};
          return {'qr': qr, 'site': await core.checkSite(qr)};
      }
    } catch (_) {}
    return null;
  });
  await channel.invokeMethod('ready');
}

String? _qrIn(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  return image == null ? null : decodeQr(image);
}

(bool, bool) _knownSite(String url) {
  if (!intel.loaded) return (false, false);
  final r = intel.quickCheck(url);
  return (r.found, r.demo);
}

(bool, bool) _knownNumber(String number) {
  if (!intel.loaded) return (false, false);
  final e = intel.graph.nodes['phone:${phoneKey(number)}'];
  if (e == null || e.source == IntelSource.seen) return (false, false);
  return (true, e.synthetic);
}
