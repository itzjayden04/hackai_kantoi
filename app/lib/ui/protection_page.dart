import 'package:flutter/material.dart';

import 'phone_guard.dart';
import 'theme.dart';

/// Protection centre: one place to switch each kind of auto-protection on
/// or off, opened from the "Protected" pill in the top bar.
class ProtectionPage extends StatelessWidget {
  const ProtectionPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Protection')),
        body: const PageBody(children: [PhoneGuardSection()]),
      );
}
