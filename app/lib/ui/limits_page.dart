import 'package:flutter/material.dart';

import 'theme.dart';

/// "What Kantoi can't do": an honest list of blind spots and how reliable
/// each check is, using the numbers in docs/evaluation.md.
class LimitsPage extends StatelessWidget {
  const LimitsPage({super.key});

  static const _cannot = [
    ('Voice and video calls', 'Kantoi cannot listen to calls or spot deepfake voices or faces. If someone calls asking for money, hang up and call back on a number you already know.'),
    ('Attachments, apps and files', 'Kantoi does not open PDFs, APK apps or other files. Never install an app sent by message.'),
    ('Messages with no warning words', 'A scammer who writes politely, with no link, no money request and no pressure, can look safe until the money request comes.'),
    ('Who is really behind an account', 'Kantoi judges messages and patterns. It cannot prove who a person is, and a relationship result is "consistent with" a scam, not proof.'),
    ('Brand-new scam scripts', 'The built-in checks know common Malaysian scams. A new trick may only be caught by the AI explanation, or not at all.'),
    ('Languages other than English and Malay', 'Chinese, Tamil and other languages are not checked by the built-in rules.'),
    ('Websites that look fine today', 'A link can be safe when checked and changed later. Kantoi checks the link at the moment you ask.'),
  ];

  static const _reliability = [
    (
      'Built-in message checks',
      'On 32 new test messages Kantoi had not been tuned on: when it says "Suspicious" or worse, it was right every time (precision 100%), '
          'but it caught 2 in 3 scams (recall 67%). Counting "Be careful" as a warning, it caught 5 in 6 scams (83%) with 1 false alarm in 14 genuine messages.',
    ),
    (
      'On the set used to tune the rules',
      '90 Malaysian messages in English, Malay and Manglish: precision 100%, recall 96% at "Suspicious". These numbers are optimistic because the rules were adjusted on this set.',
    ),
    (
      'Link checks',
      'Finds look-alike bank and courier websites, new domains and redirects. Needs the internet; offline, only the address itself is checked.',
    ),
    (
      'AI explanations',
      'Only claims that quote the message word for word are kept, so the AI cannot invent evidence. It can still miss things or be unavailable.',
    ),
    (
      'Relationship check',
      'Looks for script patterns, texting rhythm, story changes and writing-style changes. Short chats give less certain results. Not measured on real chats yet.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text("What Kantoi can't do")),
      body: PageBody(children: [
        Text('Kantoi gives its best judgement, not a guarantee. Here is what it does not check, and how often it is right.',
            style: t.bodyLarge),
        const SectionTitle('Kantoi does not detect'),
        for (final (title, body) in _cannot) _Item(Icons.block_rounded, title, body),
        const SectionTitle('How reliable each check is'),
        for (final (title, body) in _reliability) _Item(Icons.speed_rounded, title, body),
        const SizedBox(height: 12),
        Text('Measured with the built-in checks only (no internet, no AI) on synthetic Malaysian messages written for testing. '
            'Real-world results will differ. If Kantoi gets something wrong, use "This was actually legit" or "This was actually a scam" on the result.',
            style: t.bodySmall),
      ]),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Item(this.icon, this.title, this.body);
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Theme.of(context).colorScheme.outline),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(body),
      );
}
