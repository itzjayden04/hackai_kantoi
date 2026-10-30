import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum LlmKind { gemini, ollama, openaiCompatible, none }

class LlmConfig {
  final LlmKind kind;
  final String apiKey;
  final String model;
  final String baseUrl;
  const LlmConfig({required this.kind, this.apiKey = '', this.model = '', this.baseUrl = ''});

  static const _buildGeminiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// Default: Gemini with the key baked in at build time (if any).
  static const defaults = LlmConfig(kind: LlmKind.gemini, apiKey: _buildGeminiKey, model: 'gemini-flash-latest');

  bool get usable => switch (kind) {
        LlmKind.none => false,
        LlmKind.ollama => true,
        _ => apiKey.isNotEmpty,
      };

  String get displayName => switch (kind) {
        LlmKind.gemini => 'Gemini ($model)',
        LlmKind.ollama => 'Ollama on this computer ($model)',
        LlmKind.openaiCompatible => 'AI service ($model)',
        LlmKind.none => 'No AI (built-in checks only)',
      };

  /// Whether text is sent to a third-party server.
  bool get leavesDevice => kind == LlmKind.gemini || kind == LlmKind.openaiCompatible;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'apiKey': apiKey, 'model': model, 'baseUrl': baseUrl};
  factory LlmConfig.fromJson(Map<String, dynamic> j) => LlmConfig(
        kind: LlmKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => LlmKind.gemini),
        apiKey: j['apiKey'] as String? ?? '',
        model: j['model'] as String? ?? '',
        baseUrl: j['baseUrl'] as String? ?? '',
      );
}

/// Sends one prompt and returns the model's JSON reply. Every provider is asked
/// for the same JSON shape so the rest of Kantoi does not care which is used.
class LlmClient {
  final LlmConfig config;
  final http.Client _http;
  LlmClient(this.config, {http.Client? client}) : _http = client ?? http.Client();

  Future<Map<String, dynamic>> completeJson({
    required String system,
    required String user,
    List<int>? imageBytes,
    String imageMime = 'image/png',
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final text = switch (config.kind) {
      LlmKind.gemini => await _gemini(system, user, imageBytes, imageMime, timeout),
      LlmKind.ollama => await _ollama(system, user, imageBytes, timeout),
      LlmKind.openaiCompatible => await _openai(system, user, timeout),
      LlmKind.none => throw StateError('No AI configured'),
    };
    return _parseJson(text);
  }

  Future<String> _gemini(String system, String user, List<int>? img, String mime, Duration timeout) async {
    final model = config.model.isEmpty ? 'gemini-flash-latest' : config.model;
    final parts = <Map<String, dynamic>>[
      {'text': user},
      if (img != null) {'inline_data': {'mime_type': mime, 'data': base64Encode(img)}},
    ];
    final res = await postGemini(_http,
        apiKey: config.apiKey,
        model: model,
        timeout: timeout,
        body: jsonEncode({
              'system_instruction': {
                'parts': [{'text': system}]
              },
              'contents': [
                {'role': 'user', 'parts': parts}
              ],
              'generationConfig': {'temperature': 0.2, 'responseMimeType': 'application/json'},
            }));
    if (res.statusCode != 200) throw LlmError('Gemini error ${res.statusCode}: ${_short(res.body)}');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final cands = j['candidates'] as List? ?? [];
    if (cands.isEmpty) throw LlmError('Gemini returned no answer');
    final ps = (cands.first['content']?['parts'] as List?) ?? [];
    return ps.map((p) => p['text'] ?? '').join();
  }

  /// One Gemini call with Google Search grounding turned on. Returns the
  /// model's text and the grounding metadata (the pages Google actually
  /// searched), which callers must treat as the only real sources.
  /// JSON output mode is not allowed together with the search tool, so the
  /// prompt asks for JSON and the caller parses the text.
  Future<GroundedReply> groundedSearch(String prompt, {Duration timeout = const Duration(seconds: 10)}) async {
    if (config.kind != LlmKind.gemini || config.apiKey.isEmpty) throw LlmError('Google Search grounding needs a Gemini key');
    final model = config.model.isEmpty ? 'gemini-flash-latest' : config.model;
    final res = await postGemini(_http, apiKey: config.apiKey, model: model, timeout: timeout, body: jsonEncode(groundedRequestBody(prompt)));
    if (res.statusCode != 200) throw LlmError('Gemini error ${res.statusCode}: ${_short(res.body)}', status: res.statusCode);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final cands = j['candidates'] as List? ?? [];
    if (cands.isEmpty) throw LlmError('Gemini returned no answer');
    final c = cands.first as Map<String, dynamic>;
    final ps = (c['content']?['parts'] as List?) ?? [];
    return GroundedReply(ps.map((p) => p['text'] ?? '').join(), (c['groundingMetadata'] as Map?)?.cast<String, dynamic>());
  }

  /// The request body for [groundedSearch].
  static Map<String, dynamic> groundedRequestBody(String prompt) => {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'tools': [
          {'google_search': <String, dynamic>{}}
        ],
        'generationConfig': {'temperature': 0},
      };

  /// Parses the JSON object in a model reply (fenced or bare).
  static Map<String, dynamic> parseJsonText(String s) => _parseJson(s);

  Future<String> _ollama(String system, String user, List<int>? img, Duration timeout) async {
    final base = config.baseUrl.isEmpty ? 'http://127.0.0.1:11434' : config.baseUrl;
    final res = await _http
        .post(Uri.parse('$base/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': config.model.isEmpty ? 'qwen2.5:7b' : config.model,
              'stream': false,
              'format': 'json',
              'options': {'temperature': 0.2},
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user, if (img != null) 'images': [base64Encode(img)]},
              ],
            }))
        .timeout(timeout * 3);
    if (res.statusCode != 200) throw LlmError('Ollama error ${res.statusCode}: ${_short(res.body)}');
    return (jsonDecode(res.body) as Map<String, dynamic>)['message']?['content'] as String? ?? '';
  }

  Future<String> _openai(String system, String user, Duration timeout) async {
    final base = config.baseUrl.isEmpty ? 'https://api.groq.com/openai/v1' : config.baseUrl;
    final res = await _http
        .post(Uri.parse('$base/chat/completions'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${config.apiKey}'},
            body: jsonEncode({
              'model': config.model.isEmpty ? 'llama-3.3-70b-versatile' : config.model,
              'temperature': 0.2,
              'response_format': {'type': 'json_object'},
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
            }))
        .timeout(timeout);
    if (res.statusCode != 200) throw LlmError('AI service error ${res.statusCode}: ${_short(res.body)}');
    return (jsonDecode(res.body) as Map<String, dynamic>)['choices']?[0]?['message']?['content'] as String? ?? '';
  }

  static Map<String, dynamic> _parseJson(String s) {
    var t = s.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
    if (fence != null) t = fence.group(1)!.trim();
    final a = t.indexOf('{'), b = t.lastIndexOf('}');
    if (a < 0 || b <= a) throw LlmError('AI reply was not JSON');
    return jsonDecode(t.substring(a, b + 1)) as Map<String, dynamic>;
  }

  static String _short(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

  void close() => _http.close();
}

/// The lighter Gemini model, tried when the main one is too busy.
const geminiBackupModel = 'gemini-flash-lite-latest';

/// For tests: the pause before asking a busy Gemini again.
Duration geminiRetryPause = const Duration(seconds: 2);

/// The second Gemini key baked in at build time (GEMINI_API_KEY_2), used when
/// the first one runs out of quota. Empty when the build has none.
String geminiBackupKey = const String.fromEnvironment('GEMINI_API_KEY_2');

/// When the last key that ran out of quota may be tried again. A key that
/// answered 429 is skipped for an hour so every check does not wait on it.
final Map<String, DateTime> _keyRestUntil = {};

/// For tests: forget which keys ran out of quota.
void resetGeminiKeyRest() => _keyRestUntil.clear();

/// Posts to Gemini's generateContent. Gemini sometimes answers 503 ("high
/// demand") or 500 for a moment, so a busy answer is tried once more after a
/// short pause, then once on the lighter backup model. When the key is out of
/// quota (429) and the build has a second key, the second key is used, and
/// the first is rested for an hour.
Future<http.Response> postGemini(http.Client client,
    {required String apiKey, required String model, required String body, required Duration timeout, DateTime? now}) async {
  final t = now ?? DateTime.now();
  final backup = geminiBackupKey;
  final canSwap = backup.isNotEmpty && backup != apiKey;
  final rested = _keyRestUntil[apiKey];
  if (canSwap && rested != null && t.isBefore(rested)) return _postGeminiWithKey(client, backup, model, body, timeout);
  final res = await _postGeminiWithKey(client, apiKey, model, body, timeout);
  if (res.statusCode != 429 || !canSwap) return res;
  _keyRestUntil[apiKey] = t.add(const Duration(hours: 1));
  return _postGeminiWithKey(client, backup, model, body, timeout);
}

Future<http.Response> _postGeminiWithKey(http.Client client, String apiKey, String model, String body, Duration timeout) async {
  Future<http.Response> send(String m) => client
      .post(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey}, body: body)
      .timeout(timeout);
  bool busy(http.Response r) => r.statusCode == 503 || r.statusCode == 500;
  var res = await send(model);
  if (!busy(res)) return res;
  await Future<void>.delayed(geminiRetryPause);
  res = await send(model);
  if (!busy(res) || model == geminiBackupModel) return res;
  return send(geminiBackupModel);
}

class GroundedReply {
  final String text;
  /// Gemini's groundingMetadata, or null when it answered without searching.
  final Map<String, dynamic>? metadata;
  const GroundedReply(this.text, this.metadata);
}

class LlmError implements Exception {
  final String message;
  /// The HTTP status when the service answered with an error.
  final int? status;
  LlmError(this.message, {this.status});
  @override
  String toString() => message;
}
