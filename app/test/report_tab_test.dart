import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/main.dart';
import 'package:kantoi/report/report_store.dart';
import 'package:kantoi/report/scam_report.dart';
import 'package:kantoi/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('report a fake shop from the Report tab in a few taps', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      await t.pumpWidget(const KantoiApp());
      await t.pump(const Duration(milliseconds: 500));
    });
    expect(find.byTooltip('Report'), findsOneWidget, reason: 'five tabs');
    appState.tab.value = tabReport;
    await t.pumpAndSettle();
    expect(find.text('Report a scam'), findsOneWidget);

    await t.tap(find.text('Shopping & deals'));
    await t.pumpAndSettle();
    await t.tap(find.text('Fake online store'));
    await t.pumpAndSettle();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.textContaining('STEP 1 OF 4'), findsOneWidget);

    await t.tap(find.text('In-app chat'));
    await t.ensureVisible(find.widgetWithText(TextField, 'https://…'));
    await t.enterText(find.widgetWithText(TextField, 'https://…'), 'http://cheap-iphone.top');
    await t.tap(find.byTooltip('Add').last);
    await t.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
    }
    expect(find.textContaining('STEP 3 OF 4'), findsOneWidget);
    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, '0.00'), '1299');
    await t.ensureVisible(find.text('Bank transfer'));
    await t.pumpAndSettle();
    await t.tap(find.text('Bank transfer'));
    await t.pumpAndSettle();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.tap(find.text('Review'));
    await t.pumpAndSettle();
    expect(find.text('Review your report'), findsOneWidget);
    expect(find.text('Yes · RM 1,299.00'), findsOneWidget);
    expect(find.text('Bank transfer'), findsOneWidget, reason: 'payment method shows on review');

    await t.ensureVisible(find.text('Submit report'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.text('Submit report'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pumpAndSettle();
    expect(find.text('Report sent'), findsOneWidget);
    final r = reportStore.reports.first;
    expect(r.kind, 'commerce.fake_store');
    expect(r.status, ReportStatus.sent);
    expect(r.sharedPayload()['domains'], ['cheap-iphone.top']);
  });
}
