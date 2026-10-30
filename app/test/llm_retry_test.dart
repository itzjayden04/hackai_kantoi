import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kantoi/engine/llm.dart';

void main() {
  setUp(() => geminiRetryPause = Duration.zero);

  test('a busy Gemini is asked again, then the backup model answers', () async {
    final models = <String>[];
    final client = MockClient((r) async {
      final m = r.url.path.split('/').last.split(':').first;
      models.add(m);
      if (m == geminiBackupModel) return http.Response('{"ok":true}', 200);
      return http.Response('{"error":{"code":503,"status":"UNAVAILABLE"}}', 503);
    });
    final res = await postGemini(client, apiKey: 'k', model: 'gemini-flash-latest', body: '{}', timeout: const Duration(seconds: 5));
    expect(res.statusCode, 200);
    expect(models, ['gemini-flash-latest', 'gemini-flash-latest', geminiBackupModel]);
  });

  test('a quick recovery needs no backup, and other errors are not retried', () async {
    var calls = 0;
    final recovers = MockClient((r) async => ++calls == 1 ? http.Response('busy', 503) : http.Response('{}', 200));
    expect((await postGemini(recovers, apiKey: 'k', model: 'm', body: '{}', timeout: const Duration(seconds: 5))).statusCode, 200);
    expect(calls, 2);
    calls = 0;
    final badKey = MockClient((r) async {
      calls++;
      return http.Response('bad key', 400);
    });
    expect((await postGemini(badKey, apiKey: 'k', model: 'm', body: '{}', timeout: const Duration(seconds: 5))).statusCode, 400);
    expect(calls, 1);
  });

  test('a key out of quota hands over to the second key, then rests for an hour', () async {
    geminiBackupKey = 'k2';
    resetGeminiKeyRest();
    final keys = <String>[];
    final client = MockClient((r) async {
      final k = r.headers['x-goog-api-key']!;
      keys.add(k);
      return k == 'k1' ? http.Response('quota', 429) : http.Response('{}', 200);
    });
    final t = DateTime(2026, 10, 30, 12);
    Future<int> call(DateTime at) async =>
        (await postGemini(client, apiKey: 'k1', model: 'm', body: '{}', timeout: const Duration(seconds: 5), now: at)).statusCode;
    expect(await call(t), 200);
    expect(keys, ['k1', 'k2']);
    keys.clear();
    expect(await call(t.add(const Duration(minutes: 30))), 200);
    expect(keys, ['k2']);
    keys.clear();
    await call(t.add(const Duration(hours: 2)));
    expect(keys, ['k1', 'k2']);
    geminiBackupKey = '';
  });

  test('without a second key a quota error is returned as is', () async {
    geminiBackupKey = '';
    final client = MockClient((r) async => http.Response('quota', 429));
    expect((await postGemini(client, apiKey: 'k1', model: 'm', body: '{}', timeout: const Duration(seconds: 5))).statusCode, 429);
  });
}
