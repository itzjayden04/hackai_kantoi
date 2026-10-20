/// Personal safety check-up: a short quiz that becomes a to-do list.
library;

import 'package:flutter/foundation.dart';

import 'prefs.dart';

enum Answer { yes, no, unsure }

class CheckItem {
  final String id;
  final String question;
  final String fix;
  final String how;
  const CheckItem(this.id, this.question, this.fix, this.how);
}

const checkItems = <CheckItem>[
  CheckItem(
    'twofa',
    'Is in-app approval (like Secure2u or CIMB SecureTAC) turned on in your banking app?',
    'Turn on in-app approval in your banking app',
    'Open your banking app, go to Settings or Security, and turn on in-app approval. It replaces SMS codes that scammers can steal.',
  ),
  CheckItem(
    'officialApp',
    'Do you use only your bank\'s official app, and have you saved its real website as a bookmark?',
    'Use the official app and save the real website',
    'Install the bank app only from Google Play or the App Store, then bookmark the real website (for example maybank2u.com.my). Use only that, never links in messages.',
  ),
  CheckItem(
    'codeWord',
    'Does your family have a secret code word to prove it\'s really them in an emergency?',
    'Agree a family code word',
    'Pick a word only your family knows, never posted online. If someone calls for money "from family", ask for the word.',
  ),
  CheckItem(
    'neverShare',
    'Do you always keep SMS codes (TAC or OTP) to yourself, even if "the bank" asks?',
    'Never share a TAC or OTP',
    'Nobody genuine will ever ask for your code. If anyone does, hang up and call the number on the back of your card.',
  ),
  CheckItem(
    'privacy',
    'Are your Facebook, Instagram and TikTok set so strangers can\'t see your phone number, birthday or family?',
    'Lock down your social media',
    'In each app, open Settings, then Privacy, and set your phone, birthday and friends list to "Only me" or "Friends".',
  ),
  CheckItem(
    'limits',
    'Have you set a low daily transfer limit in your banking and e-wallet apps?',
    'Set low daily transfer limits',
    'In your banking and e-wallet apps, find "Transaction limits" and lower the daily limit, for example to RM1,000. A scammer can then take less.',
  ),
  CheckItem(
    'nsrc',
    'Do you know to call 997 straight away if you lose money to a scam?',
    'Save 997 in your phone',
    'Save "NSRC Scam Hotline 997" in your contacts. Calling within the first hours gives the best chance of freezing the money.',
  ),
  CheckItem(
    'semakMule',
    'Do you check a bank account or phone number on Semak Mule before paying someone you don\'t know?',
    'Check accounts on Semak Mule before paying',
    'Go to semakmule.rmp.gov.my and enter the account or phone number. If it has police reports, do not pay.',
  ),
];

class Checkup extends ChangeNotifier {
  static const _key = 'awareness.checkup';
  final Map<String, Answer> answers = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final j = await readJson(_key);
    j?.forEach((k, v) {
      final a = Answer.values.where((x) => x.name == v).firstOrNull;
      if (a != null) answers[k] = a;
    });
    notifyListeners();
  }

  void answer(String id, Answer a) {
    answers[id] = a;
    notifyListeners();
    writeJson(_key, {for (final e in answers.entries) e.key: e.value.name});
  }

  Future<void> reset() async {
    answers.clear();
    notifyListeners();
    await removeKey(_key);
  }

  bool get started => answers.isNotEmpty;
  bool get finished => checkItems.every((i) => answers.containsKey(i.id));
  int get safeCount => checkItems.where((i) => answers[i.id] == Answer.yes).length;
  int get score => (safeCount * 100 / checkItems.length).round();

  /// Answered items that still need fixing.
  List<CheckItem> get toFix => checkItems.where((i) => answers.containsKey(i.id) && answers[i.id] != Answer.yes).toList();

  String get grade => switch (score) {
        >= 88 => 'Very well protected',
        >= 63 => 'Well protected, a few gaps',
        >= 38 => 'Some protection, worth fixing',
        _ => 'Easy target, let\'s fix this',
      };
}

final checkup = Checkup();
