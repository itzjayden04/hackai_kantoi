import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kantoi/state.dart';
import 'package:kantoi/ui/intel_page.dart';
import 'package:kantoi/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget child) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: child));

http.Client _offline() => MockClient((r) async => throw const SocketException('offline'));

Future<void> _settleTrace(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('TRACE COMPLETE').evaluate().isNotEmpty) break;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('Trace tab runs a live trace offline and shows the HUD, map and feed', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const IntelPage(client: _offline, autoCrawl: false, probeCertificates: false)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('Start trace'), findsOneWidget);
    expect(find.text('Demo data'), findsWidgets);

    await tester.enterText(find.byKey(const ValueKey('trace-input')), 'https://maybank2u-secure.top/login');
    await tester.tap(find.text('Start trace'));
    await _settleTrace(tester);

    expect(find.text('Investigation canvas'), findsOneWidget);
    expect(find.text('TRACE COMPLETE'), findsOneWidget);
    expect(find.text('Investigation audit feed'), findsOneWidget);
    expect(find.textContaining('related entit'), findsOneWidget);

    await tester.ensureVisible(find.text('View full findings'));
    await tester.pump();
    await tester.tap(find.text('View full findings'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Full findings'), findsOneWidget);
    expect(find.text('Warning signs'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a trace request from elsewhere starts automatically', (tester) async {
    appState.traceRequest.value = '012-345 6789';
    await tester.pumpWidget(_app(const IntelPage(client: _offline, autoCrawl: false, probeCertificates: false)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(appState.traceRequest.value, isNull);
    await _settleTrace(tester);
    expect(find.text('TRACE COMPLETE'), findsOneWidget);
    expect(find.text('Check on Semak Mule'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });
}
