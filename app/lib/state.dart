import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/forensics/keys.dart';
import 'engine/investigator.dart';
import 'engine/llm.dart';
import 'engine/models.dart';

class AppState extends ChangeNotifier {
  LlmConfig llm = LlmConfig.defaults;
  Set<String> ownDetails = {};
  /// Optional link reputation keys (built-in defaults, overridable in Settings).
  ForensicKeys keys = ForensicKeys.defaults;
  final List<Investigation> history = [];

  /// Which bottom tab is showing (0 Check, 1 Trace, 2 Learn, 3 Emergency).
  /// Any screen or a notification tap can switch tabs through this.
  final tab = ValueNotifier<int>(0);

  /// Something to trace as soon as the Trace tab opens (a link, number,
  /// account or message), e.g. from a result screen or a notification tap.
  final traceRequest = ValueNotifier<String?>(null);

  /// Each tab can register what Back does inside it (stop a check, close a
  /// result). It returns false when the tab is already at its start.
  final Map<int, bool Function()> backHandlers = {};

  void openTrace(String target) {
    traceRequest.value = target;
    tab.value = 1;
  }

  /// Set by the shell so a live alert or a deep link can open a result.
  void Function(Investigation)? openResult;

  InvestigateOptions get options => InvestigateOptions(llm: llm, ownDetails: ownDetails, keys: keys);

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
      final k = p.getString('forensicKeys');
      if (k != null) keys = ForensicKeys.fromJson(jsonDecode(k) as Map<String, dynamic>);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> saveLlm(LlmConfig c) async {
    llm = c;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('llm', jsonEncode(c.toJson()));
  }

  Future<void> saveKeys(ForensicKeys k) async {
    keys = k;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('forensicKeys', jsonEncode(k.userValues()));
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

  /// Drops checks and live items older than [cutoff] (data retention).
  void dropOlderThan(DateTime cutoff) {
    final before = history.length;
    history.removeWhere((i) => i.artefact.receivedAt.isBefore(cutoff));
    if (history.length != before) notifyListeners();
  }

  /// Forgets everything held in memory ("Delete all my Kantoi data"). The
  /// AI key built into the app is a constant, so it stays.
  void forgetAll() {
    llm = LlmConfig.defaults;
    ownDetails = {};
    history.clear();
    notifyListeners();
  }
}

final appState = AppState();
