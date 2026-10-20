import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../engine/models.dart';

/// What an Android app file says about itself in its manifest.
class ApkInfo {
  final String? packageName;
  final String? label;
  final List<String> permissions;
  final List<String> services;
  const ApkInfo({this.packageName, this.label, this.permissions = const [], this.services = const []});
}

/// Risky permissions, with what they let an app do in plain words.
const riskyPermissions = <String, (String, int)>{
  'android.permission.READ_SMS': ('read your SMS, including bank codes', 25),
  'android.permission.RECEIVE_SMS': ('see SMS as they arrive, including bank codes', 25),
  'android.permission.SEND_SMS': ('send SMS from your phone', 10),
  'android.permission.BIND_ACCESSIBILITY_SERVICE': ('see your screen and tap buttons for you', 25),
  'android.permission.SYSTEM_ALERT_WINDOW': ('draw fake screens over your banking app', 15),
  'android.permission.REQUEST_INSTALL_PACKAGES': ('install more apps', 12),
  'android.permission.BIND_NOTIFICATION_LISTENER_SERVICE': ('read all your notifications, including bank codes', 20),
  'android.permission.READ_CONTACTS': ('read your contacts', 8),
  'android.permission.CALL_PHONE': ('make phone calls', 8),
  'android.permission.READ_CALL_LOG': ('read your call history', 8),
  'android.permission.ANSWER_PHONE_CALLS': ('answer or block your calls', 10),
  'android.permission.BIND_DEVICE_ADMIN': ('stop you from removing it', 15),
  'android.permission.QUERY_ALL_PACKAGES': ('see which banking apps you have', 6),
};

/// Unzips an APK and reads its binary manifest. Throws [FormatException] if
/// the file is not a readable APK.
ApkInfo readApk(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final entry = zip.findFile('AndroidManifest.xml');
  if (entry == null) throw const FormatException('No AndroidManifest.xml inside');
  return parseManifest(Uint8List.fromList(entry.content));
}

/// Parses Android's binary XML (AXML) manifest.
ApkInfo parseManifest(Uint8List data) {
  final b = ByteData.sublistView(data);
  if (data.length < 8 || b.getUint16(0, Endian.little) != 0x0003) throw const FormatException('Not a binary manifest');
  var strings = <String>[];
  var resIds = <int>[];
  String? pkg, label;
  final perms = <String>{};
  final services = <String>[];
  var off = b.getUint16(2, Endian.little);
  while (off + 8 <= data.length) {
    final type = b.getUint16(off, Endian.little);
    final headerSize = b.getUint16(off + 2, Endian.little);
    final size = b.getUint32(off + 4, Endian.little);
    if (size < 8 || off + size > data.length) break;
    if (type == 0x0001) {
      strings = _stringPool(b, off);
    } else if (type == 0x0180) {
      resIds = [for (var i = off + headerSize; i + 4 <= off + size; i += 4) b.getUint32(i, Endian.little)];
    } else if (type == 0x0102) {
      final name = _str(strings, b.getUint32(off + 20, Endian.little));
      final attrStart = b.getUint16(off + 24, Endian.little);
      final attrSize = b.getUint16(off + 26, Endian.little);
      final count = b.getUint16(off + 28, Endian.little);
      final attrs = <String, String>{};
      for (var i = 0; i < count; i++) {
        final a = off + 16 + attrStart + i * attrSize;
        if (a + 20 > data.length) break;
        final nameIdx = b.getUint32(a + 4, Endian.little);
        var attrName = _str(strings, nameIdx);
        // Obfuscated APKs blank the attribute names; fall back to resource ids.
        if (attrName.isEmpty && nameIdx < resIds.length) {
          attrName = switch (resIds[nameIdx]) { 0x01010003 => 'name', 0x01010006 => 'permission', 0x01010001 => 'label', _ => '' };
        }
        final raw = b.getUint32(a + 8, Endian.little);
        final dataType = data[a + 15];
        final value = b.getUint32(a + 16, Endian.little);
        attrs[attrName] = raw != 0xFFFFFFFF ? _str(strings, raw) : (dataType == 0x03 ? _str(strings, value) : '0x${value.toRadixString(16)}');
      }
      switch (name) {
        case 'manifest':
          pkg = attrs['package'];
        case 'application':
          final l = attrs['label'];
          if (l != null && !l.startsWith('0x')) label = l;
        case 'uses-permission' || 'uses-permission-sdk-23':
          if (attrs['name'] != null) perms.add(attrs['name']!);
        case 'service' || 'receiver' || 'activity':
          final p = attrs['permission'];
          if (p != null && p.startsWith('android.permission.')) {
            perms.add(p);
            services.add(attrs['name'] ?? name);
          }
      }
    }
    off += size;
  }
  return ApkInfo(packageName: pkg, label: label, permissions: perms.toList(), services: services);
}

String _str(List<String> s, int i) => i < s.length ? s[i] : '';

List<String> _stringPool(ByteData b, int off) {
  final count = b.getUint32(off + 8, Endian.little);
  final flags = b.getUint32(off + 16, Endian.little);
  final stringsStart = b.getUint32(off + 20, Endian.little);
  final headerSize = b.getUint16(off + 2, Endian.little);
  final utf8Pool = flags & 0x100 != 0;
  final out = <String>[];
  for (var i = 0; i < count; i++) {
    final at = off + stringsStart + b.getUint32(off + headerSize + i * 4, Endian.little);
    try {
      if (utf8Pool) {
        var p = at;
        if (b.getUint8(p) & 0x80 != 0) p++;
        p++;
        var len = b.getUint8(p);
        if (len & 0x80 != 0) {
          len = ((len & 0x7F) << 8) | b.getUint8(p + 1);
          p++;
        }
        p++;
        out.add(utf8.decode(b.buffer.asUint8List(b.offsetInBytes + p, len), allowMalformed: true));
      } else {
        var p = at;
        var len = b.getUint16(p, Endian.little);
        if (len & 0x8000 != 0) {
          len = ((len & 0x7FFF) << 16) | b.getUint16(p + 2, Endian.little);
          p += 2;
        }
        p += 2;
        out.add(String.fromCharCodes([for (var j = 0; j < len; j++) b.getUint16(p + j * 2, Endian.little)]));
      }
    } catch (_) {
      out.add('');
    }
  }
  return out;
}

const apkWarning = "Don't install this. Apps sent over WhatsApp that ask to read your SMS are used to steal bank codes.";

/// Findings for an app file: any APK sent by message is a risk, and risky
/// permissions make it a strong one.
List<Finding> apkFindings(ApkInfo info, {String fileName = 'this app'}) {
  final risky = info.permissions.where(riskyPermissions.containsKey).toList()
    ..sort((a, b) => riskyPermissions[b]!.$2.compareTo(riskyPermissions[a]!.$2));
  final out = <Finding>[
    Finding(
      category: CueCategory.file,
      title: 'App file from outside the Play Store',
      explanation: 'Real banks, couriers and agencies never send app files by message. Install apps only from the Play Store.',
      weight: 12,
      tool: 'App file check',
    ),
  ];
  if (risky.isNotEmpty) {
    var total = risky.fold<int>(0, (a, p) => a + riskyPermissions[p]!.$2);
    // Reading SMS or notifications, or controlling the screen, is how
    // banking malware steals codes, so a sideloaded app with these is decisive.
    final stealsCodes = risky.any((p) => p.contains('SMS') || p.contains('NOTIFICATION_LISTENER') || p.contains('ACCESSIBILITY'));
    total = stealsCodes ? (total + 20 < 55 ? 55 : total + 20) : total;
    out.add(Finding(
      category: CueCategory.file,
      title: 'Asks for dangerous phone permissions',
      explanation: 'This app wants to ${risky.take(4).map((p) => riskyPermissions[p]!.$1).join('; ')}. $apkWarning',
      weight: total.clamp(10, 75),
      tool: 'App file check',
    ));
  }
  return out;
}

/// A short readable summary used as the artefact text for an app file.
String apkSummary(ApkInfo info, String fileName) => [
      'Android app file: $fileName',
      if (info.label != null) 'App name: ${info.label}',
      if (info.packageName != null) 'Package: ${info.packageName}',
      'Permissions: ${info.permissions.isEmpty ? 'none' : info.permissions.map((p) => p.split('.').last).join(', ')}',
    ].join('\n');
