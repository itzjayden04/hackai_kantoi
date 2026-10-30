import 'package:flutter/services.dart';

import '../guard/guard_control.dart';

/// How much of a message an app's notifications show Kantoi.
enum Coverage { full, preview, sender, email }

String coverageLabel(Coverage c) => switch (c) {
      Coverage.full => 'Full message',
      Coverage.preview => 'Preview',
      Coverage.sender => 'Name only',
      Coverage.email => 'Sender + subject',
    };

String coverageHelp(Coverage c) => switch (c) {
      Coverage.full => 'Kantoi sees the whole message in the alert and checks it.',
      Coverage.preview => 'The alert shows part of the message. Kantoi checks what it shows.',
      Coverage.sender => 'The alert only says who wrote. Kantoi cannot read the message.',
      Coverage.email => 'Kantoi checks the sender, subject and first lines.',
    };

/// One watched app as the Scam Monitor shows it.
class MonitoredApp {
  final String pkg;
  final String name;
  final Coverage coverage;
  final String group;
  final bool installed;
  final bool on;
  /// Day (yyyy-MM-dd) to [checked, alerts].
  final Map<String, (int, int)> days;
  const MonitoredApp(
      {required this.pkg, required this.name, required this.coverage, required this.group, this.installed = false, this.on = true, this.days = const {}});

  int alertsOn(String day) => days[day]?.$2 ?? 0;
  int checkedOn(String day) => days[day]?.$1 ?? 0;
  int get alerts => days.values.fold(0, (a, d) => a + d.$2);
  int get checked => days.values.fold(0, (a, d) => a + d.$1);

  factory MonitoredApp.fromMap(Map m) {
    final days = <String, (int, int)>{};
    (m['days'] as Map? ?? const {}).forEach((k, v) {
      final l = (v as List).cast<num>();
      days['$k'] = (l[0].toInt(), l[1].toInt());
    });
    return MonitoredApp(
      pkg: m['pkg'] as String,
      name: m['name'] as String? ?? m['pkg'] as String,
      coverage: Coverage.values.firstWhere((c) => c.name == m['coverage'], orElse: () => Coverage.preview),
      group: m['group'] as String? ?? 'Chat',
      installed: m['installed'] as bool? ?? false,
      on: m['on'] as bool? ?? true,
      days: days,
    );
  }
}

class MonitorSnapshot {
  final List<MonitoredApp> apps;
  final bool hideScams;
  final String today;
  const MonitorSnapshot(this.apps, this.hideScams, this.today);

  /// Installed apps first (one row per app name), then the rest.
  List<MonitoredApp> get installed {
    final seen = <String>{};
    return [for (final a in apps) if (a.installed && seen.add(a.name)) a];
  }

  List<MonitoredApp> get notInstalled {
    final have = installed.map((a) => a.name).toSet();
    final seen = <String>{};
    return [for (final a in apps) if (!a.installed && !have.contains(a.name) && seen.add(a.name)) a];
  }

  int get watching => installed.where((a) => a.on).length;
  int get alertsToday => installed.fold(0, (s, a) => s + a.alertsOn(today));

  /// The last [n] days, oldest first, with total checked and alerts per day.
  List<(String, int, int)> lastDays(int n) {
    final t = DateTime.parse(today);
    return [
      for (var i = n - 1; i >= 0; i--)
        () {
          final d = t.subtract(Duration(days: i));
          final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          return (k, apps.fold(0, (s, a) => s + a.checkedOn(k)), apps.fold(0, (s, a) => s + a.alertsOn(k)));
        }(),
    ];
  }

  static MonitorSnapshot fromMap(Map m) => MonitorSnapshot(
        [for (final a in (m['apps'] as List? ?? const [])) MonitoredApp.fromMap(a as Map)],
        m['hide'] as bool? ?? true,
        m['today'] as String? ?? DateTime.now().toIso8601String().substring(0, 10),
      );
}

const _channel = MethodChannel('kantoi/guard');

Future<MonitorSnapshot?> loadMonitor() async {
  if (!guardSupported) return null;
  try {
    final m = await _channel.invokeMethod<Map>('monitor');
    return m == null ? null : MonitorSnapshot.fromMap(m);
  } catch (_) {
    return null;
  }
}

Future<void> setAppMonitored(String pkg, bool on) async {
  try {
    await _channel.invokeMethod('setMonitor', {'pkg': pkg, 'on': on});
  } catch (_) {}
}

Future<void> setHideScams(bool on) async {
  try {
    await _channel.invokeMethod('setHideScams', on);
  } catch (_) {}
}

/// The alerts from one app, newest first, from the phone's recent warnings.
List<GuardAlert> alertsFor(GuardStatus s, String pkg) => [for (final a in s.recent) if (a.app == pkg) a];
