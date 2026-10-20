import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/engine/investigator.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/local_store.dart';
import 'package:kantoi/state.dart';
import 'package:kantoi/ui/check/check_format.dart';
import 'package:kantoi/ui/check/check_widgets.dart';
import 'package:kantoi/ui/check/result_page.dart';
import 'package:kantoi/ui/check_page.dart';
import 'package:kantoi/ui/relationship_page.dart';
import 'package:kantoi/ui/result_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

const offline = InvestigateOptions(llm: LlmConfig(kind: LlmKind.none), network: false);
final parcel = samples[0].$3;
final tac = samples[1].$3;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localStore.load();
    appState.history.clear();
    appState.tab.value = 0;
    appState.traceRequest.value = null;
  });

  group('labels', () {
    test('the samples: parcel scam is flagged, the real bank TAC is judged safe', () async {
      final p = await investigate(parcel, options: offline);
      final b = await investigate(tac, options: offline);
      expect(p.verdict.level.index, greaterThanOrEqualTo(RiskLevel.suspicious.index));
      expect(b.verdict.level, RiskLevel.safe);
      expect(shortReason(b), isNot('No scam signs found'), reason: 'a genuine sign should be named');
    });

    test('trace target prefers a link, then a phone number, then the text', () async {
      final p = await investigate(parcel, options: offline);
      expect(traceTarget(p), contains('poslaju-my-redelivery.top'));
      final ph = await investigate('Call me back on 012-345 6789 about your loan approval', options: offline);
      expect(traceTarget(ph), contains('345'));
      final plain = await investigate('  Hello, are you free tomorrow?  ', options: offline);
      expect(traceTarget(plain), 'Hello, are you free tomorrow?');
    });

    test('time ago and confidence words', () {
      final now = DateTime(2026, 10, 20, 12);
      expect(timeAgo(now.subtract(const Duration(minutes: 14)), now), '14m ago');
      expect(timeAgo(now.subtract(const Duration(hours: 2)), now), '2h ago');
      expect(timeAgo(now.subtract(const Duration(hours: 30)), now), 'Yesterday');
      expect(confidenceWords(90), 'Fairly sure');
      expect(confidenceWords(40), 'Not very sure');
    });
  });

  group('screens', () {
    testWidgets('scam result: why, script, actions and Trace hands over the link', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 2400));
      final inv = (await t.runAsync(() => investigate(parcel, options: offline)))!;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ResultView(inv: inv)),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Why Kantoi flagged this'), findsOneWidget);
      expect(find.text('How sure Kantoi is'), findsOneWidget);
      expect(find.text('I already paid or shared details'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      // Details stay folded until asked for.
      expect(find.text('How Kantoi checked this'), findsOneWidget);
      expect(find.text('Nothing from this check left your phone.'), findsNothing);
      await t.ensureVisible(find.text('Your privacy'));
      await t.tap(find.text('Your privacy'));
      await t.pumpAndSettle();
      expect(find.text('Nothing from this check left your phone.'), findsOneWidget);
      await t.ensureVisible(find.text('Trace'));
      await t.tap(find.text('Trace'));
      await t.pump();
      expect(appState.tab.value, 1);
      expect(appState.traceRequest.value, contains('poslaju-my-redelivery.top'));
    });

    testWidgets('a genuine message gets a calm result and "Was this wrong?"', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 2400));
      final inv = (await t.runAsync(() => investigate(tac, options: offline)))!;
      await t.pumpWidget(MaterialApp(home: ResultPage(inv: inv)));
      await t.pumpAndSettle();
      expect(find.text('Looks safe'), findsWidgets);
      expect(find.text('Was this wrong?'), findsOneWidget);
      expect(find.text('Report'), findsNothing);
      await t.tap(find.text('This was actually a scam'));
      await t.pumpAndSettle();
      expect(localStore.review.length, 1);
    });

    testWidgets('check tab: intake, samples, recent checks and the person check', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 1600));
      appState.addHistory((await t.runAsync(() => investigate(parcel, options: offline)))!);
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: CheckPage())));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Is this a scam?'), findsOneWidget);
      expect(find.text('Check with Kantoi AI'), findsOneWidget);
      expect(find.text('Real bank TAC'), findsOneWidget);
      expect(find.byType(RecentCheckCard), findsOneWidget);
      // Nothing typed: a friendly hint, no check.
      await t.tap(find.text('Check with Kantoi AI'));
      await t.pump();
      expect(find.textContaining('Paste or type the message first'), findsOneWidget);
      await t.ensureVisible(find.text('Check a person or chat'));
      await t.tap(find.text('Check a person or chat'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(RelationshipScreen), findsOneWidget);
      expect(find.text('Can I trust this person?'), findsOneWidget);
    });

    testWidgets('a sample runs through the live pipeline into the result', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 1600));
      appState.llm = const LlmConfig(kind: LlmKind.none);
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: CheckPage())));
      await t.pump(const Duration(seconds: 1));
      await t.ensureVisible(find.text('Real bank TAC'));
      await t.tap(find.text('Real bank TAC'));
      await t.pump();
      expect(find.text('Kantoi is checking'), findsOneWidget);
      for (var i = 0; i < 50 && appState.history.isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
      }
      await t.pump(const Duration(seconds: 2));
      expect(appState.history.first.verdict.level, RiskLevel.safe);
      expect(find.text('Kantoi is checking'), findsNothing);
      expect(find.text('Was this wrong?'), findsOneWidget);
      expect(find.text('New check'), findsWidgets);
      await t.tap(find.text('New check').last);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Check with Kantoi AI'), findsOneWidget);
    });
  });
}
