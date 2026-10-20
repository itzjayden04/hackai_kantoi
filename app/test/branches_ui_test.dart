import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/engine/cases.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/local_store.dart';
import 'package:kantoi/ui/case_tracker.dart';
import 'package:kantoi/ui/emergency_page.dart';
import 'package:kantoi/ui/limits_page.dart';
import 'package:kantoi/ui/relationship_page.dart';
import 'package:kantoi/ui/report_page.dart';
import 'package:kantoi/ui/result_view.dart';
import 'package:kantoi/ui/review_page.dart';
import 'package:kantoi/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localStore.load();
  });

  testWidgets('pages render', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 2400));
    final inv = await investigate('Transfer RM500 to Maybank account 5642 1234 5678 today only',
        options: const InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false));
    await t.pumpWidget(wrap(const RelationshipPage()));
    expect(find.text('Can I trust this person?'), findsOneWidget);
    await t.pumpWidget(MaterialApp(home: ReportPage(inv: inv)));
    expect(find.textContaining('Evidence screenshots'), findsOneWidget);
    await t.tap(find.text('I have checked it. Approve report'));
    await t.pump();
    expect(find.textContaining('Copy each answer'), findsWidgets);
    await t.pumpWidget(MaterialApp(home: EmergencyPage(inv: inv)));
    expect(find.textContaining('Call 997'), findsWidgets);
    await t.pumpWidget(wrap(SingleChildScrollView(child: ResultView(inv: inv))));
    expect(find.text('This was actually legit'), findsOneWidget);
    await t.tap(find.text('This was actually a scam'));
    await t.pumpAndSettle();
    expect(localStore.review.length, 1);
    await t.pumpWidget(const MaterialApp(home: ReviewQueuePage()));
    expect(find.text('Export as JSON'), findsOneWidget);
    await t.pumpWidget(const MaterialApp(home: LimitsPage()));
    expect(find.text('Kantoi does not detect'), findsOneWidget);
    await t.pumpWidget(wrap(const SettingsPage()));
    expect(find.text('Delete all my Kantoi data'), findsOneWidget);
  });

  testWidgets('reminder banner shows for an old open case', (t) async {
    final c = ScamCase(id: 'a', createdAt: DateTime.now().subtract(const Duration(hours: 5)), title: 'Love scam');
    await localStore.setStep(c, 'call997', true);
    await t.pumpWidget(wrap(const CaseReminderBanner()));
    expect(find.textContaining('Police report pending'), findsOneWidget);
    await t.tap(find.text('Remind me later'));
    await t.pump();
    expect(find.textContaining('Police report pending'), findsNothing);
  });
}
