import 'dart:convert';
import 'dart:io';

import '../engine/investigator.dart';
import '../engine/llm.dart';
import '../engine/models.dart';
import '../engine/relationship.dart';
import '../state.dart';

const bridgePort = 47821;
const bridgeSupported = true;

/// Per-chat memory of what the extension has seen, so each new message is
/// scored in the context of the whole conversation.
final Map<String, List<ChatMessage>> _chats = {};
final Map<String, Origin> _origins = {};

/// A small HTTP server on 127.0.0.1 that the Kantoi browser extension talks to.
/// It only accepts requests from browser extensions or local tools, never from
/// web pages.
Future<void> startBridge() async {
  if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
  try {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, bridgePort);
    server.listen(_handle);
  } catch (e) {
    appState.setServerError('Could not start the extension link on port $bridgePort ($e). Is Kantoi already open?');
  }
}

Future<void> _handle(HttpRequest req) async {
  final res = req.response;
  final origin = req.headers.value('origin');
  res.headers
    ..set('Access-Control-Allow-Origin', origin ?? '*')
    ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type')
    ..contentType = ContentType.json;
  if (origin != null && !origin.startsWith('chrome-extension://') && !origin.startsWith('moz-extension://')) {
    res.statusCode = HttpStatus.forbidden;
    await res.close();
    return;
  }
  if (req.method == 'OPTIONS') {
    await res.close();
    return;
  }
  try {
    appState.pingExtension();
    final body = req.method == 'POST' ? jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic> : <String, dynamic>{};
    final out = switch (req.uri.path) {
      '/health' => {'app': 'kantoi', 'ok': true, 'ai': appState.llm.displayName},
      '/check' => await _check(body),
      '/conversation' => _conversation(body),
      '/explain' => await _explain(body),
      _ => null,
    };
    if (out == null) {
      res.statusCode = HttpStatus.notFound;
    } else {
      res.write(jsonEncode(out));
    }
  } catch (e) {
    res.statusCode = HttpStatus.badRequest;
    res.write(jsonEncode({'error': '$e'}));
  }
  await res.close();
}

Source _source(Map<String, dynamic> b) => b['source'] == 'telegram' ? Source.telegramWeb : Source.whatsappWeb;

/// Fast check of one incoming message: built-in checks only (no AI), so every
/// message can be scored instantly without using AI quota.
Future<Map<String, dynamic>> _check(Map<String, dynamic> b) async {
  final chat = b['chat'] as String? ?? 'Unknown chat';
  final text = b['text'] as String? ?? '';
  final sender = b['sender'] as String? ?? chat;
  final inv = await investigate(text,
      source: _source(b),
      sender: sender,
      options: InvestigateOptions(llm: const LlmConfig(kind: LlmKind.none), ownDetails: appState.ownDetails));
  final list = _chats.putIfAbsent(chat, () => []);
  if (!list.any((m) => m.text == text && m.sender == sender)) {
    list.add(ChatMessage(time: DateTime.now(), sender: sender, text: text, fromMe: b['fromMe'] == true));
  }
  final rel = analyzeConversation(list, origin: _origins[chat] ?? Origin.unknown);
  if (b['fromMe'] != true && (inv.verdict.level.index >= RiskLevel.caution.index || rel.level.index >= RiskLevel.suspicious.index)) {
    appState.addLive(LiveItem(chat, sender, text, DateTime.now(), inv, rel));
  }
  return {'message': inv.toJson(), 'conversation': rel.toJson()};
}

/// Replaces the stored history of a chat with what is visible on screen.
Map<String, dynamic> _conversation(Map<String, dynamic> b) {
  final chat = b['chat'] as String? ?? 'Unknown chat';
  final msgs = (b['messages'] as List? ?? []).map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList();
  if (b['origin'] != null) {
    _origins[chat] = Origin.values.firstWhere((o) => o.name == b['origin'], orElse: () => Origin.unknown);
  }
  if (msgs.isNotEmpty) _chats[chat] = msgs;
  final rel = analyzeConversation(_chats[chat] ?? const [], origin: _origins[chat] ?? Origin.unknown);
  return {'conversation': rel.toJson()};
}

/// Full investigation with AI, also opened in the Kantoi window.
Future<Map<String, dynamic>> _explain(Map<String, dynamic> b) async {
  final inv = await investigate(b['text'] as String? ?? '', source: _source(b), sender: b['sender'] as String?, options: appState.options);
  appState.addHistory(inv);
  appState.openResult?.call(inv);
  return {'message': inv.toJson()};
}
