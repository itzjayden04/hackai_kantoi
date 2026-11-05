import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth/auth_service.dart';
import 'cloud/outbox.dart';
import 'guard/guard_background.dart';
import 'history/history_log.dart';
import 'report/report_store.dart';
import 'ui/auth/auth_flow.dart';
import 'vault/vault.dart';
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
import 'ui/learn_page.dart';
import 'ui/protection_page.dart';
import 'ui/report/report_tab.dart';
import 'ui/settings_page.dart';
import 'ui/setup_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.load();
  await localStore.load();
  await auth.load();
  await Future.wait([historyLog.load(), reportStore.load(), cloudOutbox.load(), vault.load()]);
  await startTelegramBot();
  final firstRun = guardSupported && !await setupSeen();
  runApp(KantoiApp(firstRun: firstRun, needsLogin: !auth.signedIn, loginRequired: true));
}

/// Entry point for Android phone protection, started by the native side
/// without any screen.
@pragma('vm:entry-point')
Future<void> guardMain() => runGuardBackground();

final navigatorKey = GlobalKey<NavigatorState>();

class KantoiApp extends StatefulWidget {
  final bool firstRun;
  /// Every user signs in before using the app (tests skip it).
  final bool needsLogin;
  /// Signing out returns to the login screen, even when the app was opened
  /// already signed in.
  final bool loginRequired;
  const KantoiApp({super.key, this.firstRun = false, this.needsLogin = false, this.loginRequired = false});
  @override
  State<KantoiApp> createState() => _KantoiAppState();
}

class _KantoiAppState extends State<KantoiApp> with WidgetsBindingObserver {
  late bool _setup = widget.firstRun;
  late bool _login = widget.needsLogin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    auth.addListener(_onAuth);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    auth.removeListener(_onAuth);
    super.dispose();
  }

  /// Signing out (or the 7-day rule) returns to the login screen.
  void _onAuth() {
    if (!mounted) return;
    if (!auth.signedIn && (widget.needsLogin || widget.loginRequired) && !_login) setState(() => _login = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && (widget.needsLogin || widget.loginRequired)) auth.checkInactivity();
  }

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
      child: _login
          ? AuthFlow(key: const ValueKey('login'), onDone: () => setState(() => _login = false))
          : _setup
          ? SetupFlow(key: const ValueKey('setup'), startAtPermissions: widget.needsLogin, onDone: () => setState(() => _setup = false))
          : const Shell(),
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
    (Icons.verified_user_outlined, Icons.verified_user_rounded, 'Check'),
    (Icons.travel_explore_outlined, Icons.travel_explore_rounded, 'Trace'),
    (Icons.flag_outlined, Icons.flag_rounded, 'Report'),
    (Icons.school_outlined, Icons.school_rounded, 'Learn'),
    (Icons.sos_outlined, Icons.sos_rounded, 'Emerg'),
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
    2 => const ReportTab(),
    3 => const LearnPage(),
    _ => const EmergencyPage(embedded: true),
  };

  @override
  Widget build(BuildContext context) {
    final tab = appState.tab.value;
    // Trace and Emergency have a blue header behind the bar, so the bar goes light.
    final deep = tab == tabTrace || tab == tabEmergency;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: SkyBackground(
        deep: deep,
        child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        appBar: AppBar(
          systemOverlayStyle: deep ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          // No back arrow on the tabs: the tab bar moves between them and the
          // phone's back gesture still returns to Check.
          automaticallyImplyLeading: false,
          titleSpacing: 20,
          // The wordmark on every tab, white on the blue headers; each page
          // shows its own big title.
          toolbarHeight: 64,
          title: KantoiWordmark(light: deep),
          actions: [
            // Plain line icons on every tab: white on the blue headers.
            ProtectionShield(color: deep ? Colors.white : K.onSurface),
            IconButton(
              tooltip: 'Settings',
              color: deep ? Colors.white : K.onSurface,
              icon: const Icon(Icons.settings_outlined, size: 24),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Settings')),
                    body: const SettingsPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
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
      ),
    );
  }
}

/// Floating frosted capsule above the page, icons only. The open tab
/// widens into a filled ink pill; Emergency is always red so it can be found
/// in a hurry, and a red dot on Report means a report draft is waiting.
class _GlassNav extends StatelessWidget {
  final int index;
  final List<(IconData, IconData, String)> items;
  final ValueChanged<int> onTap;
  const _GlassNav({required this.index, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(36)),
            boxShadow: [
              BoxShadow(color: Color(0x14111418), blurRadius: 40, spreadRadius: 2, offset: Offset(0, 14)),
              BoxShadow(color: Color(0x0A111418), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(36)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  // Glass: a see-through white wash, brighter along the top
                  // edge, with a thin light rim.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withValues(alpha: 0.72), Colors.white.withValues(alpha: 0.45)],
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(36)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.2),
                ),
                child: ListenableBuilder(
                  listenable: reportStore,
                  builder: (context, _) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onTap(i);
                          },
                          child: _NavItem(item: items[i], selected: i == index, badge: i == tabReport && reportStore.openDraft != null),
                        ),
                    ],
                  ),
                ),
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
  final bool badge;
  const _NavItem({required this.item, required this.selected, required this.badge});

  @override
  Widget build(BuildContext context) {
    final sos = item.$1 == Icons.sos_outlined;
    final fill = sos ? K.red : K.navy;
    final c = selected ? Colors.white : (sos ? K.red : K.secondary);
    return Semantics(
      selected: selected,
      button: true,
      label: item.$3,
      child: Tooltip(
        message: item.$3,
        child: AnimatedContainer(
          duration: K.medium,
          curve: K.curve,
          width: selected ? 68 : 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.lerp(fill, Colors.white, 0.18)!, fill],
                  )
                : null,
            borderRadius: BorderRadius.circular(24),
            boxShadow: selected ? [BoxShadow(color: fill.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: 1, offset: const Offset(0, 4))] : null,
          ),
          child: Center(
            child: Stack(clipBehavior: Clip.none, children: [
              Icon(selected ? item.$2 : item.$1, color: c, size: 24),
              if (badge)
                Positioned(
                  top: -1,
                  right: -3,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: K.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A shield in the top bar: filled when phone protection is fully on, an
/// outline when it is not. Tapping opens the Protection centre.
class ProtectionShield extends StatefulWidget {
  final Color color;
  const ProtectionShield({super.key, this.color = K.onSurface});
  @override
  State<ProtectionShield> createState() => _ProtectionShieldState();
}

class _ProtectionShieldState extends State<ProtectionShield> with WidgetsBindingObserver {
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
    return IconButton(
      tooltip: on ? 'Protected' : 'Protection is off. Tap to turn on',
      color: widget.color,
      icon: Icon(on ? Icons.verified_user : Icons.verified_user_outlined, size: 24),
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProtectionPage()));
        _refresh();
      },
    );
  }
}
