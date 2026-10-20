import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What phone protection can do right now, from Android's own settings.
class GuardStatus {
  final bool supported;
  final bool enabled;
  final bool notifications;
  final bool overlay;
  final bool accessibility;
  final List<GuardAlert> recent;
  const GuardStatus({
    this.supported = false,
    this.enabled = false,
    this.notifications = false,
    this.overlay = false,
    this.accessibility = false,
    this.recent = const [],
  });

  bool get ready => enabled && notifications && overlay;
}

/// A warning phone protection showed on screen.
class GuardAlert {
  final String app;
  final String chat;
  final String level;
  final String label;
  final String headline;
  final String text;
  final List<String> reasons;
  final DateTime at;
  const GuardAlert(this.app, this.chat, this.level, this.label, this.headline, this.text, this.reasons, this.at);

  static GuardAlert? fromJson(Object? raw) {
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      return GuardAlert(
        j['app'] as String? ?? '',
        j['chat'] as String? ?? '',
        j['level'] as String? ?? 'suspicious',
        j['label'] as String? ?? '',
        j['headline'] as String? ?? '',
        j['text'] as String? ?? '',
        (j['reasons'] as List? ?? []).map((e) => '$e').toList(),
        DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
      );
    } catch (_) {
      return null;
    }
  }
}

const _channel = MethodChannel('kantoi/guard');

bool get guardSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<GuardStatus> guardStatus() async {
  if (!guardSupported) return const GuardStatus();
  try {
    final m = Map<String, dynamic>.from(await _channel.invokeMethod('status') as Map);
    return GuardStatus(
      supported: true,
      enabled: m['enabled'] == true,
      notifications: m['notifications'] == true,
      overlay: m['overlay'] == true,
      accessibility: m['accessibility'] == true,
      recent: (m['recent'] as List? ?? []).map(GuardAlert.fromJson).whereType<GuardAlert>().toList(),
    );
  } catch (_) {
    return const GuardStatus(supported: true);
  }
}

/// Opens the Android settings screen for one permission:
/// 'notifications', 'overlay' or 'accessibility'.
Future<void> openGuardSetting(String which) async {
  try {
    await _channel.invokeMethod('open', which);
  } catch (_) {}
}

Future<void> setGuardEnabled(bool on) async {
  try {
    await _channel.invokeMethod('enable', on);
  } catch (_) {}
}

/// Shows a sample pause card so the user sees what it looks like.
Future<void> previewPauseCard() async {
  try {
    await _channel.invokeMethod('preview');
  } catch (_) {}
}

Future<void> clearGuardAlerts() async {
  try {
    await _channel.invokeMethod('clear');
  } catch (_) {}
}
