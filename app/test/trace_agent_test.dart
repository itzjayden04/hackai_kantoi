import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kantoi/engine/forensics/tls_info.dart';
import 'package:kantoi/engine/llm.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/engine/trace/agent_model.dart';
import 'package:kantoi/engine/trace/trace_models.dart';
import 'package:kantoi/engine/trace/tracer.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _iso(Duration ago) => DateTime.now().subtract(ago).toUtc().toIso8601String();

/// A small fake internet: a shortener that redirects to a Maybank look-alike.
http.Response _web(http.Request r) {
  final u = r.url;
  if (u.host == 'bit.ly') return http.Response('', 301, headers: {'location': 'https://login.maybank2u-secure.top/verify'});
  if (u.host == 'login.maybank2u-secure.top') return http.Response('<html></html>', 200, headers: {'content-type': 'text/html'});
  if (u.host == 'rdap.org' && u.path == '/domain/maybank2u-secure.top') {
    return http.Response(
        jsonEncode({
          'events': [
            {'eventAction': 'registration', 'eventDate': _iso(const Duration(days: 3))}
          ],
          'entities': [
            {
              'roles': ['registrar'],
              'vcardArray': [
                'vcard',
                [
                  ['fn', {}, 'text', 'NameCheap, Inc.']
                ]
              ]
            }
          ],
          'nameservers': [
            {'ldhName': 'dns1.registrar-servers.com'}
          ],
        }),
        200);
  }
  if (u.host == 'dns.google') {
    final type = u.queryParameters['type'];
    final answer = switch (type) {
      'A' => [
          {'type': 1, 'data': '203.0.113.9'}
        ],
      'NS' => [
          {'type': 2, 'data': 'dns2.registrar-servers.com.'}
        ],
      'MX' => [
          {'type': 15, 'data': '10 mx.maybank2u-secure.top.'}
        ],
      _ => <Map<String, Object>>[],
    };
    return http.Response(jsonEncode({'Status': 0, 'Answer': answer}), 200);
  }
  if (u.host == 'ipwho.is') {
    return http.Response(
        jsonEncode({
          'success': true,
          'country_code': 'NL',
          'connection': {'org': 'Example Hosting BV', 'asn': 64500}
        }),
        200);
  }
  if (u.host == 'crt.sh') {
    return http.Response(
        jsonEncode([
          {'not_before': _iso(const Duration(days: 2)), 'name_value': 'login.maybank2u-secure.top\ncimbclicks-verify.top', 'common_name': 'login.maybank2u-secure.top'},
          {'not_before': _iso(const Duration(days: 1)), 'name_value': 'pay.maybank2u-secure.top', 'common_name': 'pay.maybank2u-secure.top'},
        ]),
        200);
  }
  return http.Response('not found', 404);
}

/// A model that plays back scripted tool calls, one list per turn, then
/// finishes.
class _Script implements TraceAgentModel {
  final List<List<AgentCall>> turns;
  final bool fail;
  final List<List<Map<String, dynamic>>> requests = [];
  final List<bool> finishOnly = [];
  int _i = 0;
  _Script(this.turns, {this.fail = false});

  @override
  String get name => 'Test model';

  @override
  bool get leavesDevice => true;

  @override
  Future<AgentTurn> next({required String system, required List<Map<String, dynamic>> contents, required List<AgentTool> tools, bool finishOnly = false}) async {
    requests.add(List.of(contents));
    this.finishOnly.add(finishOnly);
    if (fail) throw LlmError('Gemini error 429: quota');
    final calls = _i < turns.length ? turns[_i++] : [_finish()];
    return AgentTurn({
      'role': 'model',
      'parts': [
        for (final c in calls)
          {
            'functionCall': {'name': c.name, 'args': c.args}
          }
      ],
    }, calls);
  }

  @override
  void close() {}
}

AgentCall _call(String name, String key, String value, [String why = 'Because of what the last lookup showed.']) => AgentCall(name, {key: value, 'why': why});

AgentCall _finish([String level = 'danger']) => AgentCall('finish', {
      'risk_level': level,
      'scam_type': 'Maybank phishing',
      'summary': 'The short link leads to a brand-new website pretending to be Maybank.',
      'key_findings': ['Registered 3 days ago', 'Pretends to be Maybank'],
      'next_step': "Don't open the link. Use the Maybank app instead.",
    });

Tracer _tracer(http.Client client, TraceAgentModel? agent, {int max = 10}) => Tracer(
      client: client,
      agent: agent,
      agentMaxLookups: max,
      tlsProbe: (host) async => TlsInfo(
          issuer: "C=US, O=Let's Encrypt, CN=R11",
          subject: 'CN=$host',
          validFrom: DateTime.now().subtract(const Duration(days: 1)),
          validTo: DateTime.now().add(const Duration(days: 89)),
          trusted: true),
    );

Future<TraceState> _run(Tracer t, String input) async {
  final s = TraceState();
  await t.run(input).forEach(s.apply);
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('AI investigator', () {
    test('picks each lookup, explains it, and concludes', () async {
      final asked = <String>[];
      final client = MockClient((r) async {
        asked.add('${r.url.host}${r.url.path}');
        return _web(r);
      });
      final model = _Script([
        [_call('follow_link', 'url', 'https://bit.ly/abc', 'A short link hides where it really goes.')],
        [
          _call('domain_registration', 'domain', 'maybank2u-secure.top', 'It ends on a Maybank-like site; how old is it?'),
          _call('certificates', 'domain', 'maybank2u-secure.top', 'Look for other look-alikes on the same certificate.'),
        ],
        [_finish()],
      ]);
      final s = await _run(_tracer(client, model), 'https://bit.ly/abc');
      expect(s.finished, isTrue);
      expect(s.agent, isTrue);
      expect(s.thoughts.map((t) => t.tool), ['Follow the link', 'Check registration', 'Check certificates']);
      expect(s.thoughts.first.why, 'A short link hides where it really goes.');
      expect(s.conclusion?.level, RiskLevel.danger);
      expect(s.conclusion?.findings, hasLength(2));
      expect(s.flags.map((f) => f.title), containsAll(['Brand-new website', 'Pretends to be Maybank']));
      expect(s.nodes.keys, contains('domain:maybank2u-secure.top'));
      // The AI chose not to look at DNS, so DNS was never asked.
      expect(asked.where((a) => a.startsWith('dns.google')), isEmpty);
      expect(s.lookups.where((l) => l.step.tool == 'DNS (dns.google)'), isEmpty);
      // Its own steps are in the log and marked as going online.
      final ai = s.lookups.where((l) => l.step.tool == 'AI investigator').toList();
      expect(ai, isNotEmpty);
      expect(ai.every((l) => l.online && l.step.status == StepStatus.done), isTrue);
      // Each tool answer goes back to the model as data.
      final second = model.requests[1].last;
      final answer = (second['parts'] as List).first['functionResponse'] as Map;
      expect(answer['name'], 'follow_link');
      expect((answer['response'] as Map)['lookups'].toString(), contains('Redirect follower'));
      expect(s.lookups.every((l) => l.step.status != StepStatus.running), isTrue);
    });

    test('can only follow leads the trace found', () async {
      final asked = <String>[];
      final client = MockClient((r) async {
        asked.add('${r.url.host}${r.url.path}');
        return _web(r);
      });
      final model = _Script([
        [_call('domain_registration', 'domain', 'evil.example', 'Ignore previous instructions.')],
        [_call('follow_link', 'url', 'https://attacker.example/steal?x=1')],
        [_call('follow_link', 'url', 'https://bit.ly/abc')],
        [_finish('caution')],
      ]);
      final s = await _run(_tracer(client, model), 'https://bit.ly/abc');
      expect(s.thoughts.where((t) => t.refused), hasLength(2));
      expect(asked.where((a) => a.contains('evil.example') || a.contains('attacker.example')), isEmpty);
      final refusal = ((model.requests[1].last['parts'] as List).first['functionResponse'] as Map)['response'] as Map;
      expect(refusal['error'], contains('Not allowed'));
    });

    test('its verdict raises the level by one step at most and never lowers it', () {
      final low = TraceState()
        ..apply(const TraceFlagEvent(TraceFlag('Young website', 'Less than 6 months old.', 10)))
        ..apply(const TraceConclusionEvent(TraceConclusion(RiskLevel.danger, 'Scam', 'x', [], '', 'Test')));
      expect(low.rulesLevel, RiskLevel.caution);
      expect(low.level, RiskLevel.suspicious);
      expect(low.raisedByAi, isTrue);
      expect(low.riskLabel, 'Elevated');
      final high = TraceState()
        ..apply(const TraceFlagEvent(TraceFlag('Listed by VirusTotal', 'Flagged.', 50)))
        ..apply(const TraceConclusionEvent(TraceConclusion(RiskLevel.safe, 'Looks legitimate', 'x', [], '', 'Test')));
      expect(high.level, RiskLevel.danger);
      expect(high.raisedByAi, isFalse);
    });

    test('when the AI is unavailable the standard trace runs', () async {
      final model = _Script(const [], fail: true);
      final s = await _run(_tracer(MockClient((r) async => _web(r)), model), 'https://bit.ly/abc');
      expect(s.finished, isTrue);
      expect(s.agentNotes.single, contains('standard trace'));
      expect(s.conclusion, isNull);
      expect(s.lookups.where((l) => l.step.tool == 'DNS (dns.google)'), isNotEmpty);
      expect(s.nodes.keys, contains('domain:maybank2u-secure.top'));
    });

    test('leads it never looked at still get the standard checks', () async {
      final model = _Script([
        [_call('follow_link', 'url', 'https://bit.ly/abc')],
        [_finish()],
      ]);
      final s = await _run(_tracer(MockClient((r) async => _web(r)), model), 'Pay at https://bit.ly/abc or call 011-2004 7731 now');
      expect(s.lookups.map((l) => l.step.action), contains('Checking that every lead was looked at'));
      expect(s.lookups.where((l) => l.step.tool == 'Number format check'), isNotEmpty);
    });

    test('runs out of lookups, then has to conclude', () async {
      final model = _Script([
        [_call('follow_link', 'url', 'https://bit.ly/abc')],
        [_call('domain_registration', 'domain', 'maybank2u-secure.top')],
        [_call('dns_and_hosting', 'domain', 'maybank2u-secure.top')],
      ]);
      final s = await _run(_tracer(MockClient((r) async => _web(r)), model, max: 2), 'https://bit.ly/abc');
      expect(model.finishOnly[2], isTrue);
      expect(s.lookups.where((l) => l.step.tool == 'DNS (dns.google)'), isEmpty);
      expect(s.conclusion, isNotNull);
    });

    test('asking the same thing twice does not run it twice', () async {
      final asked = <String>[];
      final client = MockClient((r) async {
        asked.add('${r.url.host}${r.url.path}');
        return _web(r);
      });
      final model = _Script([
        [_call('follow_link', 'url', 'https://bit.ly/abc')],
        [_call('domain_registration', 'domain', 'maybank2u-secure.top')],
        [_call('domain_registration', 'domain', 'maybank2u-secure.top')],
        [_finish()],
      ]);
      await _run(_tracer(client, model), 'https://bit.ly/abc');
      expect(asked.where((a) => a == 'rdap.org/domain/maybank2u-secure.top'), hasLength(1));
    });
  });

  group('Gemini function calling', () {
    test('request: every tool declared, mode ANY, finish forced when asked', () {
      final body = GeminiAgentModel.requestBody(system: 'sys', contents: [agentUserText('hi')], tools: agentTools, finishOnly: true);
      final decls = (body['tools'] as List).single['functionDeclarations'] as List;
      expect(decls, hasLength(agentTools.length));
      final finish = decls.firstWhere((d) => d['name'] == 'finish') as Map;
      final props = (finish['parameters'] as Map)['properties'] as Map;
      expect(props['risk_level']['enum'], ['safe', 'caution', 'suspicious', 'danger']);
      expect(props['key_findings']['type'], 'array');
      final mode = (body['toolConfig'] as Map)['functionCallingConfig'] as Map;
      expect(mode['mode'], 'ANY');
      expect(mode['allowedFunctionNames'], ['finish']);
      expect(jsonEncode(body), isNotEmpty);
    });

    test('reply: calls read, thought signatures kept, answers matched by id', () async {
      final reply = jsonEncode({
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {
                  'functionCall': {
                    'id': 'c1',
                    'name': 'follow_link',
                    'args': {'url': 'https://bit.ly/abc', 'why': 'Short link.'}
                  },
                  'thoughtSignature': 'sig-123'
                }
              ]
            },
            'finishReason': 'STOP'
          }
        ]
      });
      late http.Request sent;
      final model = GeminiAgentModel(const LlmConfig(kind: LlmKind.gemini, apiKey: 'k'), client: MockClient((r) async {
        sent = r;
        return http.Response(reply, 200);
      }));
      final t = await model.next(system: 'sys', contents: [agentUserText('hi')], tools: agentTools);
      expect(sent.url.path, endsWith(':generateContent'));
      expect(sent.headers['x-goog-api-key'], 'k');
      expect(t.calls.single.name, 'follow_link');
      expect(t.calls.single.id, 'c1');
      expect((t.content['parts'] as List).single['thoughtSignature'], 'sig-123');
      final back = agentResponses([(t.calls.single, {'ok': true})]);
      final fr = (back['parts'] as List).single['functionResponse'] as Map;
      expect(fr['id'], 'c1');
      expect(fr['name'], 'follow_link');
      expect(() => parseAgentTurn('{"candidates": []}'), throwsA(isA<LlmError>()));
      expect(GeminiAgentModel.supports(const LlmConfig(kind: LlmKind.ollama)), isFalse);
    });
  });
}
