import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/monitor/monitor.dart';

void main() {
  test('reads the phone snapshot, groups duplicate names and sums days', () {
    final s = MonitorSnapshot.fromMap({
      'today': '2026-10-30',
      'hide': true,
      'apps': [
        {'pkg': 'com.whatsapp', 'name': 'WhatsApp', 'coverage': 'full', 'group': 'Chat', 'installed': true, 'on': true,
          'days': {'2026-10-30': [10, 2], '2026-10-29': [5, 1]}},
        {'pkg': 'com.zhiliaoapp.musically', 'name': 'TikTok', 'coverage': 'preview', 'group': 'Social', 'installed': true, 'on': false, 'days': {}},
        {'pkg': 'com.ss.android.ugc.trill', 'name': 'TikTok', 'coverage': 'preview', 'group': 'Social', 'installed': false, 'on': true, 'days': {}},
        {'pkg': 'com.snapchat.android', 'name': 'Snapchat', 'coverage': 'sender', 'group': 'Social', 'installed': false, 'on': true, 'days': {}},
      ],
    });
    expect(s.installed.map((a) => a.name), ['WhatsApp', 'TikTok']);
    expect(s.notInstalled.map((a) => a.name), ['Snapchat']);
    expect(s.watching, 1);
    expect(s.alertsToday, 2);
    final week = s.lastDays(7);
    expect(week.length, 7);
    expect(week.last, ('2026-10-30', 10, 2));
    expect(week[5], ('2026-10-29', 5, 1));
    expect(s.installed.first.coverage, Coverage.full);
    expect(coverageLabel(Coverage.sender), 'Name only');
  });
}
