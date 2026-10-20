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
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final parts = <Map<String, dynamic>>[
      {'text': user},
      if (img != null) {'inline_data': {'mime_type': mime, 'data': base64Encode(img)}},
    ];
    final res = await _http
        .post(uri,
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': config.apiKey},
            body: jsonEncode({
              'system_instruction': {
                'parts': [{'text': system}]
              },
              'contents': [
                {'role': 'user', 'parts': parts}
              ],
              'generationConfig': {'temperature': 0.2, 'responseMimeType': 'application/json'},
            }))
        .timeout(timeout);
    if (res.statusCode != 200) throw LlmError('Gemini error ${res.statusCode}: ${_short(res.body)}');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final cands = j['candidates'] as List? ?? [];
    if (cands.isEmpty) throw LlmError('Gemini returned no answer');
    final ps = (cands.first['content']?['parts'] as List?) ?? [];
    return ps.map((p) => p['text'] ?? '').join();
  }

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

class LlmError implements Exception {
  final String message;
  LlmError(this.message);
  @override
  String toString() => message;
}
