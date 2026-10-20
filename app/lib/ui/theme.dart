import 'package:flutter/material.dart';

import '../engine/models.dart';

/// Design tokens from the Stitch "Vigilant Precision" system (DESIGN.md).
class K {
  static const primary = Color(0xFF00236F);
  static const primaryContainer = Color(0xFF1E3A8A);
  static const surface = Color(0xFFF8F9FF);
  static const surfaceLow = Color(0xFFEFF4FF);
  static const surfaceMid = Color(0xFFE5EEFF);
  static const surfaceHigh = Color(0xFFDCE9FF);
  static const surfaceHighest = Color(0xFFD3E4FE);
  static const onSurface = Color(0xFF0B1C30);
  static const onSurfaceVariant = Color(0xFF444651);
  static const inverseSurface = Color(0xFF213145);
  static const outline = Color(0xFF757682);
  static const outlineVariant = Color(0xFFC5C5D3);
  static const error = Color(0xFFBA1A1A);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);
  static const tertiaryContainer = Color(0xFF653400);
  static const onTertiaryContainer = Color(0xFFFC922B);
  static const red = Color(0xFFDC2626);
  static const orange = Color(0xFFEA580C);
  static const amber = Color(0xFFD97706);
  static const green = Color(0xFF15803D);

  /// Dark canvas used by the Trace map and the Emergency header.
  static const night = Color(0xFF0B1220);
  static const nightCard = Color(0xFF131C2E);
  static const nightLine = Color(0xFF26334D);

  static const r16 = BorderRadius.all(Radius.circular(16));
  static const r8 = BorderRadius.all(Radius.circular(8));

  static const fast = Duration(milliseconds: 220);
  static const medium = Duration(milliseconds: 380);
  static const curve = Curves.easeOutCubic;
}

const brand = K.primaryContainer;

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = dark
      ? ColorScheme.fromSeed(seedColor: K.primaryContainer, brightness: b)
      : const ColorScheme(
          brightness: Brightness.light,
          primary: K.primary,
          onPrimary: Colors.white,
          primaryContainer: K.primaryContainer,
          onPrimaryContainer: Color(0xFF90A8FF),
          secondary: Color(0xFF505F76),
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFD0E1FB),
          onSecondaryContainer: Color(0xFF54647A),
          tertiary: Color(0xFF4B2500),
          onTertiary: Colors.white,
          tertiaryContainer: K.tertiaryContainer,
          onTertiaryContainer: K.onTertiaryContainer,
          error: K.error,
          onError: Colors.white,
          errorContainer: K.errorContainer,
          onErrorContainer: K.onErrorContainer,
          surface: K.surface,
          onSurface: K.onSurface,
          onSurfaceVariant: K.onSurfaceVariant,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: K.surfaceLow,
          surfaceContainer: K.surfaceMid,
          surfaceContainerHigh: K.surfaceHigh,
          surfaceContainerHighest: K.surfaceHighest,
          outline: K.outline,
          outlineVariant: K.outlineVariant,
          inverseSurface: K.inverseSurface,
          onInverseSurface: Color(0xFFEAF1FF),
          inversePrimary: Color(0xFFB6C4FF),
          surfaceTint: K.primary,
        );
  final base = ThemeData(brightness: b, useMaterial3: true, fontFamily: 'Inter', colorScheme: scheme);
  final t = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    textTheme: t.copyWith(
      displaySmall: t.displaySmall?.copyWith(fontSize: 36, height: 44 / 36, fontWeight: FontWeight.w700, letterSpacing: -0.7),
      headlineMedium: t.headlineMedium?.copyWith(fontSize: 26, height: 34 / 26, fontWeight: FontWeight.w600, letterSpacing: -0.3),
      headlineSmall: t.headlineSmall?.copyWith(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w600),
      titleLarge: t.titleLarge?.copyWith(fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600),
      titleMedium: t.titleMedium?.copyWith(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 15, height: 22 / 15),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, height: 20 / 14),
      bodySmall: t.bodySmall?.copyWith(fontSize: 13, height: 18 / 13, color: scheme.onSurfaceVariant),
      labelLarge: t.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: t.labelMedium?.copyWith(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600),
      labelSmall: t.labelSmall?.copyWith(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w600, letterSpacing: 0.4),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? scheme.surfaceContainerLow : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: K.r16, side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(shape: const StadiumBorder(), side: BorderSide(color: scheme.outlineVariant)),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: K.r8, borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: K.r8, borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: K.r8, borderSide: BorderSide(color: scheme.primary, width: 2)),
      filled: true,
      fillColor: dark ? scheme.surfaceContainerLow : Colors.white,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? scheme.surfaceContainerLow : Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? scheme.surfaceContainerLow : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: K.r16)),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary, linearTrackColor: scheme.surfaceContainerHigh),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? K.green : scheme.outlineVariant),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
  );
}

Color riskColor(RiskLevel l) => switch (l) {
      RiskLevel.safe => K.green,
      RiskLevel.caution => K.amber,
      RiskLevel.suspicious => K.orange,
      RiskLevel.danger => K.red,
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
  const PageBody({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32)});

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
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ]),
      );
}
