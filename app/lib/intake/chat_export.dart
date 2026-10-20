import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../engine/relationship.dart';

/// Parses Telegram Desktop's "Export chat history" result.json (one chat, or
/// the first chat of a full export) into chat messages.
List<ChatMessage> parseTelegramExport(String json, {String? me}) {
  final root = jsonDecode(json);
  Map<String, dynamic>? chat;
  if (root is Map<String, dynamic> && root['messages'] is List) {
    chat = root;
  } else if (root is Map<String, dynamic>) {
    final list = root['chats']?['list'] as List?;
    chat = list?.whereType<Map<String, dynamic>>().where((c) => c['messages'] is List).firstOrNull;
  }
  if (chat == null) throw const FormatException('No messages in this Telegram export');
  final out = <ChatMessage>[];
  for (final m in (chat['messages'] as List).whereType<Map<String, dynamic>>()) {
    if (m['type'] != null && m['type'] != 'message') continue;
    final text = telegramText(m['text']);
    final extra = [
      if (m['photo'] != null) '[photo]',
      if (m['file'] != null) '[file${m['file_name'] != null ? ': ${m['file_name']}' : ''}]',
      if (m['forwarded_from'] != null) '[forwarded from ${m['forwarded_from']}]',
    ];
    final body = [text, ...extra].where((s) => s.trim().isNotEmpty).join(' ');
    if (body.isEmpty) continue;
    final sender = '${m['from'] ?? m['actor'] ?? 'Unknown'}'.trim();
    out.add(ChatMessage(
      time: DateTime.tryParse('${m['date'] ?? ''}'),
      sender: sender,
      text: body,
      fromMe: me != null && sender.toLowerCase() == me.toLowerCase(),
    ));
  }
  return out;
}

/// Telegram stores text as a string or a list of strings and entity objects.
String telegramText(Object? t) {
  if (t == null) return '';
  if (t is String) return t;
  if (t is List) {
    return t.map((e) => e is String ? e : (e is Map ? '${e['text'] ?? ''}' : '')).join();
  }
  return '$t';
}

/// Turns any chat export file (WhatsApp .txt, a WhatsApp .zip, or Telegram
/// result.json) into WhatsApp-style lines that the Relationship page parses.
String chatExportText(Uint8List bytes) {
  var raw = bytes;
  if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    try {
      final zip = ZipDecoder().decodeBytes(bytes);
      final f = zip.files.where((f) => f.isFile && (f.name.endsWith('.txt') || f.name.endsWith('.json'))).firstOrNull;
      if (f != null) raw = f.content;
    } catch (_) {}
  }
  final text = utf8.decode(raw, allowMalformed: true);
  final t = text.trimLeft();
  if (!t.startsWith('{')) return text;
  try {
    return parseTelegramExport(t).map(chatLine).join('\n');
  } catch (_) {
    return text;
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// One message in WhatsApp's Android export format.
String chatLine(ChatMessage m) {
  final d = m.time ?? DateTime(2000);
  final sender = m.sender.replaceAll(':', ' ').trim();
  return '${_two(d.day)}/${_two(d.month)}/${d.year}, ${_two(d.hour)}:${_two(d.minute)} - ${sender.isEmpty ? 'Unknown' : sender}: ${m.text}';
}

/// Detects a chat export in plain text: WhatsApp lines or Telegram JSON.
bool looksLikeChatExport(String text) {
  final t = text.trimLeft();
  if (t.startsWith('{') && t.contains('"messages"')) return true;
  return RegExp(r'^\[?\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4},?\s+\d{1,2}:\d{2}', multiLine: true).allMatches(text).length >= 3;
}

/// Messages from a chat export in either format.
List<ChatMessage> parseAnyChatExport(String text) {
  final t = text.trimLeft();
  if (t.startsWith('{')) {
    try {
      return parseTelegramExport(t);
    } catch (_) {}
  }
  return parseChatExport(text);
}
