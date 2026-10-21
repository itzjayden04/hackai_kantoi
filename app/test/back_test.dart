import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/main.dart';
import 'package:kantoi/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Back leaves an inner step first, then returns to Check', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.runAsync(() async {
      await t.pumpWidget(const KantoiApp());
      await t.pump(const Duration(milliseconds: 500));
    });
    appState.tab.value = 2;
    await t.pump(const Duration(milliseconds: 500));

    var inner = true;
    appState.backHandlers[2] = () {
      final had = inner;
      inner = false;
      return had;
    };
    await t.binding.handlePopRoute();
    await t.pump();
    expect(appState.tab.value, 2, reason: 'the tab handles its own inner step first');

    await t.binding.handlePopRoute();
    await t.pump();
    expect(appState.tab.value, 0);

    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.text('Press back again to close Kantoi'), findsOneWidget);
    appState.backHandlers.remove(2);
    await t.pump(const Duration(seconds: 3));
  });
}
