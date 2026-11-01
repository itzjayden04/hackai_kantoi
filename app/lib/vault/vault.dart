import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One person and the safe word agreed with them.
class SafeWord {
  final String id;
  String name;
  String relationship;
  String phone;
  String word;
  String hint;
  String notes;
  DateTime created;
  DateTime? lastChecked;

  SafeWord({
    required this.id,
    required this.name,
    required this.word,
    this.relationship = '',
    this.phone = '',
    this.hint = '',
    this.notes = '',
    DateTime? created,
    this.lastChecked,
  }) : created = created ?? DateTime.now();

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'relationship': relationship,
        'phone': phone,
        'word': word,
        'hint': hint,
        'notes': notes,
        'created': created.toIso8601String(),
        'lastChecked': lastChecked?.toIso8601String(),
      };

  factory SafeWord.fromJson(Map<String, dynamic> j) => SafeWord(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        relationship: j['relationship'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        word: j['word'] as String? ?? '',
        hint: j['hint'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        created: DateTime.tryParse(j['created'] as String? ?? ''),
        lastChecked: DateTime.tryParse(j['lastChecked'] as String? ?? ''),
      );
}

const relationships = ['Parent', 'Child', 'Partner', 'Sibling', 'Grandparent', 'Friend', 'Colleague', 'Other'];

/// Encrypts and unlocks through Android's keystore (kantoi/vault). Tests and
/// non-Android builds swap in [PlainVaultCrypto].
abstract class VaultCrypto {
  Future<String> encrypt(String plain);
  Future<String> decrypt(String sealed);
  /// "ok", "cancelled" or "nolock".
  Future<String> unlock();
  Future<void> secureScreen(bool on);
}

class AndroidVaultCrypto implements VaultCrypto {
  static const _ch = MethodChannel('kantoi/vault');
  @override
  Future<String> encrypt(String plain) async => await _ch.invokeMethod<String>('encrypt', plain) ?? '';
  @override
  Future<String> decrypt(String sealed) async => await _ch.invokeMethod<String>('decrypt', sealed) ?? '';
  @override
  Future<String> unlock() async => await _ch.invokeMethod<String>('unlock', 'Unlock your safe words') ?? 'cancelled';
  @override
  Future<void> secureScreen(bool on) => _ch.invokeMethod('secure', on);
}

class PlainVaultCrypto implements VaultCrypto {
  String unlockAnswer;
  PlainVaultCrypto({this.unlockAnswer = 'ok'});
  @override
  Future<String> encrypt(String plain) async => plain;
  @override
  Future<String> decrypt(String sealed) async => sealed;
  @override
  Future<String> unlock() async => unlockAnswer;
  @override
  Future<void> secureScreen(bool on) async {}
}

/// The safe word vault. Lives only on this phone: encrypted at rest, never
/// synced, exported or uploaded. Locks again whenever the app goes to the
/// background.
class SafeWordVault extends ChangeNotifier {
  final VaultCrypto crypto;
  SafeWordVault({VaultCrypto? crypto})
      : crypto = crypto ?? (defaultTargetPlatform == TargetPlatform.android && !kIsWeb ? AndroidVaultCrypto() : PlainVaultCrypto());

  static const _kData = 'vault.sealed';
  static const _kCount = 'vault.count';

  final List<SafeWord> _entries = [];
  bool _unlocked = false;
  /// How many entries are saved, readable while locked (no names or words).
  int count = 0;
  /// Set when the phone has no screen lock, so the vault opens without one.
  bool noPhoneLock = false;

  bool get unlocked => _unlocked;
  List<SafeWord> get entries => List.unmodifiable(_entries);

  /// Reads only the count, so warnings can offer the vault without unlocking.
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      count = p.getInt(_kCount) ?? 0;
    } catch (_) {}
    notifyListeners();
  }

  /// Asks for the phone's fingerprint, face or PIN, then decrypts.
  /// Returns false when the user cancelled.
  Future<bool> unlock() async {
    final r = await crypto.unlock();
    if (r == 'cancelled') return false;
    noPhoneLock = r == 'nolock';
    try {
      final p = await SharedPreferences.getInstance();
      final sealed = p.getString(_kData);
      _entries.clear();
      if (sealed != null && sealed.isNotEmpty) {
        final list = jsonDecode(await crypto.decrypt(sealed)) as List;
        _entries.addAll(list.map((e) => SafeWord.fromJson((e as Map).cast<String, dynamic>())));
      }
    } catch (_) {
      // A vault that can't be decrypted (keystore wiped) starts empty rather
      // than locking the user out forever.
      _entries.clear();
    }
    _unlocked = true;
    count = _entries.length;
    notifyListeners();
    return true;
  }

  void lock() {
    if (!_unlocked) return;
    _entries.clear();
    _unlocked = false;
    notifyListeners();
  }

  Future<void> upsert(SafeWord w) async {
    _requireUnlocked();
    final i = _entries.indexWhere((e) => e.id == w.id);
    if (i >= 0) {
      _entries[i] = w;
    } else {
      _entries.add(w);
    }
    _entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _save();
  }

  Future<void> remove(String id) async {
    _requireUnlocked();
    _entries.removeWhere((e) => e.id == id);
    await _save();
  }

  Future<void> markChecked(String id, {DateTime? at}) async {
    _requireUnlocked();
    for (final e in _entries) {
      if (e.id == id) e.lastChecked = at ?? DateTime.now();
    }
    await _save();
  }

  /// Search by name, relationship or phone (never by the word itself).
  List<SafeWord> search(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return entries;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return _entries
        .where((e) =>
            e.name.toLowerCase().contains(t) ||
            e.relationship.toLowerCase().contains(t) ||
            (digits.length >= 3 && e.phone.replaceAll(RegExp(r'\D'), '').contains(digits)))
        .toList();
  }

  Future<void> deleteAll() async {
    _entries.clear();
    count = 0;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kData);
      await p.remove(_kCount);
    } catch (_) {}
    notifyListeners();
  }

  void _requireUnlocked() {
    if (!_unlocked) throw StateError('Vault is locked');
  }

  Future<void> _save() async {
    count = _entries.length;
    final sealed = await crypto.encrypt(jsonEncode(_entries.map((e) => e.toJson()).toList()));
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kData, sealed);
      await p.setInt(_kCount, count);
    } catch (_) {}
    notifyListeners();
  }
}

final vault = SafeWordVault();

/// Everyday words that are easy to say on a call and hard to guess. No names,
/// dates or words a scammer could find on social media.
const _words = [
  'mango', 'lantern', 'river', 'teacup', 'pillow', 'rocket', 'garden', 'violin', 'pepper', 'island', 'marble', 'kettle',
  'saddle', 'meadow', 'compass', 'banana', 'ladder', 'harbour', 'pebble', 'blanket', 'cactus', 'feather', 'helmet', 'jigsaw',
  'lemon', 'magnet', 'noodle', 'orchid', 'pencil', 'puzzle', 'rainbow', 'sandal', 'tiger', 'tunnel', 'umbrella', 'velvet',
  'walnut', 'window', 'anchor', 'bamboo', 'candle', 'dolphin', 'durian', 'engine', 'falcon', 'glacier', 'hammock', 'iguana',
  'jasmine', 'kayak', 'lychee', 'mirror', 'nutmeg', 'oyster', 'paddle', 'quilt', 'rambutan', 'satay', 'teapot', 'tortoise',
  'turtle', 'volcano', 'wagon', 'yogurt', 'zebra', 'apricot', 'balloon', 'biscuit', 'bucket', 'button', 'carrot', 'castle',
  'cherry', 'cobweb', 'coconut', 'cookie', 'copper', 'cotton', 'crystal', 'cushion', 'dragon', 'emerald', 'fountain', 'gecko',
  'ginger', 'gravel', 'hornbill', 'jelly', 'kite', 'ladle', 'lagoon', 'lobster', 'mosaic', 'mustard', 'orbit', 'otter',
  'paprika', 'parrot', 'peacock', 'penguin', 'pickle', 'pinwheel', 'planet', 'pretzel', 'pumpkin', 'raisin', 'ribbon', 'saffron',
  'scooter', 'seashell', 'silver', 'snorkel', 'spinach', 'sponge', 'squirrel', 'sunrise', 'teaspoon', 'thimble', 'tulip', 'waffle',
];

/// Two random everyday words, e.g. "mango lantern".
String suggestSafeWord({Random? random}) {
  final r = random ?? Random.secure();
  final a = _words[r.nextInt(_words.length)];
  var b = _words[r.nextInt(_words.length)];
  while (b == a) {
    b = _words[r.nextInt(_words.length)];
  }
  return '$a $b';
}

/// Problems with a word the user typed, in plain English, or empty when fine.
List<String> safeWordWarnings(String word, {String name = ''}) {
  final w = word.trim().toLowerCase();
  final out = <String>[];
  if (w.length < 4) out.add('Too short. Use at least two words.');
  if (RegExp(r'\b(19|20)\d{2}\b').hasMatch(w) || RegExp(r'\b\d{1,2}[/-]\d{1,2}\b').hasMatch(w)) {
    out.add("Looks like a date. Birthdays are easy to find online.");
  }
  if (RegExp(r'^\d+$').hasMatch(w)) out.add('Numbers only are easy to guess. Use words.');
  final n = name.trim().toLowerCase();
  if (n.isNotEmpty && n.split(RegExp(r'\s+')).any((p) => p.length > 2 && w.contains(p))) {
    out.add("Don't use the person's own name.");
  }
  if (const {'password', 'safeword', 'secret', '1234', 'kantoi', 'family', 'love', 'iloveyou'}.any(w.contains)) {
    out.add('Too common. Pick something only the two of you would know.');
  }
  return out;
}

/// Whether a warning should remind the user to ask for their safe word: the
/// scam looks like someone posing as family, a friend or a colleague.
bool shouldAskSafeWord({String? kindCode, String scamType = '', String text = ''}) {
  if (kindCode == 'identity.family') return true;
  final t = '$scamType $text'.toLowerCase();
  const posing = [
    'new number', 'nombor baru', 'no baru', 'hijacked friend', 'friend in need', "it's me", 'its me', 'ini saya', 'saya ni',
    'grandparent', 'family emergency', 'my phone broke', 'phone rosak', 'lost my phone', 'hilang phone', 'change number',
  ];
  return posing.any(t.contains);
}
