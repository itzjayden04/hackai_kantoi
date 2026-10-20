import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/guard/guard_core.dart';

void main() {
  test('phone protection alerts once as a chat turns into a scam', () async {
    final g = GuardCore();
    final first = await g.check(app: 'com.whatsapp', chat: 'Amanda', text: 'Hi, is this Mr Tan? Sorry, wrong number!', network: false);
    expect(first!['alert'], isFalse);
    final pitch = await g.check(
        app: 'com.whatsapp',
        chat: 'Amanda',
        text: 'My uncle is a crypto trader. Guaranteed 30% profit every week. Dear, transfer RM5000 to account 5123456789012 today only',
        network: false);
    expect(pitch!['alert'], isTrue);
    expect(pitch['level'], anyOf('suspicious', 'danger'));
    expect((pitch['reasons'] as List), isNotEmpty);
    // The same message seen again (notification and open chat) is skipped.
    expect(await g.check(app: 'com.whatsapp', chat: 'Amanda', text: pitch['text'] as String, network: false), isNull);
  });

  test('ordinary messages never raise the pause card', () async {
    final g = GuardCore();
    for (final t in ['Bro jom futsal tonight at 9?', 'Mum says dinner at 7, bring the durian', 'Meeting moved to Thursday 3pm']) {
      final r = await g.check(app: 'com.whatsapp', chat: 'Ali', text: t, network: false);
      expect(r!['alert'], isFalse, reason: t);
    }
  });
}
