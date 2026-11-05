import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/models.dart';

/// Design tokens: a calm monochrome base (soft grey-white, ink text, black
/// pill buttons) so the risk colours are the only strong colour on screen.
class K {
  static const primary = Color(0xFF15181D);
  static const primaryContainer = Color(0xFF15181D);
  static const primaryFixed = Color(0xFFE6E9ED);
  static const secondary = Color(0xFF6B717B);
  static const secondaryContainer = Color(0xFFE9ECF0);
  static const tertiaryFixed = Color(0xFFFFDCC3);
  static const surface = Color(0xFFF3F5F7);
  static const surfaceLow = Color(0xFFF1F3F6);
  static const surfaceMid = Color(0xFFEBEEF2);
  static const surfaceHigh = Color(0xFFE3E7EC);
  static const surfaceHighest = Color(0xFFDADFE5);
  static const onSurface = Color(0xFF111418);
  static const onSurfaceVariant = Color(0xFF59606A);
  static const inverseSurface = Color(0xFF1C2026);
  static const outline = Color(0xFF8C929B);
  static const outlineVariant = Color(0xFFDADEE3);
  static const error = Color(0xFFBA1A1A);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);
  static const tertiaryContainer = Color(0xFF653400);
  static const onTertiaryContainer = Color(0xFFFC922B);
  static const red = Color(0xFFDC2626);
  static const orange = Color(0xFFEA580C);
  static const amber = Color(0xFFD97706);
  static const green = Color(0xFF15803D);

  /// Kantoi's deep blue, the colour of Trace's Start trace bar: filled
  /// buttons, the open tab, switches and the logo.
  static const navy = Color(0xFF0B4A8B);

  /// The brighter blue of the Trace and Emergency headers: links, counts
  /// and progress on their white sheets.
  static const blue = Color(0xFF1D56C4);

  /// Frosted card fill and its hairline edge.
  static const glass = Color(0xE6FFFFFF);
  static const glassEdge = Color(0xB3FFFFFF);

  /// The soft sky wash behind the main screen: the Trace header's blue,
  /// kept pale.
  static const skyTop = Color(0xFFD3E6FB);
  static const skyMid = Color(0xFFE8F2FD);

  /// Dark canvas used by the Trace map and the Emergency header.
  static const night = Color(0xFF0B1220);
  static const nightCard = Color(0xFF131C2E);
  static const nightLine = Color(0xFF26334D);

  static const r16 = BorderRadius.all(Radius.circular(16));
  static const r8 = BorderRadius.all(Radius.circular(8));
  static const r12 = BorderRadius.all(Radius.circular(12));
  static const rCard = BorderRadius.all(Radius.circular(22));
  static const shadow = [BoxShadow(color: Color(0x0D111418), blurRadius: 24, offset: Offset(0, 8))];

  static const fast = Duration(milliseconds: 220);
  static const medium = Duration(milliseconds: 380);
  static const curve = Curves.easeOutCubic;
}

/// The sky wash: pale sky blue at the top fading into the page, with a faint
/// light-blue glow on the right. With [deep] a Kantoi navy wash fades in over
/// the top half, as behind the Trace header.
class SkyBackground extends StatelessWidget {
  final Widget child;
  final bool deep;
  const SkyBackground({super.key, required this.child, this.deep = false});

  /// Strong blue at the top easing to a light sky blue, then into the page.
  static const deepWash = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1C4FB8), Color(0xFF2C6FD6), Color(0xFF63A6EC), Color(0xFFA9D2F6), K.surface],
    stops: [0, 0.16, 0.32, 0.44, 0.58],
  );

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [K.skyTop, K.skyMid, K.surface],
            stops: [0, 0.32, 0.62],
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.1, -0.85),
              radius: 0.9,
              colors: [Color(0x40A9D2F6), Color(0x00A9D2F6)],
            ),
          ),
          child: Stack(fit: StackFit.expand, children: [
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: deep ? 1 : 0,
                duration: K.medium,
                curve: K.curve,
                // The wash plus a soft light patch, like light through glass.
                child: const DecoratedBox(
                  decoration: BoxDecoration(gradient: deepWash),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0.55, -0.15),
                        radius: 0.75,
                        colors: [Color(0x40CFE6FF), Color(0x00CFE6FF)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child,
          ]),
        ),
      );
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
          secondary: K.secondary,
          onSecondary: Colors.white,
          secondaryContainer: K.secondaryContainer,
          onSecondaryContainer: Color(0xFF5C647A),
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
      displaySmall: t.displaySmall?.copyWith(fontSize: 36, height: 44 / 36, fontWeight: FontWeight.w400, letterSpacing: -1.2),
      headlineMedium: t.headlineMedium?.copyWith(fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w400, letterSpacing: -0.9),
      headlineSmall: t.headlineSmall?.copyWith(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w400, letterSpacing: -0.5),
      titleLarge: t.titleLarge?.copyWith(fontSize: 19, height: 24 / 19, fontWeight: FontWeight.w500, letterSpacing: -0.2),
      titleMedium: t.titleMedium?.copyWith(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w500),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 15, height: 22 / 15),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, height: 20 / 14),
      bodySmall: t.bodySmall?.copyWith(fontSize: 13, height: 18 / 13, color: scheme.onSurfaceVariant),
      labelLarge: t.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: t.labelMedium?.copyWith(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500),
      labelSmall: t.labelSmall?.copyWith(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w500, letterSpacing: 0.2),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      // Dark status-bar icons: the bar is see-through over a light page.
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w500, letterSpacing: -0.3, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? scheme.surfaceContainerLow : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: K.rCard),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? null : K.navy,
        foregroundColor: dark ? null : Colors.white,
        disabledBackgroundColor: dark ? null : K.surfaceMid,
        disabledForegroundColor: dark ? null : K.outline,
        minimumSize: const Size(0, 54),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w500),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        backgroundColor: dark ? null : Colors.white,
        foregroundColor: dark ? null : K.onSurface,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500),
        shape: const StadiumBorder(),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      backgroundColor: dark ? null : Colors.white,
      labelStyle: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurface),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? null : K.onSurface,
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: K.r16, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7))),
      enabledBorder: OutlineInputBorder(borderRadius: K.r16, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7))),
      focusedBorder: OutlineInputBorder(borderRadius: K.r16, borderSide: BorderSide(color: scheme.onSurface, width: 1.2)),
      errorBorder: OutlineInputBorder(borderRadius: K.r16, borderSide: BorderSide(color: scheme.error.withValues(alpha: 0.5))),
      focusedErrorBorder: OutlineInputBorder(borderRadius: K.r16, borderSide: BorderSide(color: scheme.error, width: 1.5)),
      filled: true,
      fillColor: dark ? scheme.surfaceContainerLow : Colors.white,
      hintStyle: const TextStyle(color: K.outline),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? scheme.surfaceContainerLow : Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? scheme.surfaceContainerLow : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: K.inverseSurface, shape: StadiumBorder()),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary, linearTrackColor: scheme.surfaceContainerHigh),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? (dark ? K.green : K.navy) : scheme.outlineVariant),
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
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
          ?trailing,
        ]),
      );
}
