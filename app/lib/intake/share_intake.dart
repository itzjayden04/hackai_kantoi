import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Something shared to Kantoi from another app ("Share to Kantoi").
class SharedItem {
  final String? text;
  final Uint8List? bytes;
  final String? name;
  final String? mime;
  const SharedItem({this.text, this.bytes, this.name, this.mime});

  bool get isEmpty => (text == null || text!.trim().isEmpty) && bytes == null;

  static SharedItem? fromMap(Object? m) {
    if (m is! Map) return null;
    final subject = m['subject'] as String?;
    final text = m['text'] as String?;
    final item = SharedItem(
      text: [subject, text].whereType<String>().where((s) => s.trim().isNotEmpty).toSet().join('\n'),
      bytes: m['bytes'] as Uint8List?,
      name: m['name'] as String?,
      mime: m['mime'] as String?,
    );
    return item.isEmpty ? null : item;
  }
}

const _channel = MethodChannel('kantoi/share');

/// The latest shared item, waiting for the Check tab to pick it up.
final pendingShare = ValueNotifier<SharedItem?>(null);

/// Listens for items shared from WhatsApp, SMS or the gallery (Android only).
/// [onShare] lets the shell switch to the Check tab.
Future<void> listenForShares(VoidCallback onShare) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method != 'shared') return;
    final item = SharedItem.fromMap(call.arguments);
    if (item == null) return;
    pendingShare.value = item;
    onShare();
  });
  try {
    final item = SharedItem.fromMap(await _channel.invokeMethod('initial'));
    if (item != null) {
      pendingShare.value = item;
      onShare();
    }
  } catch (_) {}
}
