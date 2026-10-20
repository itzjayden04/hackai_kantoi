import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../engine/investigator.dart';
import '../engine/models.dart';
import '../state.dart';
import 'intake_settings.dart';
import 'router.dart';

/// "Telegram bot: on, @name", shown in Settings.
final telegramBotStatus = ValueNotifier<String>('Off: no bot token set up');

int _generation = 0;
String _runningToken = '';

bool get _desktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Starts the Telegram bot when a token is set (desktop only), and restarts
/// it whenever the token changes in Settings.
Future<void> startTelegramBot() async {
  await intakeSettings.load();
  if (!_desktop) {
    telegramBotStatus.value = 'Only runs in the Kantoi app on a computer';
    return;
  }
  intakeSettings.addListener(_maybeRestart);
  _maybeRestart();
}

void _maybeRestart() {
  final token = intakeSettings.telegramToken;
  if (token == _runningToken) return;
  _runningToken = token;
  final gen = ++_generation;
  if (token.isEmpty) {
    telegramBotStatus.value = 'Off: no bot token set up';
    return;
  }
  unawaited(_run(token, gen));
}

Future<void> _run(String token, int gen) async {
  final client = http.Client();
  final base = 'https://api.telegram.org/bot$token';
  var offset = 0;
  var backoff = 5;
  try {
    while (gen == _generation) {
      try {
        final me = jsonDecode((await client.get(Uri.parse('$base/getMe')).timeout(const Duration(seconds: 15))).body);
        if (me['ok'] != true) {
          telegramBotStatus.value = 'Not working: the bot token was refused';
          return;
        }
        telegramBotStatus.value = 'On, @${me['result']['username']}';
        backoff = 5;
        while (gen == _generation) {
          final res = await client
              .get(Uri.parse('$base/getUpdates?timeout=30&offset=$offset&allowed_updates=%5B%22message%22%5D'))
              .timeout(const Duration(seconds: 45));
          final j = jsonDecode(res.body) as Map<String, dynamic>;
          if (j['ok'] != true) throw Exception(j['description'] ?? 'Telegram error ${res.statusCode}');
          for (final u in (j['result'] as List).cast<Map<String, dynamic>>()) {
            offset = (u['update_id'] as int) + 1;
            final msg = u['message'] as Map<String, dynamic>?;
            if (msg != null && gen == _generation) unawaited(_handle(client, base, msg));
          }
        }
      } catch (e) {
        if (gen != _generation) return;
        telegramBotStatus.value = 'Reconnecting (${e.toString().split('\n').first})';
        await Future.delayed(Duration(seconds: backoff));
        backoff = (backoff * 2).clamp(5, 120);
      }
    }
  } finally {
    client.close();
  }
}

Future<void> _handle(http.Client client, String base, Map<String, dynamic> msg) async {
  final chatId = msg['chat']['id'];
  Future<void> reply(String text) => client.post(Uri.parse('$base/sendMessage'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'chat_id': chatId, 'text': text, 'reply_to_message_id': msg['message_id']}));
  final text = (msg['text'] ?? msg['caption'] ?? '') as String;
  try {
    if (text.trim().startsWith('/start') || text.trim() == '/help') {
      await reply('Hi, I am Kantoi. Forward me any message, link or screenshot you are unsure about and I will tell you if it looks like a scam, and what to do.');
      return;
    }
    Uint8List? photo;
    final photos = msg['photo'] as List?;
    if (photos != null && photos.isNotEmpty) {
      final fileId = (photos.last as Map)['file_id'];
      final f = jsonDecode((await client.get(Uri.parse('$base/getFile?file_id=$fileId'))).body);
      final path = f['result']?['file_path'];
      if (path != null) {
        photo = (await client.get(Uri.parse('${base.replaceFirst('/bot', '/file/bot')}/$path'))).bodyBytes;
      }
    }
    if (text.trim().isEmpty && photo == null) {
      await reply('Please forward a message, link or screenshot for me to check.');
      return;
    }
    final routed = photo != null
        ? await routeInput(bytes: photo, name: 'photo.jpg', mime: 'image/jpeg', source: Source.telegramBot, llm: appState.llm, virusTotalKey: intakeSettings.virusTotalKey)
        : await routeInput(text: text, source: Source.telegramBot, llm: appState.llm);
    final inv = await investigate(
      photo != null && text.trim().isNotEmpty ? '${text.trim()}\n${routed.text}' : routed.text,
      source: Source.telegramBot,
      sender: msg['forward_sender_name'] as String? ?? (msg['forward_from'] as Map?)?['first_name'] as String?,
      options: appState.options,
      extras: routed.extras,
    );
    appState.addHistory(inv);
    await reply(botReply(inv));
  } catch (e) {
    await reply(e is IntakeError ? e.message : 'Sorry, I could not check that one. Try sending the text instead.');
  }
}

/// The verdict, top reasons and safe next step, as a Telegram message.
String botReply(Investigation inv) {
  final v = inv.verdict;
  final reasons = inv.findings.where((f) => f.isRisk).toList()..sort((a, b) => b.weight.compareTo(a.weight));
  final legit = inv.findings.where((f) => !f.isRisk).map((f) => f.title).toSet();
  final top = reasons.map((f) => f.title).toSet().take(3).toList();
  return [
    'Kantoi: ${riskLabel(v.level)} (risk ${v.score}/100)',
    if (v.scamType.isNotEmpty) 'Type: ${v.scamType}',
    '',
    v.headline,
    if (top.isNotEmpty) ...['', 'Why:', for (final t in top) '- $t'],
    if (top.isEmpty && legit.isNotEmpty) ...['', 'Good signs:', for (final t in legit.take(2)) '- $t'],
    '',
    'What to do: ${v.nextStep}',
    if (v.level.index >= RiskLevel.suspicious.index) 'If you already paid or shared details, call 997 now.',
  ].join('\n');
}
