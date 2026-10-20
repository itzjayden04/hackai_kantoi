import 'package:flutter/material.dart';

import '../../engine/models.dart';
import '../../state.dart';
import '../result_view.dart';
import '../theme.dart';

/// A check opened on its own screen (from Recent checks, a notification or
/// a deep link), with Trace / Report / Warn family pinned to the bottom.
class ResultPage extends StatelessWidget {
  final Investigation inv;
  const ResultPage({super.key, required this.inv});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Check result')),
    body: PageBody(children: [ResultView(inv: inv, inlineActions: false)]),
    bottomNavigationBar: StickyActions(
      inv: inv,
      onNew: () {
        Navigator.of(context).popUntil((r) => r.isFirst);
        appState.tab.value = 0;
      },
      bottomInset: MediaQuery.paddingOf(context).bottom,
    ),
  );
}
