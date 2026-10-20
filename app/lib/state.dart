import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/investigator.dart';
import 'engine/llm.dart';
import 'engine/models.dart';
import 'engine/relationship.dart';

/// One message the browser extension saw in WhatsApp Web or Telegram Web.
class LiveItem {
  final String chat;
  final String sender;
  final String text;
  final DateTime at;
  final Investigation investigation;
  final RelationshipReport? conversation;
  const LiveItem(this.chat, this.sender, this.text, this.at, this.investigation, this.conversation);
}

class AppState extends ChangeNotifier {
  LlmConfig llm = LlmConfig.defaults;
  Set<String> ownDetails = {};
  final List<Investigation> history = [];
  final List<LiveItem> live = [];
  bool extensionConnected = false;
  DateTime? lastExtensionPing;
  String? serverError;

  /// Set by the shell so a live alert or a deep link can open a result.
  void Function(Investigation)? openResult;

  InvestigateOptions get options => InvestigateOptions(llm: llm, ownDetails: ownDetails);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final j = p.getString('llm');
      if (j != null) {
        final saved = LlmConfig.fromJson(jsonDecode(j) as Map<String, dynamic>);
        // Fall back to the built-in key if the user never entered their own.
        llm = saved.kind == LlmKind.gemini && saved.apiKey.isEmpty
            ? LlmConfig(kind: LlmKind.gemini, apiKey: LlmConfig.defaults.apiKey, model: saved.model)
            : saved;
      }
      ownDetails = (p.getStringList('ownDetails') ?? []).toSet();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> saveLlm(LlmConfig c) async {
    llm = c;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('llm', jsonEncode(c.toJson()));
  }

  Future<void> saveOwnDetails(Set<String> v) async {
    ownDetails = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList('ownDetails', v.toList());
  }

  void addHistory(Investigation i) {
    history.insert(0, i);
    if (history.length > 50) history.removeLast();
    notifyListeners();
  }

  void addLive(LiveItem item) {
    live.insert(0, item);
    if (live.length > 100) live.removeLast();
    notifyListeners();
  }

  void setServerError(String e) {
    serverError = e;
    notifyListeners();
  }

  void pingExtension() {
    lastExtensionPing = DateTime.now();
    if (!extensionConnected) {
      extensionConnected = true;
      notifyListeners();
    }
  }
}

final appState = AppState();
