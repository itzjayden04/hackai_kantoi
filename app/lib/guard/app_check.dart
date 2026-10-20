import '../engine/models.dart';
import '../engine/url_analyzer.dart' show brandKeywords;

/// Facts Android gives about a newly installed app.
class NewApp {
  final String name;
  final String package;

  /// Package name of the store or app that installed it, or null.
  final String? installer;
  final List<String> permissions;

  /// Asks to be an accessibility service (it could read and tap the screen).
  final bool accessibility;
  final bool notificationListener;
  final bool deviceAdmin;
  const NewApp({
    required this.name,
    required this.package,
    this.installer,
    this.permissions = const [],
    this.accessibility = false,
    this.notificationListener = false,
    this.deviceAdmin = false,
  });

  factory NewApp.fromMap(Map m) => NewApp(
        name: '${m['name'] ?? m['package'] ?? ''}',
        package: '${m['package'] ?? ''}',
        installer: m['installer'] as String?,
        permissions: [for (final p in (m['permissions'] as List? ?? [])) '$p'],
        accessibility: m['accessibility'] == true,
        notificationListener: m['notificationListener'] == true,
        deviceAdmin: m['deviceAdmin'] == true,
      );
}

/// App stores whose apps are reviewed before they are offered.
const appStores = {
  'com.android.vending', 'com.google.android.packageinstaller.ota', 'com.sec.android.app.samsungapps',
  'com.huawei.appmarket', 'com.xiaomi.market', 'com.xiaomi.mipicks', 'com.heytap.market', 'com.oppo.market',
  'com.bbk.appstore', 'com.vivo.appstore', 'com.amazon.venezia',
};

class AppVerdict {
  final String name;
  final RiskLevel level;
  final String headline;
  final List<String> reasons;
  const AppVerdict(this.name, this.level, this.headline, this.reasons);
  Map<String, dynamic> toJson() => {
        'name': name,
        'level': level.name,
        'label': riskLabel(level),
        'headline': headline,
        'reasons': reasons,
        'warn': level.index >= RiskLevel.suspicious.index,
      };
}

/// Scam apps ("APK" files sent over WhatsApp) are installed outside the app
/// store and then ask to read SMS codes or control the screen.
AppVerdict checkNewApp(NewApp a) {
  final reasons = <String>[];
  var score = 0;
  final sideloaded = a.installer == null || !appStores.contains(a.installer);
  if (sideloaded) {
    reasons.add('Installed from outside an app store');
    score += 10;
  }
  final p = a.permissions.map((e) => e.split('.').last).toSet();
  if (p.contains('RECEIVE_SMS') || p.contains('READ_SMS')) {
    reasons.add('Can read your SMS, including bank codes (TAC/OTP)');
    score += 18;
  }
  if (p.contains('SEND_SMS')) {
    reasons.add('Can send SMS from your phone');
    score += 6;
  }
  if (a.accessibility) {
    reasons.add('Asks to control your screen (accessibility)');
    score += 18;
  }
  if (a.notificationListener) {
    reasons.add('Asks to read all your notifications');
    score += 8;
  }
  if (a.deviceAdmin) {
    reasons.add('Asks to be a device admin, which makes it hard to remove');
    score += 10;
  }
  if (p.contains('SYSTEM_ALERT_WINDOW')) {
    reasons.add('Can draw over other apps');
    score += 4;
  }
  if (p.contains('REQUEST_INSTALL_PACKAGES')) {
    reasons.add('Can install other apps');
    score += 4;
  }
  final label = a.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final brand = brandKeywords.entries.where((e) => e.key.length >= 4 && label.contains(e.key)).map((e) => e.value).firstOrNull;
  if (brand != null && sideloaded) {
    reasons.add('Uses the name $brand but did not come from an app store');
    score += 20;
  }
  final level = score >= 36
      ? RiskLevel.danger
      : score >= 24
          ? RiskLevel.suspicious
          : score >= 6
              ? RiskLevel.caution
              : RiskLevel.safe;
  final headline = switch (level) {
    RiskLevel.danger => 'Scam apps look like this. Uninstall it unless you are sure where it came from.',
    RiskLevel.suspicious => 'This app asks for powerful access. Only keep it if you trust where it came from.',
    RiskLevel.caution => 'Installed from outside an app store. Nothing else looks risky.',
    RiskLevel.safe => 'Nothing risky found.',
  };
  return AppVerdict(a.name, level, headline, reasons.take(4).toList());
}
