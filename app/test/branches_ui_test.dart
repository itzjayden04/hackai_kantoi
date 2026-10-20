import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/engine/cases.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/report.dart';
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
    final inv = (await t.runAsync(() => investigate('Transfer RM500 to Maybank account 5642 1234 5678 today only',
        options: const InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false))))!;
    await t.pumpWidget(wrap(const RelationshipPage()));
    expect(find.text('Can I trust this person?'), findsOneWidget);
    await t.pumpWidget(MaterialApp(home: ReportPage(inv: inv, initial: Situation.lostMoney)));
    expect(find.textContaining('Evidence screenshots'), findsOneWidget);
    expect(find.text('Incident sheet'), findsOneWidget);
    expect(find.text('FOR POLICE'), findsOneWidget);
    await t.tap(find.text('MCMC'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('FOR MCMC'), findsOneWidget);
    expect(find.text('Copy all'), findsOneWidget);
    // Masking can be switched off.
    await t.tap(find.byType(Switch).first);
    await t.pump(const Duration(milliseconds: 600));
    expect(t.widget<Switch>(find.byType(Switch).first).value, isFalse);
    await t.pumpWidget(MaterialApp(home: ReportPage(key: UniqueKey(), initial: Situation.lostMoney)));
    expect(find.text('Their number, profile or link'), findsOneWidget);
    await t.pumpWidget(MaterialApp(home: EmergencyPage(inv: inv)));
    await t.pumpAndSettle();
    expect(find.text('Call 997 now'), findsOneWidget);
    expect(find.text('What to do right now'), findsOneWidget);
    expect(find.text('0 OF ${caseSteps.length} DONE'), findsOneWidget);
    await t.tap(find.text('Keep the evidence'));
    await t.pumpAndSettle();
    expect(find.text('1 OF ${caseSteps.length} DONE'), findsOneWidget);
    expect(find.text('Bank fraud lines'), findsOneWidget);
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

  testWidgets('emergency and report fit a small phone', (t) async {
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final inv = (await t.runAsync(() => investigate('Transfer RM500 to Maybank account 5642 1234 5678 today only',
        options: const InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false))))!;
    for (final w in <Widget>[
      const Scaffold(body: EmergencyPage(embedded: true)),
      EmergencyPage(inv: inv),
      ReportPage(inv: inv, initial: Situation.lostMoney),
      const ReportPage(),
      const Scaffold(body: SettingsPage()),
    ]) {
      await t.pumpWidget(MaterialApp(home: w));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull, reason: w.toStringShort());
    }
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
