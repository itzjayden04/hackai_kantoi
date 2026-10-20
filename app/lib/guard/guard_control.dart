import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state.dart';

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

  /// Which guards are switched on, by [Guard.key].
  final Map<String, bool> guards;

  /// Counted on this phone: warnings, pages, calls, apps, photos.
  final Map<String, int> stats;

  /// When protection was last switched on.
  final DateTime? since;

  /// False on Android 9 and older, which can't screen calls.
  final bool callScreeningSupported;
  const GuardStatus({
    this.perms = const {},
    this.supported = false,
    this.enabled = false,
    this.notifications = false,
    this.overlay = false,
    this.accessibility = false,
    this.recent = const [],
    this.guards = const {},
    this.stats = const {},
    this.since,
    this.callScreeningSupported = true,
  });

  bool get ready => enabled && notifications && overlay && accessibility;

  bool has(String key) => perms[key] ?? false;

  bool guardOn(String key) => guards[key] ?? true;

  int stat(String key) => stats[key] ?? 0;

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
  SetupItem('callScreening', 'Check who is calling', 'Choose Kantoi as your "caller ID & spam" app. Kantoi only sees the number, never the call itself.', Icons.phone_in_talk_outlined),
  SetupItem('photos', 'Check new screenshots and photos', 'Looks for QR codes with scam links in new pictures. Pictures stay on your phone.', Icons.qr_code_scanner_rounded),
  SetupItem('battery', 'Keep running in the background', 'Stops the phone from switching Kantoi off to save battery.', Icons.battery_charging_full_rounded),
];

/// One kind of auto-protection the user can switch on or off in the
/// Protection centre. [needs] is the [SetupItem.key] it can't work without.
class Guard {
  final String key;
  final String title;
  final String what;
  final IconData icon;
  final String? needs;

  /// The [GuardStatus.stats] counter shown on its row, and its unit.
  final String stat;
  final String unit;
  const Guard(this.key, this.title, this.what, this.icon, this.needs, this.stat, this.unit);
}

const guards = [
  Guard('calls', 'Calls', 'Warns you while a scam number is ringing. Kantoi sees the number only, never the call.', Icons.phone_in_talk_outlined,
      'callScreening', 'calls', 'flagged'),
  Guard('messages', 'Messages', 'Checks new SMS, WhatsApp, Telegram and email messages as they arrive.', Icons.sms_outlined, 'notifications',
      'messages', 'flagged'),
  Guard('chats', 'Chats on screen', 'Shows a small risk badge on WhatsApp, Telegram and Messenger chats, and pauses you before paying.',
      Icons.forum_outlined, 'accessibility', 'chats', 'flagged'),
  Guard('web', 'Web & link blocker', 'Closes scam websites in Chrome, Samsung Internet, Firefox, Edge, Opera and Brave.', Icons.language_rounded,
      'accessibility', 'pages', 'blocked'),
  Guard('apps', 'New apps', 'Checks every new app for scam signs, like reading your SMS codes.', Icons.install_mobile_outlined, null, 'apps',
      'checked'),
  Guard('photos', 'Pictures & QR codes', 'Looks for scam links in QR codes in new screenshots and photos.', Icons.qr_code_scanner_rounded, 'photos',
      'photos', 'flagged'),
];

/// A warning phone protection showed on screen.
class GuardAlert {
  /// message, chat, call, site, app or photo.
  final String kind;

  /// What to check in full: the message, link, number or app name.
  final String target;
  final String app;
  final String chat;
  final String level;
  final String label;
  final String headline;
  final String text;
  final List<String> reasons;
  final DateTime at;
  const GuardAlert(this.app, this.chat, this.level, this.label, this.headline, this.text, this.reasons, this.at,
      {this.kind = 'message', this.target = ''});

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
        kind: j['kind'] as String? ?? 'message',
        target: j['target'] as String? ?? j['text'] as String? ?? '',
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
  listenForGuardTaps();
  try {
    final m = Map<String, dynamic>.from(await _channel.invokeMethod('status') as Map);
    // A warning notification tapped while Kantoi was closed.
    final tapped = m['openTrace'];
    if (tapped is String && tapped.isNotEmpty) appState.openTrace(tapped);
    final since = (m['since'] as num?)?.toInt() ?? 0;
    return GuardStatus(
      guards: {for (final e in (m['guards'] as Map? ?? {}).entries) '${e.key}': e.value == true},
      stats: {for (final e in (m['stats'] as Map? ?? {}).entries) '${e.key}': (e.value as num?)?.toInt() ?? 0},
      since: since > 0 ? DateTime.fromMillisecondsSinceEpoch(since) : null,
      callScreeningSupported: m['callScreeningSupported'] != false,
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

/// Shows a sample warning so the user sees what it looks like: 'pause',
/// 'call', 'site' or 'badge'.
Future<void> previewWarning([String kind = 'pause']) async {
  try {
    await _channel.invokeMethod('preview', kind);
  } catch (_) {}
}

/// Switches one guard (a [Guard.key]) on or off. Android's services read it.
Future<void> setGuard(String key, bool on) async {
  try {
    await _channel.invokeMethod('setGuard', {'key': key, 'on': on});
  } catch (_) {}
}

var _listening = false;

/// Tapping a warning notification opens that link, number or message in the
/// Trace tab. Installed by the first [guardStatus] call.
void listenForGuardTaps() {
  if (_listening || !guardSupported) return;
  _listening = true;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'openTrace' && call.arguments is String && (call.arguments as String).isNotEmpty) {
      appState.openTrace(call.arguments as String);
    }
    return null;
  });
}

Future<void> clearGuardAlerts() async {
  try {
    await _channel.invokeMethod('clear');
  } catch (_) {}
}
