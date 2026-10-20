import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What phone protection can do right now, from Android's own settings.
class GuardStatus {
  final bool supported;
  final bool enabled;
  final bool notifications;
  final bool overlay;
  final bool accessibility;
  final List<GuardAlert> recent;

  /// Every permission Android reports, by key (see [setupItems]).
  final Map<String, bool> perms;
  const GuardStatus({
    this.perms = const {},
    this.supported = false,
    this.enabled = false,
    this.notifications = false,
    this.overlay = false,
    this.accessibility = false,
    this.recent = const [],
  });

  bool get ready => enabled && notifications && overlay && accessibility;

  bool has(String key) => perms[key] ?? false;

  /// How many of the required setup steps are done.
  int get setupDone => setupItems.where((i) => has(i.key)).length;
  bool get setupComplete => setupItems.every((i) => has(i.key));
}

/// One permission the first-run setup walks the user through, in order.
class SetupItem {
  final String key;
  final String title;
  final String why;
  final IconData icon;
  const SetupItem(this.key, this.title, this.why, this.icon);
}

/// The permissions Kantoi asks for on first run, in the order it asks.
/// [GuardStatus.perms] reports each by [SetupItem.key]; [openGuardSetting]
/// opens the screen (or system pop-up) that grants it.
final setupItems = [
  SetupItem('postNotifications', 'Send you warnings', 'So Kantoi can tell you the moment something looks like a scam.', Icons.notifications_active_outlined),
  SetupItem('notifications', 'Read new messages', 'Checks new WhatsApp, Telegram, SMS and email messages as they arrive. Nothing leaves your phone.', Icons.forum_outlined),
  SetupItem('overlay', 'Show warnings on top', 'Lets Kantoi put a pause card over a chat, call or scam website.', Icons.layers_outlined),
  SetupItem('accessibility', 'Watch for scams on screen', 'Reads the chat or website you have open so Kantoi can warn you and close scam pages. Find "Kantoi" and switch it on.', Icons.accessibility_new_rounded),
  SetupItem('battery', 'Keep running in the background', 'Stops the phone from switching Kantoi off to save battery.', Icons.battery_charging_full_rounded),
];

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
      perms: {
        for (final e in m.entries)
          if (e.value is bool) e.key: e.value as bool,
      },
      recent: (m['recent'] as List? ?? []).map(GuardAlert.fromJson).whereType<GuardAlert>().toList(),
    );
  } catch (_) {
    return const GuardStatus(supported: true);
  }
}

/// Opens the Android settings screen (or pop-up) for one permission, by
/// its [SetupItem.key].
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
