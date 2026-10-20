import 'package:flutter/material.dart';

import '../../engine/models.dart';

// Small, testable helpers that turn an Investigation into the short labels
// the Check tab and the result screen show.

String sourceLabel(Artefact a) => switch (a.source) {
  Source.paste => switch (a.kind) {
    'url' => 'Link',
    'email' => 'Email',
    _ => 'Pasted text',
  },
  Source.whatsappWeb => 'WhatsApp',
  Source.telegramWeb => 'Telegram',
  Source.telegramBot => 'Telegram bot',
  Source.screenshot => 'Screenshot',
  Source.qr => 'QR code',
  Source.chatExport => 'Chat export',
  Source.questionnaire => 'Questions',
  Source.document => 'Document',
  Source.voice => 'Voice note',
  Source.video => 'Video',
  Source.apk => 'App file',
  Source.email => 'Email',
  Source.share => 'Shared to Kantoi',
};

IconData sourceIcon(Artefact a) => switch (a.source) {
  Source.paste => switch (a.kind) {
    'url' => Icons.link_rounded,
    'email' => Icons.mail_outline_rounded,
    _ => Icons.sms_outlined,
  },
  Source.whatsappWeb || Source.chatExport => Icons.chat_outlined,
  Source.telegramWeb || Source.telegramBot => Icons.send_outlined,
  Source.screenshot => Icons.image_outlined,
  Source.qr => Icons.qr_code_2_rounded,
  Source.questionnaire => Icons.quiz_outlined,
  Source.document => Icons.description_outlined,
  Source.voice => Icons.mic_none_rounded,
  Source.video => Icons.videocam_outlined,
  Source.apk => Icons.android_rounded,
  Source.email => Icons.mail_outline_rounded,
  Source.share => Icons.ios_share_rounded,
};

/// The most telling thing to show next to the source: the link's site, a
/// phone number, or who sent it.
String? sourceDetail(Investigation inv) {
  if (inv.urls.isNotEmpty) return inv.urls.first.host;
  final e = inv.artefact.entities;
  final url = e.where((x) => x.type == EntityType.url).firstOrNull;
  if (url != null) return Uri.tryParse(url.value.contains('://') ? url.value : 'https://${url.value}')?.host ?? url.value;
  final phone = e.where((x) => x.type == EntityType.phone).firstOrNull;
  if (phone != null) return phone.value;
  return inv.artefact.sender;
}

/// One line on why: the strongest warning sign, or the strongest sign it is
/// genuine for a safe result.
String shortReason(Investigation inv) {
  final risky = inv.verdict.level != RiskLevel.safe;
  final list = inv.findings.where((f) => f.isRisk == risky).toList()..sort((a, b) => b.weight.abs().compareTo(a.weight.abs()));
  if (list.isNotEmpty) return list.first.title;
  return risky ? inv.verdict.headline : 'No scam signs found';
}

/// What the Trace tab should look into: the first link, else a phone
/// number, else the message itself.
String traceTarget(Investigation inv) {
  if (inv.urls.isNotEmpty) return inv.urls.first.input;
  final e = inv.artefact.entities;
  final url = e.where((x) => x.type == EntityType.url).firstOrNull;
  if (url != null) return url.value;
  final phone = e.where((x) => x.type == EntityType.phone).firstOrNull;
  if (phone != null) return phone.value;
  return inv.artefact.text.trim();
}

String timeAgo(DateTime t, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  return '${t.day}/${t.month}/${t.year}';
}

/// Plain words for how sure Kantoi is. Never claims certainty.
String confidenceWords(int confidence) {
  if (confidence >= 80) return 'Fairly sure';
  if (confidence >= 55) return 'Somewhat sure';
  return 'Not very sure';
}
