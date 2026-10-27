/// The model behind the Trace agent: Gemini with function calling. The agent
/// loop talks to it through [TraceAgentModel], so tests can script it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../llm.dart';

/// One tool the agent may call.
class AgentTool {
  final String name;
  final String description;

  /// Parameter name -> description. Every parameter is a required string,
  /// except those listed in [optional].
  final Map<String, String> params;
  final Set<String> optional;

  /// Allowed values for a parameter, when it is a fixed choice.
  final Map<String, List<String>> choices;

  /// Parameters that are lists of strings.
  final Set<String> lists;

  const AgentTool(this.name, this.description, this.params, {this.optional = const {}, this.choices = const {}, this.lists = const {}});

  /// Gemini's function declaration for this tool.
  Map<String, dynamic> toGemini() => {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': {
            for (final e in params.entries)
              e.key: lists.contains(e.key)
                  ? {
                      'type': 'array',
                      'items': {'type': 'string'},
                      'description': e.value,
                    }
                  : {
                      'type': 'string',
                      'description': e.value,
                      if (choices[e.key] != null) 'enum': choices[e.key],
                    },
          },
          'required': [for (final k in params.keys) if (!optional.contains(k)) k],
        },
      };
}

/// One function call the model asked for.
class AgentCall {
  final String name;
  final Map<String, dynamic> args;

  /// Gemini's call id, echoed back with the answer when present.
  final String? id;
  const AgentCall(this.name, this.args, {this.id});

  String arg(String k) => '${args[k] ?? ''}'.trim();
}

/// One reply from the model: what to add to the conversation (verbatim, so
/// Gemini's thought signatures go back with it) and the calls it made.
class AgentTurn {
  final Map<String, dynamic> content;
  final List<AgentCall> calls;
  final String text;
  const AgentTurn(this.content, this.calls, {this.text = ''});
}

abstract class TraceAgentModel {
  /// Shown in the activity log, e.g. "Gemini (gemini-flash-latest)".
  String get name;

  /// Whether text sent to the model leaves the phone.
  bool get leavesDevice;

  /// Asks for the next step. [finishOnly] forces a call to the finish tool.
  Future<AgentTurn> next({
    required String system,
    required List<Map<String, dynamic>> contents,
    required List<AgentTool> tools,
    bool finishOnly = false,
  });

  void close() {}
}

/// The first user message.
Map<String, dynamic> agentUserText(String text) => {
      'role': 'user',
      'parts': [
        {'text': text}
      ],
    };

/// The answers to the calls of one turn, in the order they were made.
Map<String, dynamic> agentResponses(List<(AgentCall, Map<String, dynamic>)> answers, {String? note}) => {
      'role': 'user',
      'parts': [
        for (final (c, r) in answers)
          {
            'functionResponse': {
              if (c.id != null) 'id': c.id,
              'name': c.name,
              'response': r,
            }
          },
        if (note != null) {'text': note},
      ],
    };

/// Reads a generateContent answer into a turn.
AgentTurn parseAgentTurn(String body) {
  final j = jsonDecode(body);
  if (j is! Map) throw LlmError('Gemini returned no answer');
  final cands = j['candidates'];
  if (cands is! List || cands.isEmpty) throw LlmError('Gemini returned no answer');
  final c = cands.first;
  if (c is! Map) throw LlmError('Gemini returned no answer');
  final content = c['content'];
  if (content is! Map) throw LlmError('Gemini stopped (${c['finishReason'] ?? 'no content'})');
  final parts = content['parts'];
  final calls = <AgentCall>[];
  final text = StringBuffer();
  if (parts is List) {
    for (final p in parts) {
      if (p is! Map) continue;
      final fc = p['functionCall'];
      if (fc is Map) {
        final args = fc['args'];
        calls.add(AgentCall('${fc['name'] ?? ''}', args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{},
            id: fc['id'] is String ? fc['id'] as String : null));
      } else if (p['text'] is String && p['thought'] != true) {
        text.write(p['text']);
      }
    }
  }
  final echo = Map<String, dynamic>.from(content);
  echo['role'] = 'model';
  return AgentTurn(echo, calls, text: text.toString().trim());
}

/// Gemini with function calling (generateContent, tools, mode ANY).
class GeminiAgentModel implements TraceAgentModel {
  final LlmConfig config;
  final http.Client _http;
  final Duration timeout;
  final bool _ownClient;

  GeminiAgentModel(this.config, {http.Client? client, this.timeout = const Duration(seconds: 30)})
      : _http = client ?? http.Client(),
        _ownClient = client == null;

  /// Only Gemini is wired up for the agent; other providers use the standard trace.
  static bool supports(LlmConfig c) => c.kind == LlmKind.gemini && c.apiKey.isNotEmpty;

  String get _model => config.model.isEmpty ? 'gemini-flash-latest' : config.model;

  @override
  String get name => 'Gemini ($_model)';

  @override
  bool get leavesDevice => true;

  /// The request body, also used by tests.
  static Map<String, dynamic> requestBody({
    required String system,
    required List<Map<String, dynamic>> contents,
    required List<AgentTool> tools,
    bool finishOnly = false,
  }) =>
      {
        'systemInstruction': {
          'parts': [
            {'text': system}
          ]
        },
        'contents': contents,
        'tools': [
          {'functionDeclarations': [for (final t in tools) t.toGemini()]}
        ],
        'toolConfig': {
          'functionCallingConfig': {
            'mode': 'ANY',
            if (finishOnly) 'allowedFunctionNames': ['finish'],
          }
        },
        'generationConfig': {'temperature': 0.2},
      };

  @override
  Future<AgentTurn> next({
    required String system,
    required List<Map<String, dynamic>> contents,
    required List<AgentTool> tools,
    bool finishOnly = false,
  }) async {
    final res = await postGemini(_http,
        apiKey: config.apiKey,
        model: _model,
        timeout: timeout,
        body: jsonEncode(requestBody(system: system, contents: contents, tools: tools, finishOnly: finishOnly)));
    if (res.statusCode != 200) {
      final b = res.body;
      throw LlmError('Gemini error ${res.statusCode}: ${b.length > 160 ? '${b.substring(0, 160)}…' : b}', status: res.statusCode);
    }
    return parseAgentTurn(res.body);
  }

  @override
  void close() {
    if (_ownClient) _http.close();
  }
}
