import 'models.dart';

enum Situation { lostMoney, sharedDetails, installedApp, onlyReceived }

const situationLabels = {
  Situation.lostMoney: 'I lost money',
  Situation.sharedDetails: 'I gave my login, OTP or card details',
  Situation.installedApp: 'I installed an app they sent',
  Situation.onlyReceived: 'I only received it',
};

enum ChannelKind { call, web, inApp }

class Channel {
  final String id;
  final String name;
  final String why;
  final ChannelKind kind;
  final String? target; // phone number or URL
  final List<String> steps;
  const Channel(this.id, this.name, this.why, this.kind, {this.target, this.steps = const []});
}

const nsrc = Channel('nsrc', 'National Scam Response Centre (NSRC) 997',
    'Call within minutes of a transfer. NSRC works with banks to trace and freeze stolen money.', ChannelKind.call,
    target: '997', steps: ['Call 997.', 'Read out the call script below.', 'Write down the case reference they give you.']);
const bank = Channel('bank', 'Your bank',
    'Ask the bank to block your card or account and flag the transaction as fraud.', ChannelKind.call,
    steps: ['Call the number on the back of your card or in your official banking app.', 'Ask them to block the account and dispute the transaction.', 'Change your banking password from the official app.']);
const police = Channel('police', 'Police report (PDRM)',
    'A police report is needed for bank disputes and insurance. File it within 24 hours.', ChannelKind.web,
    target: 'https://ereporting.rmp.gov.my',
    steps: ['Go to the nearest police station, or start online.', 'Bring the PDF report and screenshots from Kantoi.']);
const semakMule = Channel('semakmule', 'Check the account on Semak Mule',
    'PDRM\'s public check shows whether a bank account or phone number has been reported before.', ChannelKind.web,
    target: 'https://semakmule.rmp.gov.my', steps: ['Enter the account or phone number the scammer gave you.']);
const mcmc = Channel('mcmc', 'MCMC complaint',
    'For scam SMS, calls and websites, so the number or site can be blocked.', ChannelKind.web,
    target: 'https://aduan.mcmc.gov.my', steps: ['Choose a complaint about scam SMS, calls or websites.', 'Paste the report text from Kantoi.']);
const whatsapp = Channel('whatsapp', 'Report and block on WhatsApp',
    'Stops the account reaching you and helps WhatsApp ban it.', ChannelKind.inApp,
    steps: ['Open the chat.', 'Tap the contact name, then "Report".', 'Choose "Block and report".']);
const telegram = Channel('telegram', 'Report on Telegram',
    'Telegram removes scam accounts reported to its official @notoscam account.', ChannelKind.inApp,
    target: 'https://t.me/notoscam', steps: ['Open the chat and tap "Report".', 'Or forward the evidence to @notoscam.']);

const facebook = Channel('facebook', 'Report on Facebook or Messenger',
    'Facebook removes scam profiles and pages that are reported, and blocking stops them reaching you.', ChannelKind.inApp,
    steps: [
      'On their profile, tap ⋯ (More) under their name, then "Report profile".',
      'Choose the reason about a scam or fraud, then follow the steps to submit.',
      'In Messenger: open the chat, tap their name, tap "Report", then choose scam or fraud.',
      'Block them from the same menu.',
    ]);
const instagram = Channel('instagram', 'Report on Instagram',
    'Instagram removes scam and fake accounts that are reported.', ChannelKind.inApp,
    steps: [
      'Open their profile and tap ⋯ at the top right.',
      'Tap "Report", then choose the reason about a scam or fraud (or "Pretending to be someone" for a fake account).',
      'For a direct message: press and hold the message, then tap "Report".',
      'Block them from the same menu.',
    ]);
const tiktok = Channel('tiktok', 'Report on TikTok',
    'TikTok removes accounts reported for frauds and scams.', ChannelKind.inApp,
    steps: [
      'Open their profile and tap the share arrow at the top right.',
      'Tap "Report", then "Report account", and choose "Frauds and scams".',
      'For a direct message: press and hold the message, then tap "Report".',
      'Block them from their profile.',
    ]);

/// Where the scammer contacted the user, which decides the platform channel.
enum ContactPlatform { whatsapp, telegram, facebook, instagram, tiktok, smsOrCall, other }

const platformLabels = {
  ContactPlatform.whatsapp: 'WhatsApp',
  ContactPlatform.telegram: 'Telegram',
  ContactPlatform.facebook: 'Facebook or Messenger',
  ContactPlatform.instagram: 'Instagram',
  ContactPlatform.tiktok: 'TikTok',
  ContactPlatform.smsOrCall: 'SMS or phone call',
  ContactPlatform.other: 'Somewhere else',
};

ContactPlatform platformFor(Source? source) => switch (source) {
      Source.telegramWeb => ContactPlatform.telegram,
      Source.whatsappWeb || Source.chatExport => ContactPlatform.whatsapp,
      _ => ContactPlatform.whatsapp,
    };

Channel? platformChannel(ContactPlatform p) => switch (p) {
      ContactPlatform.whatsapp => whatsapp,
      ContactPlatform.telegram => telegram,
      ContactPlatform.facebook => facebook,
      ContactPlatform.instagram => instagram,
      ContactPlatform.tiktok => tiktok,
      ContactPlatform.smsOrCall => mcmc,
      ContactPlatform.other => null,
    };

/// Channels in the order the victim should use them.
List<Channel> channelsFor(Situation s, {Source? source, ContactPlatform? platform}) {
  final p = platformChannel(platform ?? platformFor(source));
  final out = switch (s) {
    Situation.lostMoney => [nsrc, bank, police, semakMule, ?p],
    Situation.sharedDetails => [bank, nsrc, police, ?p],
    Situation.installedApp => [bank, nsrc, police],
    Situation.onlyReceived => [?p, mcmc, semakMule],
  };
  // MCMC can appear twice when the platform is SMS; keep the first.
  final seen = <String>{};
  return out.where((c) => seen.add(c.id)).toList();
}

class ReportDetails {
  String amount = '';
  String when = '';
  String transactionRef = '';
  String paidTo = '';
  String paidFromBank = '';
  String contactMethod = '';
  String scammerBank = '';

  /// The scammer's number, profile or link, typed in when no message was
  /// checked first.
  String scammerContact = '';

  /// What happened, in the user's own words.
  String story = '';
}

/// The four places a victim reports to, as chips on the report page.
const authorities = [police, nsrc, bank, mcmc];

String authorityLabel(Channel c) => switch (c.id) {
      'police' => 'Police',
      'nsrc' => 'NSRC 997',
      'bank' => 'Bank',
      'mcmc' => 'MCMC',
      _ => c.name,
    };

/// One field of a report form, with a copy button in the UI.
class PackField {
  final String label;
  final String value;
  const PackField(this.label, this.value);
}

const _situationSentence = {
  Situation.lostMoney: 'I lost money to this scam.',
  Situation.sharedDetails: 'I gave my login, OTP or card details to them.',
  Situation.installedApp: 'I installed an app they sent me.',
  Situation.onlyReceived: 'I did not pay or share any details.',
};

/// A short description in plain sentences, for the "description" box of any
/// report form. [scamText] is already redacted.
String incidentDescription(Investigation? inv, ReportDetails d, Situation s) {
  final how = d.contactMethod.isEmpty ? '' : ' on ${d.contactMethod}';
  final signs = (inv?.findings ?? const <Finding>[]).where((f) => f.isRisk).map((f) => f.title.toLowerCase()).toSet().take(3).toList();
  final what = inv == null ? 'a scam' : 'what looks like a ${inv.verdict.scamType.toLowerCase()}';
  final b = StringBuffer('${d.when.isEmpty ? 'Recently' : 'On ${d.when}'}, I was contacted$how by someone '
      'running $what. ${_situationSentence[s]}');
  if (s == Situation.lostMoney && (d.amount.isNotEmpty || d.paidTo.isNotEmpty)) {
    b.write(' I transferred ${d.amount.isEmpty ? 'money' : d.amount}');
    if (d.paidFromBank.isNotEmpty) b.write(' from my ${d.paidFromBank} account');
    if (d.paidTo.isNotEmpty) b.write(' to account ${d.paidTo}');
    if (d.scammerBank.isNotEmpty) b.write(' (${d.scammerBank})');
    b.write('.');
    if (d.transactionRef.isNotEmpty) b.write(' The transaction reference is ${d.transactionRef}.');
  }
  if (signs.isNotEmpty) b.write(' Warning signs: ${signs.join(', ')}.');
  if (d.story.trim().isNotEmpty) b.write(' In my words: ${d.story.trim()}');
  return b.toString();
}

/// The fields each channel's form asks for, in the order it asks for them.
/// Empty fields are left out.
List<PackField> reportPack(Channel c, Investigation? inv, ReportDetails d, Situation s, String scamText) {
  final ents = inv?.artefact.entities ?? const <Entity>[];
  String list(EntityType t) => ents.where((e) => e.type == t).map((e) => e.value).toSet().join(', ');
  final account = d.paidTo.isNotEmpty ? d.paidTo : list(EntityType.bankAccount);
  final profile = [d.scammerContact.trim(), list(EntityType.handle), list(EntityType.phone), list(EntityType.url)]
      .where((x) => x.isNotEmpty)
      .join(', ');
  final f = <String, String>{
    'amount': d.amount,
    'date': d.when,
    'bank': d.paidFromBank,
    'account': account,
    'scammerBank': d.scammerBank,
    'reference': d.transactionRef,
    'phone': [d.scammerContact.trim(), list(EntityType.phone)].where((x) => x.isNotEmpty).join(', '),
    'link': list(EntityType.url),
    'profile': profile,
    'how': d.contactMethod,
    'description': incidentDescription(inv, d, s),
    'message': scamText,
  };
  const labels = {
    'amount': 'Amount',
    'date': 'Date and time',
    'bank': 'Your bank',
    'account': "Scammer's account number",
    'scammerBank': "Scammer's bank",
    'reference': 'Transaction reference',
    'phone': "Scammer's phone number",
    'link': 'Scam link',
    'profile': 'Their profile, number or link',
    'how': 'How they contacted you',
    'description': 'Description',
    'message': 'The scam message (your details hidden)',
  };
  final order = switch (c.id) {
    'nsrc' || 'bank' => ['amount', 'date', 'bank', 'account', 'scammerBank', 'reference', 'description'],
    'police' => ['date', 'how', 'description', 'amount', 'bank', 'account', 'scammerBank', 'reference', 'phone', 'link', 'message'],
    'mcmc' when inv == null => ['phone', 'how', 'date', 'description'],
    'semakmule' => ['account', 'phone'],
    'mcmc' => ['phone', 'link', 'date', 'description', 'message'],
    _ => ['profile', 'description', 'message'],
  };
  return [for (final k in order) if (f[k]!.trim().isNotEmpty) PackField(labels[k]!, f[k]!.trim())];
}

/// The report text shared with every channel. [scamText] is already redacted.
String buildReport(Investigation? inv, String scamText, ReportDetails d, Situation s) {
  final v = inv?.verdict;
  final ents = inv?.artefact.entities ?? const <Entity>[];
  String list(EntityType t) => ents.where((e) => e.type == t).map((e) => e.value).toSet().join(', ');
  final b = StringBuffer()
    ..writeln('SCAM REPORT (prepared with Kantoi)')
    ..writeln('Situation: ${situationLabels[s]}');
  if (v != null) b.writeln('Type: ${v.scamType} (risk ${v.score}/100, ${riskLabel(v.level)})');
  b.writeln();
  if (d.amount.isNotEmpty || d.when.isNotEmpty || d.paidTo.isNotEmpty) {
    b.writeln('TRANSACTION');
    if (d.amount.isNotEmpty) b.writeln('Amount: ${d.amount}');
    if (d.when.isNotEmpty) b.writeln('Date and time: ${d.when}');
    if (d.paidFromBank.isNotEmpty) b.writeln('Paid from: ${d.paidFromBank}');
    if (d.paidTo.isNotEmpty) b.writeln('Paid to (scammer account): ${d.paidTo}');
    if (d.transactionRef.isNotEmpty) b.writeln('Transaction reference: ${d.transactionRef}');
    b.writeln();
  }
  b.writeln('SCAMMER DETAILS');
  for (final (label, t) in [
    ('Phone numbers', EntityType.phone),
    ('Bank accounts', EntityType.bankAccount),
    ('Links', EntityType.url),
    ('Crypto wallets', EntityType.cryptoWallet),
    ('Social handles', EntityType.handle),
    ('Emails', EntityType.email),
  ]) {
    final v = list(t);
    if (v.isNotEmpty) b.writeln('$label: $v');
  }
  if (d.scammerContact.trim().isNotEmpty) b.writeln('Their number, profile or link: ${d.scammerContact.trim()}');
  if (d.contactMethod.isNotEmpty) b.writeln('How they contacted me: ${d.contactMethod}');
  for (final u in (inv?.urls ?? const <UrlReport>[]).where((u) => u.hops.length > 1 || u.imitates != null)) {
    b.writeln('Link ${u.input} leads to ${u.finalUrl}${u.imitates != null ? ' (imitates ${u.imitates})' : ''}'
        '${u.domainAgeDays != null ? ', registered ${u.domainAgeDays} days ago' : ''}');
  }
  if (d.story.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('WHAT HAPPENED')
      ..writeln(d.story.trim());
  }
  if (inv != null) {
    b
      ..writeln()
      ..writeln('WARNING SIGNS FOUND')
      ..writeln(inv.findings.where((f) => f.isRisk).map((f) => '- ${f.title}: ${f.explanation}').toSet().join('\n'));
  }
  if (scamText.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('ORIGINAL MESSAGE (my personal details masked)')
      ..writeln(scamText);
  }
  return b.toString().trim();
}

/// What to say on the phone to NSRC or the bank.
String callScript(ReportDetails d, Investigation? inv) {
  final to = d.paidTo.isNotEmpty
      ? d.paidTo
      : inv?.artefact.entities.where((e) => e.type == EntityType.bankAccount).map((e) => e.value).firstOrNull ?? '[account number]';
  return 'Hello, I want to report a scam and stop a transfer.\n'
      'I transferred ${d.amount.isEmpty ? '[amount]' : d.amount} on ${d.when.isEmpty ? '[date and time]' : d.when}'
      ' from my ${d.paidFromBank.isEmpty ? '[your bank]' : d.paidFromBank} account.\n'
      'It went to account $to.\n'
      '${d.transactionRef.isEmpty ? '' : 'The transaction reference is ${d.transactionRef}.\n'}'
      'It was a ${inv?.verdict.scamType.toLowerCase() ?? 'scam'}. Please help freeze the money and give me a case reference number.';
}
