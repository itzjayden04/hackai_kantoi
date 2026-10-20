import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/bridge/bridge.dart';

Future<(int, dynamic)> _post(String path, Map<String, dynamic>? body, {String origin = 'chrome-extension://abc'}) async {
  final c = HttpClient();
  final req = body == null
      ? await c.getUrl(Uri.parse('http://127.0.0.1:$bridgePort$path'))
      : await c.postUrl(Uri.parse('http://127.0.0.1:$bridgePort$path'));
  req.headers.set('Origin', origin);
  req.headers.contentType = ContentType.json;
  if (body != null) req.write(jsonEncode(body));
  final res = await req.close();
  final text = await utf8.decodeStream(res);
  c.close();
  return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
}

void main() {
  setUpAll(startBridge);

  test('web pages are refused', () async {
    final (code, _) = await _post('/health', null, origin: 'https://evil.example');
    expect(code, 403);
  });

  test('extension flow: health, conversation, check', () async {
    final (h, health) = await _post('/health', null);
    expect(h, 200);
    expect(health['app'], 'kantoi');

    final (c1, conv) = await _post('/conversation', {
      'chat': 'Amanda',
      'origin': 'wrongNumber',
      'messages': [
        {'sender': 'Amanda', 'text': 'Hi sorry, wrong number. But you seem nice, can we be friends?', 'fromMe': false},
        {'sender': 'Me', 'text': 'Sure', 'fromMe': true},
      ],
    });
    expect(c1, 200);
    expect(conv['conversation']['score'], isA<int>());

    final (c2, out) = await _post('/check', {
      'chat': 'Amanda',
      'sender': 'Amanda',
      'text': 'My uncle teaches crypto trading, guaranteed 30% profit weekly. Transfer RM5000 to start, dear.',
      'source': 'whatsapp',
    });
    expect(c2, 200);
    expect(out['message']['verdict']['level'], anyOf('suspicious', 'danger'));
    expect(out['conversation']['level'], isNot('safe'));
  });
}
