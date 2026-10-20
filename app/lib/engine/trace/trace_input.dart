/// Works out what the user asked to trace, and the on-device checks for
/// phone numbers and bank accounts (format only, no lookups).
library;

import '../entities.dart';
import '../models.dart';

enum SeedKind { url, phone, account, email }

class TraceSeed {
  final SeedKind kind;
  final String value;
  const TraceSeed(this.kind, this.value);
  @override
  String toString() => '${kind.name}:$value';
}

class TraceInput {
  final List<TraceSeed> seeds;
  /// True when the input was a whole message and the seeds were pulled out of it.
  final bool message;
  const TraceInput(this.seeds, {this.message = false});
}

final _email = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');
final _numberish = RegExp(r'^\+?[\d\s()-]{6,}$');

bool _looksLikePhone(String raw, String d) {
  if (raw.trim().startsWith('+') || d.startsWith('00')) return true;
  return RegExp(r'^(0?1\d{8,9}|601\d{8,9}|0[3-9]\d{7,8}|60[3-9]\d{7,8}|1[378]00\d{6})$').hasMatch(d);
}

/// One link, number, account or email, or the ones found in a message.
TraceInput parseTraceInput(String input, {int max = 5}) {
  final s = input.trim();
  if (s.isEmpty) return const TraceInput([]);
  if (_email.hasMatch(s)) return TraceInput([TraceSeed(SeedKind.email, s.toLowerCase())]);
  if (_numberish.hasMatch(s)) {
    final d = s.replaceAll(RegExp(r'\D'), '');
    if (_looksLikePhone(s, d)) return TraceInput([TraceSeed(SeedKind.phone, s)]);
    if (d.length >= 6 && d.length <= 20) return TraceInput([TraceSeed(SeedKind.account, d)]);
  }
  if (!RegExp(r'\s').hasMatch(s) && s.contains('.')) {
    final u = Uri.tryParse(RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(s) ? s : 'https://$s');
    if (u != null && u.host.contains('.') && RegExp(r'[a-z]', caseSensitive: false).hasMatch(u.host)) {
      return TraceInput([TraceSeed(SeedKind.url, s)]);
    }
  }
  final seeds = <TraceSeed>[];
  final seen = <String>{};
  for (final e in extractEntities(s)) {
    final kind = switch (e.type) {
      EntityType.url => SeedKind.url,
      EntityType.phone => SeedKind.phone,
      EntityType.bankAccount => SeedKind.account,
      EntityType.email => SeedKind.email,
      _ => null,
    };
    if (kind == null) continue;
    final key = '${kind.name}:${e.value.toLowerCase().replaceAll(RegExp(r'[\s-]'), '')}';
    if (seen.add(key)) seeds.add(TraceSeed(kind, kind == SeedKind.account ? e.value.replaceAll(RegExp(r'\D'), '') : e.value));
    if (seeds.length >= max) break;
  }
  return TraceInput(seeds, message: true);
}

// ------------------------------------------------------------- phone numbers

class PhoneInfo {
  /// International form without "+", e.g. 60123456789.
  final String digits;
  final String callingCode;
  final String? country;
  final String lineType;
  final String? area;
  const PhoneInfo(this.digits, this.callingCode, this.country, this.lineType, {this.area});

  String get display => '+$digits';
  bool get malaysian => country == 'MY';
}

/// Calling codes of the countries Malaysian scam calls most often come from,
/// plus the big ones. Longest prefix wins.
const callingCodes = {
  '60': 'MY', '65': 'SG', '62': 'ID', '66': 'TH', '63': 'PH', '84': 'VN', '855': 'KH', '856': 'LA', '95': 'MM',
  '673': 'BN', '86': 'CN', '852': 'HK', '853': 'MO', '886': 'TW', '81': 'JP', '82': 'KR', '91': 'IN', '92': 'PK',
  '880': 'BD', '94': 'LK', '977': 'NP', '61': 'AU', '64': 'NZ', '1': 'US', '44': 'GB', '49': 'DE', '33': 'FR',
  '31': 'NL', '7': 'RU', '90': 'TR', '971': 'AE', '966': 'SA', '234': 'NG', '27': 'ZA', '20': 'EG', '55': 'BR',
  '39': 'IT', '34': 'ES', '380': 'UA', '48': 'PL', '40': 'RO',
};

/// Reads a number by its format only: country code, mobile or fixed line,
/// and the area for Malaysian fixed lines. Nothing leaves the phone.
PhoneInfo analyzePhone(String raw) {
  final t = raw.trim();
  var d = t.replaceAll(RegExp(r'\D'), '');
  final international = t.startsWith('+') || d.startsWith('00');
  if (d.startsWith('00')) d = d.substring(2);
  if (!international) {
    if (RegExp(r'^1[378]00\d{6}$').hasMatch(d)) {
      return PhoneInfo('60$d', '60', 'MY', d.startsWith('1800') ? 'Toll-free business line (1-800)' : 'Business line (1-300 / 1-700)');
    }
    if (d.startsWith('0')) {
      d = '60${d.substring(1)}';
    } else if (d.startsWith('1') && d.length >= 9 && d.length <= 10) {
      d = '60$d';
    }
  }
  String? cc;
  for (final n in [3, 2, 1]) {
    if (d.length > n && callingCodes.containsKey(d.substring(0, n))) {
      cc = d.substring(0, n);
      break;
    }
  }
  if (cc == null) return PhoneInfo(d, '', null, 'Unknown format');
  final country = callingCodes[cc]!;
  if (country != 'MY') return PhoneInfo(d, cc, country == 'US' ? null : country, cc == '1' ? 'North American number (US, Canada or Caribbean)' : 'Overseas number');
  final n = d.substring(2);
  if (n.startsWith('15')) return PhoneInfo(d, cc, 'MY', 'Internet phone (VoIP) number');
  if (RegExp(r'^1[378]00').hasMatch(n)) return PhoneInfo(d, cc, 'MY', 'Business line');
  if (n.startsWith('1')) return PhoneInfo(d, cc, 'MY', 'Mobile number');
  final area = switch (n) {
    _ when n.startsWith('3') => 'Kuala Lumpur, Selangor or Putrajaya',
    _ when n.startsWith('4') => 'Penang, Kedah or Perlis',
    _ when n.startsWith('5') => 'Perak',
    _ when n.startsWith('6') => 'Melaka or Negeri Sembilan',
    _ when n.startsWith('7') => 'Johor',
    _ when RegExp(r'^8[2-6]').hasMatch(n) => 'Sarawak',
    _ when RegExp(r'^8[7-9]').hasMatch(n) => 'Sabah or Labuan',
    _ when n.startsWith('9') => 'Kelantan, Terengganu or Pahang',
    _ => null,
  };
  return PhoneInfo(d, cc, 'MY', area == null ? 'Unknown Malaysian number' : 'Fixed line', area: area);
}

// ------------------------------------------------------------- bank accounts

/// Malaysian banks whose personal account numbers usually have this many
/// digits. Length alone never proves which bank it is.
const accountLengths = {
  10: ['CIMB', 'Public Bank', 'OCBC', 'UOB'],
  11: ['Hong Leong Bank'],
  12: ['Maybank', 'Bank Rakyat'],
  13: ['AmBank'],
  14: ['CIMB', 'RHB', 'Bank Islam'],
  16: ['BSN'],
};

class AccountInfo {
  final String digits;
  final List<String> banksByLength;
  final List<String> oddities;
  const AccountInfo(this.digits, this.banksByLength, this.oddities);
  String get masked => digits.length <= 4 ? digits : '${'•' * 4} ${digits.substring(digits.length - 4)}';
}

AccountInfo analyzeAccount(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  final odd = <String>[
    if (RegExp(r'^(\d)\1+$').hasMatch(d)) 'every digit is the same',
    if ('01234567890123456789'.contains(d) || '98765432109876543210'.contains(d)) 'the digits simply count up or down',
    if (RegExp(r'^(0?1\d{8,9}|601\d{8,9})$').hasMatch(d)) 'it is shaped like a Malaysian mobile number (DuitNow can pay to phone numbers)',
    if (d.length < 8 || d.length > 17) 'its length (${d.length} digits) is unusual for a Malaysian bank account',
  ];
  return AccountInfo(d, accountLengths[d.length] ?? const [], odd);
}
