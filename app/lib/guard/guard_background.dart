import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../local_store.dart';
import '../state.dart';
import 'guard_core.dart';

/// Runs inside the background engine Android starts for phone protection.
Future<void> runGuardBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.load();
  await localStore.load();
  final core = GuardCore();
  const channel = MethodChannel('kantoi/guard_bg');
  channel.setMethodCallHandler((call) async {
    if (call.method != 'check') return null;
    final a = Map<String, dynamic>.from(call.arguments as Map);
    try {
      return await core.check(
        app: a['app'] as String? ?? '',
        chat: a['chat'] as String? ?? 'Unknown chat',
        sender: a['sender'] as String?,
        text: a['text'] as String? ?? '',
        incoming: a['incoming'] as bool? ?? true,
        ownDetails: appState.ownDetails,
      );
    } catch (_) {
      return null;
    }
  });
  await channel.invokeMethod('ready');
}
