import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../engine/models.dart';
import '../engine/redaction.dart';
import '../engine/report.dart';
import '../engine/taxonomy.dart';

/// Where the scammer reached the user.
enum ContactChannel { whatsapp, telegram, sms, email, phoneCall, inApp, inPerson }

String contactChannelLabel(ContactChannel c) => switch (c) {
      ContactChannel.whatsapp => 'WhatsApp',
      ContactChannel.telegram => 'Telegram',
      ContactChannel.sms => 'SMS',
      ContactChannel.email => 'Email',
      ContactChannel.phoneCall => 'Phone call',
      ContactChannel.inApp => 'In-app chat',
      ContactChannel.inPerson => 'In person',
    };

enum PaymentMethod { bankTransfer, card, ewallet, crypto, giftCard, cash, other }

String paymentLabel(PaymentMethod p) => switch (p) {
      PaymentMethod.bankTransfer => 'Bank transfer',
      PaymentMethod.card => 'Credit/debit card',
      PaymentMethod.ewallet => 'E-wallet / DuitNow / P2P app',
      PaymentMethod.crypto => 'Crypto',
      PaymentMethod.giftCard => 'Gift card',
      PaymentMethod.cash => 'Cash',
      PaymentMethod.other => 'Other',
    };

const currencies = ['MYR', 'USD', 'SGD', 'EUR', 'GBP', 'CNY', 'IDR', 'THB', 'BTC', 'ETH', 'USDT', 'Other'];

/// Crypto amounts need more decimals than cash.
int decimalsFor(String currency) => switch (currency) {
      'BTC' || 'ETH' => 8,
      'IDR' => 0,
      _ => 2,
    };

enum IdentifierType { phone, email, handle, bankAccount, wallet, other }

String identifierLabel(IdentifierType t) => switch (t) {
      IdentifierType.phone => 'Phone number',
      IdentifierType.email => 'Email',
      IdentifierType.handle => 'Social username or profile',
      IdentifierType.bankAccount => 'Bank account',
      IdentifierType.wallet => 'Crypto wallet',
      IdentifierType.other => 'Other',
    };

class AttackerId {
  final IdentifierType type;
  final String value;
  const AttackerId(this.type, this.value);

  /// Lower case, digits only for numbers, so the same scammer matches across reports.
  String get normalised {
    final v = value.trim().toLowerCase();
    return switch (type) {
      IdentifierType.phone => _normalisePhone(v),
      IdentifierType.bankAccount => v.replaceAll(RegExp(r'\D'), ''),
      IdentifierType.handle => v.replaceFirst(RegExp(r'^@'), ''),
      _ => v,
    };
  }

  /// Safe to show anyone: 012-***-4567, j***@gmail.com, @ab***.
  String get masked {
    final v = value.trim();
    switch (type) {
      case IdentifierType.email:
        final at = v.indexOf('@');
        return at > 0 ? '${v[0]}***${v.substring(at)}' : '***';
      case IdentifierType.phone || IdentifierType.bankAccount || IdentifierType.wallet:
        final d = type == IdentifierType.wallet ? v : (type == IdentifierType.phone ? _normalisePhone(v) : v.replaceAll(RegExp(r'\D'), ''));
        if (d.length < 7) return '***';
        return '${d.substring(0, 3)}-***-${d.substring(d.length - 4)}';
      case IdentifierType.handle || IdentifierType.other:
        final h = v.replaceFirst(RegExp(r'^@'), '');
        return h.length <= 2 ? '@***' : '@${h.substring(0, 2)}***';
    }
  }

  Map<String, dynamic> toJson() => {'type': type.name, 'value': value};
  factory AttackerId.fromJson(Map<String, dynamic> j) =>
      AttackerId(IdentifierType.values.firstWhere((t) => t.name == j['type'], orElse: () => IdentifierType.other), j['value'] as String? ?? '');
}

String _normalisePhone(String v) {
  var d = v.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('60')) d = '0${d.substring(2)}';
  return d;
}

/// A one-way code for an identifier, so the shared database can count
/// reports of one number without storing the number. Peppered so a plain
/// hash table of all numbers does not reverse it; the server will re-key it
/// with a secret once Firebase is live.
String identifierCode(AttackerId id) =>
    sha256.convert(utf8.encode('kantoi-v1|${id.type.name}|${id.normalised}')).toString().substring(0, 32);

enum ReportStatus { draft, saved, sent }

/// One scam report: what the user tells Kantoi, pre-filled from a check when
/// there is one. Lives on the phone; only [sharedPayload] ever leaves it.
class ScamReport {
  final String id;
  String? kind; // taxonomy code
  ContactChannel? channel;
  List<AttackerId> attackers;
  String impersonated;
  List<String> links;
  bool? lostMoney;
  /// In the currency's smallest unit (sen for MYR), so totals never round.
  int? amountMinor;
  String currency;
  PaymentMethod? payment;
  String transactionRef;
  /// Paths of evidence images on this phone (already redacted).
  List<String> screenshots;
  String description;
  DateTime? incidentAt;
  bool reportedToPolice;
  bool reportedToBank;
  bool reportedTo997;
  String officialRef;
  /// The user agreed (by the sign-up disclaimer, and not turned off here)
  /// to share masked details with Kantoi's scam database.
  bool shareWithKantoi;
  ReportStatus status;
  DateTime created;
  DateTime updated;
  /// The check this report came from, if any.
  String? fromCheck;

  ScamReport({
    required this.id,
    this.kind,
    this.channel,
    List<AttackerId>? attackers,
    this.impersonated = '',
    List<String>? links,
    this.lostMoney,
    this.amountMinor,
    this.currency = 'MYR',
    this.payment,
    this.transactionRef = '',
    List<String>? screenshots,
    this.description = '',
    this.incidentAt,
    this.reportedToPolice = false,
    this.reportedToBank = false,
    this.reportedTo997 = false,
    this.officialRef = '',
    this.shareWithKantoi = true,
    this.status = ReportStatus.draft,
    DateTime? created,
    DateTime? updated,
    this.fromCheck,
  })  : attackers = attackers ?? [],
        links = links ?? [],
        screenshots = screenshots ?? [],
        created = created ?? DateTime.now(),
        updated = updated ?? created ?? DateTime.now();

  ScamKind? get scamKind => kindByCode(kind);

  /// Title for lists: "Task & employment scam · 012-***-4567".
  String get title {
    final k = scamKind?.label ?? 'Scam report';
    return attackers.isEmpty ? k : '$k · ${attackers.first.masked}';
  }

  /// "RM 3,500.00", "0.05000000 BTC".
  String get amountText {
    final a = amountMinor;
    if (a == null) return '';
    final dp = decimalsFor(currency);
    final whole = dp == 0 ? a : a ~/ _pow10(dp);
    final frac = dp == 0 ? '' : '.${(a % _pow10(dp)).toString().padLeft(dp, '0')}';
    final w = whole.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return currency == 'MYR' ? 'RM $w$frac' : '$w$frac $currency';
  }

  /// Parses what the user typed ("3,500", "3500.5") into [amountMinor].
  static int? parseAmount(String typed, String currency) {
    final t = typed.replaceAll(RegExp(r'[^\d.]'), '');
    if (t.isEmpty) return null;
    final parts = t.split('.');
    if (parts.length > 2) return null;
    final dp = decimalsFor(currency);
    final whole = int.tryParse(parts[0].isEmpty ? '0' : parts[0]);
    if (whole == null) return null;
    var frac = parts.length == 2 ? parts[1] : '';
    if (frac.length > dp) frac = frac.substring(0, dp);
    return whole * _pow10(dp) + (frac.isEmpty ? 0 : int.parse(frac.padRight(dp, '0')));
  }

  /// What is still missing before the report is worth sending.
  List<String> get missing => [
        if (kind == null) 'What kind of scam',
        if (channel == null) 'How they contacted you',
        if (attackers.isEmpty && links.isEmpty) 'Their number, account, profile or link',
        if (lostMoney == null) 'Whether you lost money',
        if (lostMoney == true && amountMinor == null) 'How much you lost',
      ];

  bool get ready => missing.isEmpty;

  /// The old report generator's situation, so its PDF and per-channel
  /// packs keep working.
  Situation get situation {
    if (lostMoney == true) return Situation.lostMoney;
    if (kind == 'cyber.sim_otp' || kind == 'cyber.account_takeover') return Situation.sharedDetails;
    if (kind == 'cyber.malware') return Situation.installedApp;
    return Situation.onlyReceived;
  }

  /// The old generator's details, filled from this report.
  ReportDetails toDetails() {
    final d = ReportDetails()
      ..amount = amountText
      ..when = incidentAt == null ? '' : _fmt(incidentAt!)
      ..transactionRef = transactionRef
      ..contactMethod = channel == null ? '' : contactChannelLabel(channel!)
      ..scammerContact = attackers.map((a) => a.value).join(', ')
      ..story = description;
    final acct = attackers.where((a) => a.type == IdentifierType.bankAccount || a.type == IdentifierType.wallet).map((a) => a.value);
    d.paidTo = acct.join(', ');
    return d;
  }

  /// The only thing that leaves the phone for Kantoi's scam database:
  /// no names, no message text, no screenshots, no transaction numbers.
  /// Identifiers become one-way codes plus a masked form; links keep only
  /// their website name.
  Map<String, dynamic> sharedPayload({String appVersion = '1.2.0'}) => {
        'v': 1,
        'kind': kind,
        'group': scamKind?.group.name,
        'channel': channel?.name,
        'identifiers': [
          for (final a in attackers) {'type': a.type.name, 'code': identifierCode(a), 'masked': a.masked}
        ],
        'domains': {for (final l in links) ?_domain(l)}.toList(),
        'impersonated': impersonated.trim().isEmpty ? null : impersonated.trim(),
        'lostMoney': lostMoney,
        'amountMinor': lostMoney == true ? amountMinor : null,
        'currency': lostMoney == true ? currency : null,
        'payment': payment?.name,
        // Day only: enough to see a campaign, not enough to pin a person.
        'incidentDay': incidentAt == null ? null : _day(incidentAt!),
        'reportedOfficially': reportedToPolice || reportedToBank || reportedTo997,
        'appVersion': appVersion,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'channel': channel?.name,
        'attackers': attackers.map((a) => a.toJson()).toList(),
        'impersonated': impersonated,
        'links': links,
        'lostMoney': lostMoney,
        'amountMinor': amountMinor,
        'currency': currency,
        'payment': payment?.name,
        'transactionRef': transactionRef,
        'screenshots': screenshots,
        'description': description,
        'incidentAt': incidentAt?.toIso8601String(),
        'reportedToPolice': reportedToPolice,
        'reportedToBank': reportedToBank,
        'reportedTo997': reportedTo997,
        'officialRef': officialRef,
        'shareWithKantoi': shareWithKantoi,
        'status': status.name,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
        'fromCheck': fromCheck,
      };

  factory ScamReport.fromJson(Map<String, dynamic> j) => ScamReport(
        id: j['id'] as String,
        kind: j['kind'] as String?,
        channel: _enum(ContactChannel.values, j['channel']),
        attackers: [for (final a in (j['attackers'] as List? ?? const [])) AttackerId.fromJson((a as Map).cast<String, dynamic>())],
        impersonated: j['impersonated'] as String? ?? '',
        links: [for (final l in (j['links'] as List? ?? const [])) '$l'],
        lostMoney: j['lostMoney'] as bool?,
        amountMinor: j['amountMinor'] as int?,
        currency: j['currency'] as String? ?? 'MYR',
        payment: _enum(PaymentMethod.values, j['payment']),
        transactionRef: j['transactionRef'] as String? ?? '',
        screenshots: [for (final s in (j['screenshots'] as List? ?? const [])) '$s'],
        description: j['description'] as String? ?? '',
        incidentAt: DateTime.tryParse(j['incidentAt'] as String? ?? ''),
        reportedToPolice: j['reportedToPolice'] as bool? ?? false,
        reportedToBank: j['reportedToBank'] as bool? ?? false,
        reportedTo997: j['reportedTo997'] as bool? ?? false,
        officialRef: j['officialRef'] as String? ?? '',
        shareWithKantoi: j['shareWithKantoi'] as bool? ?? true,
        status: _enum(ReportStatus.values, j['status']) ?? ReportStatus.draft,
        created: DateTime.tryParse(j['created'] as String? ?? ''),
        updated: DateTime.tryParse(j['updated'] as String? ?? ''),
        fromCheck: j['fromCheck'] as String?,
      );

  /// A new report pre-filled from a finished check: kind, channel, the
  /// scammer's numbers and accounts, links, who they pretend to be, and a
  /// first description the user can edit.
  factory ScamReport.fromCheck(Investigation inv, {required String id, DateTime? now}) {
    final ents = inv.artefact.entities;
    final ids = <AttackerId>[];
    void add(IdentifierType t, String v) {
      final a = AttackerId(t, v);
      if (v.trim().isNotEmpty && !ids.any((x) => x.type == t && x.normalised == a.normalised)) ids.add(a);
    }

    final sender = inv.artefact.sender;
    if (sender != null && RegExp(r'\d{7,}').hasMatch(sender.replaceAll(RegExp(r'[\s-]'), ''))) add(IdentifierType.phone, sender);
    for (final e in ents) {
      switch (e.type) {
        case EntityType.phone:
          add(IdentifierType.phone, e.value);
        case EntityType.email:
          add(IdentifierType.email, e.value);
        case EntityType.handle:
          add(IdentifierType.handle, e.value);
        case EntityType.bankAccount || EntityType.ewallet:
          add(IdentifierType.bankAccount, e.value);
        case EntityType.cryptoWallet:
          add(IdentifierType.wallet, e.value);
        default:
          break;
      }
    }
    final brand = ents.where((e) => e.type == EntityType.brand).map((e) => e.value).firstOrNull ??
        inv.urls.map((u) => u.imitates).whereType<String>().firstOrNull ??
        '';
    final signs = inv.findings.where((f) => f.isRisk).map((f) => f.title.toLowerCase()).toSet().take(3).toList();
    final pii = findPii(inv.artefact.text);
    final excerpt = redact(inv.artefact.text, pii);
    return ScamReport(
      id: id,
      kind: kindOf(inv)?.code,
      channel: channelFor(inv.artefact.source, inv.artefact.meta['app']),
      attackers: ids,
      impersonated: brand,
      links: [for (final e in ents) if (e.type == EntityType.url) e.value],
      incidentAt: inv.artefact.receivedAt,
      description: [
        'Kantoi judged this "${inv.verdict.scamType}" (${inv.verdict.score}/100).',
        if (signs.isNotEmpty) 'Warning signs: ${signs.join(', ')}.',
        if (excerpt.trim().isNotEmpty) 'Message: "${excerpt.length > 400 ? '${excerpt.substring(0, 400)}…' : excerpt}"',
      ].join(' '),
      fromCheck: inv.artefact.receivedAt.toIso8601String(),
      created: now,
    );
  }
}

/// The channel a check came in on, from its source or the app package.
ContactChannel? channelFor(Source source, [String? app]) {
  final a = app ?? '';
  if (a.contains('whatsapp')) return ContactChannel.whatsapp;
  if (a.contains('telegram') || a.contains('challegram')) return ContactChannel.telegram;
  if (a.contains('messaging') || a.contains('mms') || a.contains('message')) return ContactChannel.sms;
  if (a.contains('mail') || a.contains('outlook') || a.contains('.gm')) return ContactChannel.email;
  if (a.isNotEmpty) return ContactChannel.inApp;
  return switch (source) {
    Source.whatsappWeb || Source.chatExport => ContactChannel.whatsapp,
    Source.telegramWeb || Source.telegramBot => ContactChannel.telegram,
    Source.email => ContactChannel.email,
    Source.voice => ContactChannel.phoneCall,
    _ => null,
  };
}

T? _enum<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

String? _domain(String link) {
  var l = link.trim();
  if (!l.contains('://')) l = 'http://$l';
  final h = Uri.tryParse(l)?.host.toLowerCase();
  if (h == null || h.isEmpty) return null;
  return h.startsWith('www.') ? h.substring(4) : h;
}

String _day(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

String _fmt(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}
