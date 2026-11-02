import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/auth/account.dart';
import 'package:kantoi/auth/auth_service.dart';
import 'package:kantoi/main.dart';
import 'package:kantoi/ui/auth/auth_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('logging out returns to the login screen even when the app opened signed in', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.runAsync(() async {
      // Builds in tests have no email-code sender, so sign-up skips the code.
      await auth.registerWithoutCode(const Registration(
          fullName: 'Jay Tan', email: 'jay@example.com', username: 'jaytan', password: 'Str0ng!pass', agreed: true));
    });
    expect(auth.signedIn, isTrue);

    await t.runAsync(() async {
      await t.pumpWidget(const KantoiApp(loginRequired: true));
      await t.pump(const Duration(milliseconds: 500));
    });
    expect(find.byType(AuthFlow), findsNothing);

    await t.runAsync(() => auth.signOut());
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(AuthFlow), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
  });
}
