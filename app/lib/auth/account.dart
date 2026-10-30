import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The privacy notice version a user agreed to at sign-up. Bump it when the
/// notice changes so users are asked again.
const consentVersion = '2026-10-30';

enum SignInMethod { google, email }

class KantoiUser {
  final String uid;
  final SignInMethod method;
  final String fullName;
  final String email;
  final String username;
  final String phone;
  final DateTime created;
  final String consent;
  final DateTime consentAt;

  const KantoiUser({
    required this.uid,
    required this.method,
    required this.fullName,
    required this.email,
    this.username = '',
    this.phone = '',
    required this.created,
    required this.consent,
    required this.consentAt,
  });

  String get initials {
    final p = fullName.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (p.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'method': method.name,
        'fullName': fullName,
        'email': email,
        'username': username,
        'phone': phone,
        'created': created.toIso8601String(),
        'consent': consent,
        'consentAt': consentAt.toIso8601String(),
      };

  factory KantoiUser.fromJson(Map<String, dynamic> j) => KantoiUser(
        uid: j['uid'] as String,
        method: SignInMethod.values.firstWhere((m) => m.name == j['method'], orElse: () => SignInMethod.email),
        fullName: j['fullName'] as String? ?? '',
        email: j['email'] as String? ?? '',
        username: j['username'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        created: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        consent: j['consent'] as String? ?? '',
        consentAt: DateTime.tryParse(j['consentAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// What the register form collects before the email code is sent.
class Registration {
  final String fullName;
  final String email;
  final String phone;
  final String username;
  final String password;
  final bool agreed;
  const Registration(
      {required this.fullName, required this.email, this.phone = '', required this.username, required this.password, required this.agreed});
}

/// Plain-English problems with a registration form, keyed by field.
Map<String, String> validateRegistration(Registration r) {
  final e = <String, String>{};
  if (r.fullName.trim().length < 2) e['fullName'] = 'Please enter your name.';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(r.email.trim())) e['email'] = "That email address doesn't look right.";
  final digits = r.phone.replaceAll(RegExp(r'\D'), '');
  if (r.phone.trim().isNotEmpty && (digits.length < 9 || digits.length > 13)) e['phone'] = 'Please check the phone number.';
  if (!RegExp(r'^[a-zA-Z0-9_.]{3,20}$').hasMatch(r.username.trim())) {
    e['username'] = '3 to 20 letters, numbers, dots or underscores.';
  }
  if (passwordStrength(r.password) < 2) e['password'] = 'Use at least 8 characters with letters and numbers.';
  if (!r.agreed) e['agreed'] = 'Please tick the box to agree to the Privacy Notice.';
  return e;
}

/// 0 = weak, 1 = okay, 2 = strong, 3 = very strong.
int passwordStrength(String p) {
  if (p.length < 8) return 0;
  var kinds = 0;
  if (RegExp(r'[a-z]').hasMatch(p)) kinds++;
  if (RegExp(r'[A-Z]').hasMatch(p)) kinds++;
  if (RegExp(r'\d').hasMatch(p)) kinds++;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(p)) kinds++;
  const common = ['password', '12345678', 'qwerty', 'kantoi', 'abc12345', 'iloveyou'];
  if (common.any(p.toLowerCase().contains)) return 1;
  if (kinds >= 3 && p.length >= 12) return 3;
  if (kinds >= 2) return 2;
  return 1;
}

/// PBKDF2-HMAC-SHA256, so a stolen copy of the account list does not give
/// passwords away.
String hashPassword(String password, String salt, {int iterations = 20000}) {
  final hmac = Hmac(sha256, utf8.encode(password));
  final s = utf8.encode(salt);
  var u = hmac.convert([...s, 0, 0, 0, 1]).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return base64Encode(out);
}
