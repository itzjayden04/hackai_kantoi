import 'package:flutter/material.dart';

import 'bridge/bridge.dart';
import 'engine/models.dart';
import 'local_store.dart';
import 'state.dart';
import 'ui/case_tracker.dart';
import 'ui/check_page.dart';
import 'ui/emergency_page.dart';
import 'ui/intel_page.dart';
import 'ui/learn_page.dart';
import 'ui/live_page.dart';
import 'ui/relationship_page.dart';
import 'ui/result_view.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.load();
  await localStore.load();
  await startBridge();
  runApp(const KantoiApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

class KantoiApp extends StatelessWidget {
  const KantoiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Kantoi',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  int _seenLive = 0;
  static const _paidTab = 5;

  static const _dests = [
    (Icons.search_rounded, 'Check'),
    (Icons.favorite_border_rounded, 'Relationship'),
    (Icons.shield_outlined, 'Live'),
    (Icons.hub_outlined, 'Scam map'),
    (Icons.school_outlined, 'Learn'),
    (Icons.emergency_outlined, 'I already paid'),
    (Icons.settings_outlined, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    appState.openResult = (inv) => navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => Scaffold(appBar: AppBar(title: const Text('Kantoi check')), body: _ResultPage(inv: inv))));
    appState.addListener(_onState);
  }

  void _onState() {
    // Pop a quiet banner when the extension flags something new.
    final n = appState.live.length;
    if (n > _seenLive && mounted) {
      final item = appState.live.first;
      _seenLive = n;
      if (item.investigation.verdict.level.index >= RiskLevel.suspicious.index ||
          (item.conversation?.level.index ?? 0) >= RiskLevel.suspicious.index) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Kantoi flagged a message from ${item.chat}: ${riskLabel(item.investigation.verdict.level)}'),
          action: SnackBarAction(label: 'View', onPressed: () => setState(() => _tab = 2)),
        ));
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    appState.removeListener(_onState);
    super.dispose();
  }

  Widget get _page => switch (_tab) {
        0 => const CheckPage(),
        1 => const RelationshipPage(),
        2 => const LivePage(),
        3 => const IntelPage(),
        4 => const LearnPage(),
        5 => const EmergencyPage(embedded: true),
        _ => const SettingsPage(),
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final liveBadge = appState.live.where((i) => i.investigation.verdict.level.index >= RiskLevel.suspicious.index).length;
    Widget icon(int i) {
      final ic = Icon(_dests[i].$1, color: i == _paidTab ? const Color(0xFFDC2626) : null);
      return i == 2 && liveBadge > 0 ? Badge(label: Text('$liveBadge'), child: ic) : ic;
    }

    final body = SafeArea(
        child: Column(children: [
      const CaseReminderBanner(),
      Expanded(child: KeyedSubtree(key: ValueKey(_tab), child: _page)),
    ]));
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: _Logo(compact: true)),
            destinations: [
              for (var i = 0; i < _dests.length; i++) NavigationRailDestination(icon: icon(i), label: Text(_dests[i].$2)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    // Phones get the five most-used tabs at the bottom; Live (desktop
    // extension) and Settings move to the top bar.
    const bottom = [0, 1, 3, 4, _paidTab];
    final sel = bottom.indexOf(_tab);
    return Scaffold(
      appBar: AppBar(title: const _Logo(), centerTitle: false, actions: [
        if (appState.extensionConnected || appState.live.isNotEmpty)
          IconButton(tooltip: 'Live', onPressed: () => setState(() => _tab = 2), icon: icon(2)),
        IconButton(tooltip: 'Settings', onPressed: () => setState(() => _tab = 6), icon: Icon(_dests[6].$1)),
      ]),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: sel < 0 ? 0 : sel,
        indicatorColor: sel < 0 ? Colors.transparent : null,
        onDestinationSelected: (i) => setState(() => _tab = bottom[i]),
        destinations: [
          for (final i in bottom) NavigationDestination(icon: icon(i), label: _dests[i].$2),
        ],
      ),
    );
  }
}

class _ResultPage extends StatelessWidget {
  final Investigation inv;
  const _ResultPage({required this.inv});
  @override
  Widget build(BuildContext context) => PageBody(children: [ResultView(inv: inv)]);
}

class _Logo extends StatelessWidget {
  final bool compact;
  const _Logo({this.compact = false});
  @override
  Widget build(BuildContext context) => Flex(direction: compact ? Axis.vertical : Axis.horizontal, mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.policy_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 8, height: 4),
        Text('Kantoi', style: (compact ? Theme.of(context).textTheme.titleSmall : Theme.of(context).textTheme.titleLarge)?.copyWith(fontWeight: FontWeight.w900)),
      ]);
}
