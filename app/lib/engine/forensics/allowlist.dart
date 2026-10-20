import '../models.dart';
import '../url_analyzer.dart' show brands, officialBrandFor;

/// Official contact points of a Malaysian bank, courier, e-wallet or agency.
///
/// Only details we are confident are real are listed. Where an SMS short code
/// could not be confirmed, it is left out and only the official domain (in
/// `brands` in url_analyzer.dart) and public hotline are used.
class OfficialSender {
  final String brand;
  final String kind; // bank, courier, e-wallet, agency
  /// Names the organisation sends under (SMS sender ID or verified chat name).
  final List<String> senderIds;
  /// SMS short codes confirmed to belong to the organisation.
  final List<String> shortCodes;
  /// Public customer care numbers, digits only.
  final List<String> hotlines;
  const OfficialSender(this.brand, this.kind, {this.senderIds = const [], this.shortCodes = const [], this.hotlines = const []});

  List<String> get domains => brands[brand] ?? const [];
}

const officialSenders = <OfficialSender>[
  OfficialSender('Maybank', 'bank', senderIds: ['Maybank', 'Maybank2u'], hotlines: ['1300886688']),
  OfficialSender('CIMB', 'bank', senderIds: ['CIMB', 'CIMB Bank', 'CIMB Clicks'], hotlines: ['0362047788']),
  OfficialSender('Public Bank', 'bank', senderIds: ['Public Bank', 'PBe', 'PBB'], hotlines: ['0321773555', '1800225555']),
  OfficialSender('RHB', 'bank', senderIds: ['RHB', 'RHB Bank'], hotlines: ['0392068118']),
  OfficialSender('Hong Leong Bank', 'bank', senderIds: ['Hong Leong Bank', 'HLB', 'Hong Leong'], hotlines: ['0376268899']),
  OfficialSender('AmBank', 'bank', senderIds: ['AmBank', 'AmOnline'], hotlines: ['0321788888']),
  OfficialSender('Bank Islam', 'bank', senderIds: ['Bank Islam', 'BIMB'], hotlines: ['0326900900']),
  OfficialSender('BSN', 'bank', senderIds: ['BSN', 'myBSN'], hotlines: ['1300881900']),
  OfficialSender("Touch 'n Go", 'e-wallet', senderIds: ["Touch 'n Go", 'TNG', 'TNG Digital', 'TNGD'], hotlines: ['0350223888']),
  OfficialSender('Pos Malaysia', 'courier', senderIds: ['Pos Malaysia', 'POS', 'PosLaju', 'Pos Laju'], hotlines: ['1300300300']),
  OfficialSender('J&T Express', 'courier', senderIds: ['J&T', 'J&T Express', 'JT Express']),
  OfficialSender('LHDN', 'agency', senderIds: ['LHDN', 'HASiL', 'LHDNM'], hotlines: ['0389111000']),
  OfficialSender('JPJ', 'agency', senderIds: ['JPJ']),
  OfficialSender('KWSP', 'agency', senderIds: ['KWSP', 'EPF'], hotlines: ['0389226000']),
  OfficialSender('PDRM', 'agency', senderIds: ['PDRM']),
];

String _normName(String s) => s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9&]"), '');

String _normPhone(String s) {
  var d = s.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('60')) d = '0${d.substring(2)}';
  return d;
}

/// The official sender a message's sender matches, and how ("sender name",
/// "short code" or "customer care number").
(OfficialSender, String)? matchSender(String? sender) {
  if (sender == null || sender.trim().isEmpty) return null;
  final name = _normName(sender);
  final phone = _normPhone(sender);
  final looksNumeric = RegExp(r'^[\d\s+()-]+$').hasMatch(sender.trim());
  for (final o in officialSenders) {
    if (looksNumeric) {
      if (o.shortCodes.contains(phone)) return (o, 'short code');
      if (phone.length >= 9 && o.hotlines.contains(phone)) return (o, 'customer care number');
    } else if (o.senderIds.any((id) => _normName(id) == name)) {
      return (o, 'sender name');
    }
  }
  return null;
}

final _courier = r'(pos ?laju|pos malaysia|j&t|jnt|dhl|ninja ?van|gdex|city-?link|spx|shopee express|lazada logistics|flash express)';
final _deliveryTemplate = RegExp(
  '\\b$_courier\\b'
  r'[\s\S]{0,160}'
  r'\b(out for delivery|has been delivered|was delivered|delivered to|in transit|arriving (today|tomorrow)|will be delivered|has been picked up|ready for (collection|pick-?up)|sedang dihantar|telah dihantar|telah diterima)\b',
  caseSensitive: false,
);
// UPU S10 tracking number used by Pos Malaysia (e.g. EN123456789MY) or a long
// courier consignment number.
final _trackingNo = RegExp(r'\b[A-Z]{2}\d{9}MY\b|\b(tracking|consignment|parcel|item|awb)( no\.?| number| #)?:?\s*[A-Z0-9]{8,}\b', caseSensitive: false);

final _bankNames = r'(maybank|cimb|public ?bank|pbe|rhb|hong leong|hlb|ambank|bank islam|bsn|affin|alliance|ocbc|uob|hsbc|bank rakyat|agrobank|touch ?.?n ?go|tng)';
final _bankAlert = RegExp(
  '\\b$_bankNames\\b'
  r'[\s\S]{0,80}'
  r'\b(debit(ed)?|credit(ed)?|purchase|transaction|payment|withdrawal|card ending|ending( with)? \d{4}|a/c|acct|duitnow|ibg|transfer)\b'
  r'[\s\S]{0,80}'
  r'\bRM ?\d[\d,]*\.\d{2}\b',
  caseSensitive: false,
);
final _alertTail = RegExp(
  r"\b(if (this was not you|you did not|not done by you|unauthori[sz]ed)|bukan anda|call (us )?(at )?1[- ]?[38]00|\d{2}/\d{2}(/\d{2,4})?\b|\d{1,2}:\d{2})",
  caseSensitive: false,
);
final _rm0 = RegExp(r'^\s*RM ?0(\.00)?\b', caseSensitive: false);

/// Legitimacy evidence beyond the wording rules in cues.dart: an official
/// sender, and known-good templates for delivery updates and bank alerts.
/// [prior] are the findings so far, so a template never vouches for a message
/// that asks for codes, money or has a risky link.
List<Finding> legitimacyFindings(String text, {String? sender, required List<UrlReport> urls, required List<Finding> prior}) {
  final out = <Finding>[];
  final riskyLink = urls.any((u) => !u.official);
  final asksForSecrets = prior.any((f) => f.isRisk && (f.title == 'Wants your code' || f.category == CueCategory.aiManipulation));
  final asksToPay = prior.any((f) => f.isRisk && (f.title == 'Pay to get your money' || f.title.contains('safe account') || f.title == 'Parcel problem'));
  final heavyRisk = prior.where((f) => f.isRisk).fold<int>(0, (a, f) => a + f.weight) >= 40;
  final clean = !riskyLink && !asksForSecrets && !asksToPay && !heavyRisk;

  final m = matchSender(sender);
  if (m != null && clean) {
    final (o, how) = m;
    final strong = how != 'sender name';
    out.add(Finding(
      category: CueCategory.legitimacy,
      title: 'Sent from ${o.brand}\'s official $how',
      explanation: strong
          ? 'The sender, $sender, is listed as ${o.brand}\'s official $how, and the message has no risky link.'
          : 'The sender name matches what ${o.brand} uses, and the message has no risky link. Names can be faked, so this only counts because nothing else looks wrong.',
      weight: strong ? -10 : -5,
      tool: 'Official sender list',
    ));
  }

  if (clean) {
    final d = _deliveryTemplate.firstMatch(text);
    if (d != null && !RegExp(r'\b(fee|caj|bayar|pay|unpaid|customs duty|cukai)\b', caseSensitive: false).hasMatch(text)) {
      out.add(Finding(
        category: CueCategory.legitimacy,
        title: 'Standard delivery update',
        explanation: _trackingNo.hasMatch(text)
            ? 'This matches the usual courier update: a tracking number and a delivery status, with no fee and no link to pay.'
            : 'This matches the usual courier update: a delivery status with no fee and no link to pay.',
        weight: _trackingNo.hasMatch(text) ? -10 : -6,
        start: d.start,
        end: d.end,
        tool: 'Known-good templates',
      ));
    }
    final b = _bankAlert.firstMatch(text);
    if (b != null && _alertTail.hasMatch(text) && !RegExp(r'\b(click|klik|log ?in|tekan)\b', caseSensitive: false).hasMatch(text)) {
      out.add(Finding(
        category: CueCategory.legitimacy,
        title: 'Standard bank transaction alert',
        explanation: 'This reads like an automatic alert for a transaction on your account: bank name, amount and time, with no link and no request.',
        weight: -8,
        start: b.start,
        end: b.end,
        tool: 'Known-good templates',
      ));
    }
    final r = _rm0.firstMatch(text);
    if (r != null && out.isNotEmpty) {
      out.add(Finding(
        category: CueCategory.legitimacy,
        title: 'Follows the official SMS format',
        explanation: 'Business SMS in Malaysia start with "RM0", which this message does. Scammers can copy it, so it only adds a little.',
        weight: -3,
        start: r.start,
        end: r.end,
        tool: 'Known-good templates',
      ));
    }
  }
  return out;
}

/// "Looks legitimate" headline with reasons, when the legitimacy evidence
/// clearly outweighs any warning sign. Null when it does not.
String? legitimateHeadline(List<Finding> findings) {
  final legit = findings.where((f) => !f.isRisk).toList()..sort((a, b) => a.weight.compareTo(b.weight));
  final legitSum = legit.fold<int>(0, (a, f) => a - f.weight);
  final riskSum = findings.where((f) => f.isRisk).fold<int>(0, (a, f) => a + f.weight);
  if (legit.isEmpty || legitSum < 10 || riskSum * 2 > legitSum) return null;
  final reasons = legit.map((f) => f.title.toLowerCase()).toSet().take(3).toList();
  final joined = reasons.length == 1
      ? reasons.first
      : '${reasons.sublist(0, reasons.length - 1).join(', ')} and ${reasons.last}';
  return 'Looks legitimate: ${joined[0].toUpperCase()}${joined.substring(1)}.';
}

/// Is [host] an official domain of [brand]?
bool isOfficialFor(String host, String brand) => officialBrandFor(host.toLowerCase()) == brand;
