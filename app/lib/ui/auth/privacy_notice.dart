import 'package:flutter/material.dart';

import '../../auth/account.dart';
import '../theme.dart';

/// The Privacy Notice the user agrees to at sign-up (PDPA 2010, notice and
/// choice). Plain English, one screen.
class PrivacyNoticePage extends StatelessWidget {
  const PrivacyNoticePage({super.key});

  static const sections = [
    (
      'What Kantoi stores about you',
      'Your name, email, username, optional phone number, and the date you agreed to this notice. '
          'Your password is stored only as a scrambled one-way code.'
    ),
    (
      'What stays on your phone',
      'The messages Kantoi checks, your check, trace and learning history, your reports, screenshots and your safe word vault. '
          'Safe words are encrypted and are never backed up or sent anywhere.'
    ),
    (
      'What Kantoi shares to protect others',
      'When Kantoi is very sure something is a scam, or when you submit a report, it adds masked details to Kantoi\'s scam database: '
          'the type of scam, which warning signs fired, which app it came in on, website names, and phone numbers or accounts '
          'turned into one-way codes with a masked form (like 012-***-4567). It never shares message text, contact names, '
          'screenshots or transaction numbers. You can turn this off in Settings at any time.'
    ),
    (
      'AI and online checks',
      'To check a message, Kantoi may send it to Google Gemini and to link-checking services after hiding your personal details. '
          'Each check shows exactly what was sent, in "How Kantoi checked this".'
    ),
    (
      'How long data is kept',
      'History on your phone follows the "Keep history for" setting. You can download your data or delete your account and all '
          'data from Settings.'
    ),
    (
      'Where data is stored',
      'On your phone, and for shared scam data, on servers that may be outside Malaysia (for example Google Cloud in Singapore), '
          'which protect data to a standard similar to Malaysian law.'
    ),
    (
      'Your rights',
      'Under the Personal Data Protection Act 2010 you can ask to see, correct or delete your data, and withdraw consent. '
          'Use Settings, or contact the Kantoi team through the GitHub page.'
    ),
    (
      'Honest limits',
      'Kantoi gives its best judgement, not a guarantee. It is not the police, your bank or a lawyer. In an emergency call 997.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Notice and Terms')),
      body: PageBody(children: [
        Text('Version $consentVersion', style: t.labelMedium?.copyWith(color: K.outline)),
        const SizedBox(height: 12),
        for (final (title, body) in sections) ...[
          Text(title, style: t.titleMedium),
          const SizedBox(height: 4),
          Text(body, style: t.bodyMedium?.copyWith(height: 1.5)),
          const SizedBox(height: 16),
        ],
      ]),
    );
  }
}
