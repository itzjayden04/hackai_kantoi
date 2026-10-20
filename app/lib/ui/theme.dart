import 'package:flutter/material.dart';

import '../engine/models.dart';

const brand = Color(0xFF1E3A8A);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
    ),
  );
}

Color riskColor(RiskLevel l) => switch (l) {
      RiskLevel.safe => const Color(0xFF15803D),
      RiskLevel.caution => const Color(0xFFB45309),
      RiskLevel.suspicious => const Color(0xFFEA580C),
      RiskLevel.danger => const Color(0xFFDC2626),
    };

IconData riskIcon(RiskLevel l) => switch (l) {
      RiskLevel.safe => Icons.verified_user_rounded,
      RiskLevel.caution => Icons.info_rounded,
      RiskLevel.suspicious => Icons.warning_amber_rounded,
      RiskLevel.danger => Icons.gpp_bad_rounded,
    };

/// Constrains page content to a readable width on large screens.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  const PageBody({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 40)});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: padding,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ?trailing,
        ]),
      );
}
