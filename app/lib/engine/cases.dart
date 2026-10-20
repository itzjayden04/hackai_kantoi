/// Case tracking for victims: the "I already paid" checklist, kept per case on
/// the device so Kantoi can remind the user of what is still open.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';

class CaseStep {
  final String id;
  final String title;
  final String help;
  final String doneLabel;
  final String pendingLabel;
  const CaseStep(this.id, this.title, this.help, this.doneLabel, this.pendingLabel);
}

const caseSteps = [
  CaseStep('call997', 'Call 997 (National Scam Response Centre)', 'Every minute counts. They can work with banks to freeze the money.',
      'Called 997', '997 not called yet'),
  CaseStep('callBank', 'Call your bank', 'Use the number on the back of your card. Ask them to block your account and card.',
      'Called bank', 'Bank not called yet'),
  CaseStep('passwords', 'Change your passwords', 'Banking app first, then email. Log out of all other devices.',
      'Passwords changed', 'Passwords not changed yet'),
  CaseStep('stop', 'Stop all contact with the scammer', 'Do not pay any "recovery fee". Recovery offers are a second scam.',
      'Contact stopped', 'Still in contact'),
  CaseStep('police', 'Make a police report within 24 hours', 'Your bank will ask for it. Kantoi prepares it for you.',
      'Police report made', 'Police report pending'),
  CaseStep('platform', 'Report the account on the app they used', 'So it gets blocked before it reaches someone else.',
      'Account reported', 'Account not reported yet'),
];

class ScamCase {
  final String id;
  final DateTime createdAt;
  String title;
  final Map<String, DateTime> done;
  bool closed;
  DateTime? snoozedUntil;
  ScamCase({required this.id, required this.createdAt, required this.title, Map<String, DateTime>? done, this.closed = false, this.snoozedUntil})
      : done = done ?? {};

  List<CaseStep> get pending => caseSteps.where((s) => !done.containsKey(s.id)).toList();
  bool get isOpen => !closed && pending.isNotEmpty;

  /// For example "Called 997 ✓, Called bank ✓, Police report pending".
  String get summary => [
        for (final s in caseSteps)
          if (done.containsKey(s.id)) '${s.doneLabel} ✓' else s.pendingLabel,
      ].join(', ');

  /// Needs a reminder: open, older than [after], and not snoozed.
  bool needsReminder(DateTime now, {Duration after = const Duration(hours: 3)}) =>
      isOpen && now.difference(createdAt) >= after && (snoozedUntil == null || now.isAfter(snoozedUntil!));

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'title': title,
        'done': done.map((k, v) => MapEntry(k, v.toIso8601String())),
        'closed': closed,
        'snoozedUntil': snoozedUntil?.toIso8601String(),
      };

  factory ScamCase.fromJson(Map<String, dynamic> j) => ScamCase(
        id: j['id'] as String,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        title: j['title'] as String? ?? 'Scam case',
        done: {
          for (final e in ((j['done'] as Map?) ?? {}).entries)
            if (DateTime.tryParse('${e.value}') != null) '${e.key}': DateTime.parse('${e.value}'),
        },
        closed: j['closed'] as bool? ?? false,
        snoozedUntil: DateTime.tryParse(j['snoozedUntil'] as String? ?? ''),
      );
}

/// A stable case id for one checked message, so the emergency page and the
/// report page share the same checklist. The message itself is not stored.
String caseIdFor(Investigation inv) =>
    sha1.convert(utf8.encode(inv.artefact.text)).toString().substring(0, 16);

/// A short label with no personal details, for example "Investment scam".
String caseTitleFor(Investigation? inv) => inv == null ? 'My scam case' : inv.verdict.scamType;
