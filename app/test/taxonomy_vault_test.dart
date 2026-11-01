import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kantoi/engine/models.dart';
import 'package:kantoi/engine/taxonomy.dart';
import 'package:kantoi/vault/vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('taxonomy', () {
    test('has 5 groups of 4 kinds with unique codes', () {
      expect(scamKinds.length, 20);
      expect(scamKinds.map((k) => k.code).toSet().length, 20);
      for (final g in ScamGroup.values) {
        expect(kindsIn(g).length, 4, reason: g.name);
      }
    });

    test('AI codes are taken as they are', () {
      expect(classifyScam(scamType: 'finance.crypto')!.code, 'finance.crypto');
    });

    test('classifies common Malaysian scams by name and text', () {
      expect(classifyScam(scamType: 'Fake officer (Macau) scam')!.code, 'identity.government');
      expect(classifyScam(scamType: 'Job task scam', text: 'Kerja part time, like videos, komisen RM300')!.code, 'finance.task_job');
      expect(classifyScam(scamType: 'Parcel fee scam', text: 'Pay RM2 at this link to release your parcel')!.code, 'cyber.phishing');
      expect(classifyScam(text: 'Please send me the 6-digit TAC code you just received')!.code, 'cyber.sim_otp');
      expect(classifyScam(scamType: 'Love and investment scam', text: 'darling, invest in this USDT platform')!.code, 'social.romance');
      expect(classifyScam(text: 'Room for rent in Kampar, pay deposit first before viewing')!.code, 'commerce.rental');
    });

    test('a clean message has no kind', () {
      expect(classifyScam(scamType: 'Legitimate message', text: 'See you at lunch'), isNull);
      expect(classifyScam(scamType: 'Unclear'), isNull);
    });

    test('cue categories alone still point somewhere', () {
      expect(classifyScam(cues: [CueCategory.file])!.code, 'cyber.malware');
    });
  });

  group('safe word vault', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saves, sorts, searches, locks and reopens', () async {
      final v = SafeWordVault(crypto: PlainVaultCrypto());
      await v.load();
      expect(v.count, 0);
      expect(await v.unlock(), isTrue);
      await v.upsert(SafeWord(id: '1', name: 'Siti Aminah', relationship: 'Parent', phone: '012-345 6789', word: 'mango lantern'));
      await v.upsert(SafeWord(id: '2', name: 'Ali', relationship: 'Sibling', word: 'river teacup'));
      expect(v.entries.map((e) => e.name), ['Ali', 'Siti Aminah']);
      expect(v.search('siti').single.id, '1');
      expect(v.search('3456').single.id, '1');
      expect(v.search('mango'), isEmpty, reason: 'never searchable by the word');
      v.lock();
      expect(v.entries, isEmpty);
      expect(() => v.upsert(SafeWord(id: '3', name: 'X', word: 'y')), throwsStateError);

      final again = SafeWordVault(crypto: PlainVaultCrypto());
      await again.load();
      expect(again.count, 2);
      expect(again.unlocked, isFalse);
      await again.unlock();
      expect(again.entries.firstWhere((e) => e.id == '1').word, 'mango lantern');
      await again.remove('2');
      expect(again.count, 1);
    });

    test('a cancelled unlock keeps it locked', () async {
      final v = SafeWordVault(crypto: PlainVaultCrypto(unlockAnswer: 'cancelled'));
      expect(await v.unlock(), isFalse);
      expect(v.unlocked, isFalse);
    });

    test('a phone with no screen lock still opens, flagged', () async {
      final v = SafeWordVault(crypto: PlainVaultCrypto(unlockAnswer: 'nolock'));
      expect(await v.unlock(), isTrue);
      expect(v.noPhoneLock, isTrue);
    });

    test('suggested words are two different everyday words', () {
      final w = suggestSafeWord(random: Random(1)).split(' ');
      expect(w.length, 2);
      expect(w[0], isNot(w[1]));
    });

    test('weak words are flagged', () {
      expect(safeWordWarnings('mango lantern', name: 'Siti'), isEmpty);
      expect(safeWordWarnings('siti1990', name: 'Siti Aminah'), isNotEmpty);
      expect(safeWordWarnings('12/05'), isNotEmpty);
      expect(safeWordWarnings('ab'), isNotEmpty);
    });

    test('reminds about safe words when someone poses as family', () {
      expect(shouldAskSafeWord(kindCode: 'identity.family'), isTrue);
      expect(shouldAskSafeWord(text: 'Mak, ini saya. Nombor baru. Boleh pinjam RM500?'), isTrue);
      expect(shouldAskSafeWord(text: 'Your parcel is waiting'), isFalse);
    });
  });
}
