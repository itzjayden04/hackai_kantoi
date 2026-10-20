import 'package:flutter/material.dart';

import '../engine/forensics/keys.dart';
import 'theme.dart';

/// Holds the text fields for the optional link-check keys, so the Settings
/// page can save them with its own Save button.
class ForensicKeysController {
  final safeBrowsing = TextEditingController();
  final virusTotal = TextEditingController();
  final abuseCh = TextEditingController();
  final urlscan = TextEditingController();

  ForensicKeysController(ForensicKeys current) {
    final u = current.userValues();
    safeBrowsing.text = u['safeBrowsing']!;
    virusTotal.text = u['virusTotal']!;
    abuseCh.text = u['abuseCh']!;
    urlscan.text = u['urlscan']!;
  }

  ForensicKeys get value => ForensicKeys.withOverrides(
        safeBrowsing: safeBrowsing.text,
        virusTotal: virusTotal.text,
        abuseCh: abuseCh.text,
        urlscan: urlscan.text,
      );

  void dispose() {
    for (final c in [safeBrowsing, virusTotal, abuseCh, urlscan]) {
      c.dispose();
    }
  }
}

/// Settings section for the optional link reputation services.
class ForensicKeysSection extends StatelessWidget {
  final ForensicKeysController controller;
  const ForensicKeysSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final built = ForensicKeys.builtIn;
    Widget field(TextEditingController c, String label, String where, bool hasBuiltIn) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(
            controller: c,
            obscureText: true,
            decoration: InputDecoration(
              labelText: label,
              helperText: hasBuiltIn ? 'Leave empty to use the key built into this copy of Kantoi.' : 'Optional. Free key from $where.',
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Link safety services (optional)'),
      Text(
          'With these free keys Kantoi also asks well-known safety lists about a link. Only the link is sent, never your message. '
          'Without a key, that check is skipped. Keys are stored only on this device.',
          style: t.bodyMedium),
      field(controller.safeBrowsing, 'Google Safe Browsing key', 'console.cloud.google.com', built['safeBrowsing']!),
      field(controller.virusTotal, 'VirusTotal key', 'virustotal.com', built['virusTotal']!),
      field(controller.abuseCh, 'URLhaus (abuse.ch) key', 'auth.abuse.ch', built['abuseCh']!),
      field(controller.urlscan, 'urlscan.io key (takes a screenshot in a remote browser)', 'urlscan.io', built['urlscan']!),
    ]);
  }
}
