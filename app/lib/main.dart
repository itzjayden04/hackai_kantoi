import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'guard/guard_background.dart';
import 'guard/guard_control.dart';
import 'local_store.dart';
import 'intake/share_intake.dart';
import 'intake/telegram_bot.dart';
import 'state.dart';
import 'ui/case_tracker.dart';
import 'ui/check/result_page.dart';
import 'ui/check_page.dart';
import 'ui/emergency_page.dart';
import 'ui/intel_page.dart';
import 'ui/kit.dart';
import 'ui/learn_page.dart';
import 'ui/protection_page.dart';
import 'ui/settings_page.dart';
import 'ui/setup_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.load();
  await localStore.load();
  await startTelegramBot();
  final firstRun = guardSupported && !await setupSeen();
  runApp(KantoiApp(firstRun: firstRun));
}

/// Entry point for Android phone protection, started by the native side
/// without any screen.
@pragma('vm:entry-point')
Future<void> guardMain() => runGuardBackground();

final navigatorKey = GlobalKey<NavigatorState>();

class KantoiApp extends StatefulWidget {
  final bool firstRun;
  const KantoiApp({super.key, this.firstRun = false});
  @override
  State<KantoiApp> createState() => _KantoiAppState();
}

class _KantoiAppState extends State<KantoiApp> {
  late bool _setup = widget.firstRun;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kantoi',
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey,
    theme: buildTheme(Brightness.light),
    // The design is light-first; dark mode follows later.
    themeMode: ThemeMode.light,
    home: AnimatedSwitcher(
      duration: K.medium,
      child: _setup ? SetupFlow(key: const ValueKey('setup'), onDone: () => setState(() => _setup = false)) : const Shell(),
    ),
  );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  static const _tabs = [
    (Icons.shield_outlined, Icons.shield_rounded, 'Check'),
    (Icons.hub_outlined, Icons.hub_rounded, 'Trace'),
    (Icons.school_outlined, Icons.school_rounded, 'Learn'),
    (Icons.emergency_outlined, Icons.emergency_rounded, 'Emergency'),
  ];
  // Tabs are built the first time they are opened, then kept alive so a
  // running trace or check survives switching tabs.
  final _built = <int>{0};
  DateTime? _exitAsked;

  /// Back steps out one level at a time: first inside the tab (stop a check
  /// or trace, close a result), then to the Check tab, then a second press
  /// within two seconds leaves the app.
  void _onBack() {
    final tab = appState.tab.value;
    if (appState.backHandlers[tab]?.call() ?? false) return;
    if (tab != 0) {
      appState.tab.value = 0;
      return;
    }
    final now = DateTime.now();
    if (_exitAsked != null && now.difference(_exitAsked!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _exitAsked = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Press back again to close Kantoi'), duration: Duration(seconds: 2)));
  }

  @override
  void initState() {
    super.initState();
    appState.openResult = (inv) => navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ResultPage(inv: inv)));
    appState.tab.addListener(_onTab);
    listenForShares(() => appState.tab.value = 0);
  }

  void _onTab() {
    if (mounted) setState(() => _built.add(appState.tab.value));
  }

  @override
  void dispose() {
    appState.tab.removeListener(_onTab);
    super.dispose();
  }

  Widget _page(int i) => switch (i) {
    0 => const CheckPage(),
    1 => const IntelPage(),
    2 => const LearnPage(),
    _ => const EmergencyPage(embedded: true),
  };

  @override
  Widget build(BuildContext context) {
    final tab = appState.tab.value;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        extendBody: true,
        appBar: AppBar(
          leading: tab == 0 ? null : IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: _onBack),
          titleSpacing: tab == 0 ? 16 : 0,
          title: const KantoiLogo(),
          actions: [
            const ProtectedPill(),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Settings')),
                    body: const SettingsPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            const CaseReminderBanner(),
            Expanded(
              child: Stack(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    if (_built.contains(i))
                      IgnorePointer(
                        ignoring: i != tab,
                        child: AnimatedOpacity(
                          opacity: i == tab ? 1 : 0,
                          duration: K.fast,
                          child: AnimatedSlide(
                            offset: i == tab ? Offset.zero : const Offset(0, 0.02),
                            duration: K.medium,
                            curve: K.curve,
                            child: TickerMode(
                              enabled: i == tab,
                              child: KeyedSubtree(key: ValueKey(i), child: _page(i)),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _GlassNav(index: tab, items: _tabs, onTap: (i) => appState.tab.value = i),
      ),
    );
  }
}

/// Frosted bottom bar with a sliding highlight; Emergency is always red.
class _GlassNav extends StatelessWidget {
  final int index;
  final List<(IconData, IconData, String)> items;
  final ValueChanged<int> onTap;
  const _GlassNav({required this.index, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            border: Border(top: BorderSide(color: K.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: InkResponse(
                        onTap: () => onTap(i),
                        child: _NavItem(item: items[i], selected: i == index, danger: i == 3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final (IconData, IconData, String) item;
  final bool selected;
  final bool danger;
  const _NavItem({required this.item, required this.selected, required this.danger});

  @override
  Widget build(BuildContext context) {
    final c = danger ? K.red : (selected ? K.primary : K.outline);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: K.medium,
          curve: K.curve,
          padding: EdgeInsets.symmetric(horizontal: selected ? 18 : 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? (danger ? K.red : K.primary).withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Icon(selected ? item.$2 : item.$1, color: c, size: 24),
        ),
        const SizedBox(height: 2),
        Text(
          item.$3,
          style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: c),
        ),
      ],
    );
  }
}

/// "Protected" with a breathing green dot when phone protection is fully
/// on, "Turn on" in amber otherwise. Tapping opens the Protection centre.
class ProtectedPill extends StatefulWidget {
  const ProtectedPill({super.key});
  @override
  State<ProtectedPill> createState() => _ProtectedPillState();
}

class _ProtectedPillState extends State<ProtectedPill> with WidgetsBindingObserver {
  GuardStatus? _s;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await guardStatus();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    if (!guardSupported) return const SizedBox.shrink();
    final on = _s?.ready ?? false;
    final c = on ? K.green : K.amber;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Material(
        color: c.withValues(alpha: 0.1),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProtectionPage()));
            _refresh();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                on
                    ? PulseDot(color: c, size: 7)
                    : Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.error_outline_rounded, size: 14, color: c),
                      ),
                Text(
                  _s == null ? '...' : (on ? 'Protected' : 'Turn on'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
