import 'package:flutter/material.dart';

import '../engine/investigator.dart';
import '../engine/models.dart';
import '../guard/guard_control.dart';
import '../state.dart';
import 'kit.dart';
import 'result_view.dart';
import 'theme.dart';

/// The app a warning came from, in plain words.
String guardAppName(String pkg) {
  if (pkg.contains('whatsapp')) return 'WhatsApp';
  if (pkg.contains('telegram') || pkg.contains('challegram')) return 'Telegram';
  if (pkg.contains('facebook.orca')) return 'Messenger';
  if (pkg.contains('instagram')) return 'Instagram';
  if (pkg.contains('android.gm')) return 'Gmail';
  if (pkg.contains('outlook')) return 'Outlook';
  if (pkg.contains('email') || pkg.contains('mail')) return 'Email';
  if (pkg.contains('messaging') || pkg.contains('mms') || pkg.contains('sms')) return 'SMS';
  if (pkg.contains('chrome')) return 'Chrome';
  if (pkg.contains('sbrowser')) return 'Samsung Internet';
  if (pkg.contains('firefox')) return 'Firefox';
  if (pkg.contains('emmx')) return 'Edge';
  if (pkg.contains('opera')) return 'Opera';
  if (pkg.contains('brave')) return 'Brave';
  return '';
}

/// Icon and short name for each kind of warning.
(IconData, String) guardKind(String kind) => switch (kind) {
      'call' => (Icons.phone_disabled_outlined, 'Call'),
      'site' => (Icons.language_rounded, 'Website closed'),
      'app' => (Icons.install_mobile_outlined, 'New app'),
      'photo' => (Icons.qr_code_2_rounded, 'QR code'),
      'chat' => (Icons.forum_outlined, 'Chat'),
      _ => (Icons.sms_outlined, 'Message'),
    };

RiskLevel guardLevel(String level) => RiskLevel.values.where((l) => l.name == level).firstOrNull ?? RiskLevel.suspicious;

/// Opens a warning: messages get a full check here, links and numbers go to
/// the Trace tab, apps show what Kantoi found.
void openGuardAlert(BuildContext context, GuardAlert a) {
  if (a.kind == 'message' || a.kind == 'chat') {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuardAlertDetail(alert: a)));
  } else if (a.kind == 'app') {
    showKSheet<void>(
      context,
      title: a.chat,
      icon: Icons.install_mobile_outlined,
      iconColor: riskColor(guardLevel(a.level)),
      message: a.headline,
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final r in a.reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: riskColor(guardLevel(a.level))),
              const SizedBox(width: 8),
              Expanded(child: Text(r)),
            ]),
          ),
        const SizedBox(height: 8),
        const Text('To remove it: open Settings, then Apps, find the app and tap Uninstall.'),
      ]),
      primary: 'OK',
    );
  } else {
    Navigator.of(context).popUntil((r) => r.isFirst);
    appState.openTrace(a.target.isNotEmpty ? a.target : a.chat);
  }
}

/// The full check of a message phone protection warned about, with AI if set up.
class GuardAlertDetail extends StatefulWidget {
  final GuardAlert alert;
  const GuardAlertDetail({super.key, required this.alert});
  @override
  State<GuardAlertDetail> createState() => _GuardAlertDetailState();
}

class _GuardAlertDetailState extends State<GuardAlertDetail> {
  late final Future<Investigation> _inv = investigate(widget.alert.text, source: Source.share, sender: widget.alert.chat, options: appState.options).then((r) {
    appState.addHistory(r);
    return r;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.alert.chat)),
        body: FutureBuilder<Investigation>(
          future: _inv,
          builder: (context, snap) => snap.hasData
              ? PageBody(children: [ResultView(inv: snap.data!)])
              : snap.hasError
                  ? PageBody(children: [Text('Could not check this message: ${snap.error}')])
                  : const Center(child: CircularProgressIndicator()),
        ),
      );
}
