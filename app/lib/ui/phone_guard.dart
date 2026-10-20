import 'package:flutter/material.dart';

import '../guard/guard_control.dart';
import '../engine/investigator.dart';
import '../engine/models.dart';
import '../state.dart';
import 'result_view.dart';
import 'theme.dart';

/// Android phone protection: checks chat messages as they arrive and shows a
/// pause card over WhatsApp, Telegram or a banking app when something looks
/// like a scam.
class PhoneGuardSection extends StatefulWidget {
  const PhoneGuardSection({super.key});
  @override
  State<PhoneGuardSection> createState() => _PhoneGuardSectionState();
}

class _PhoneGuardSectionState extends State<PhoneGuardSection> with WidgetsBindingObserver {
  GuardStatus _s = const GuardStatus(supported: true);
  bool _loaded = false;

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

  // Coming back from Android settings is the moment a permission changes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await guardStatus();
    if (mounted) {
      setState(() {
        _s = s;
        _loaded = true;
      });
    }
  }

  /// One tap turns protection on and walks to the first missing permission.
  Future<void> _turnOn() async {
    await setGuardEnabled(true);
    if (!_s.notifications) {
      await openGuardSetting('notifications');
    } else if (!_s.overlay) {
      await openGuardSetting('overlay');
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final on = _s.ready;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: (on ? const Color(0xFF15803D) : scheme.primary).withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(on ? Icons.shield_rounded : Icons.shield_outlined, size: 32, color: on ? const Color(0xFF15803D) : scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        !_loaded
                            ? 'Checking phone protection'
                            : on
                            ? 'Phone protection is on'
                            : 'Phone protection is off',
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_loaded)
                      Switch(
                        value: _s.enabled,
                        onChanged: (v) async {
                          if (v) {
                            await _turnOn();
                          } else {
                            await setGuardEnabled(false);
                            await _refresh();
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Kantoi reads new WhatsApp, Telegram and SMS messages on this phone and checks them for scam signs. '
                  'If one looks dangerous, a pause card appears on top of the chat. Messages are checked on this phone and never sent anywhere.',
                  style: t.bodyMedium,
                ),
                if (_loaded && _s.enabled && !on) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _turnOn, icon: const Icon(Icons.arrow_forward_rounded), label: const Text('Finish turning it on')),
                ],
              ],
            ),
          ),
        ),
        const SectionTitle('What Kantoi needs'),
        _Permission(
          done: _s.notifications,
          title: 'Read chat notifications',
          why: 'So Kantoi sees new messages from WhatsApp, Telegram and SMS. Other apps are ignored.',
          onTap: () => openGuardSetting('notifications'),
        ),
        _Permission(
          done: _s.overlay,
          title: 'Show the pause card over other apps',
          why: 'Listed by Android as "Display over other apps". Used only for the warning card.',
          onTap: () => openGuardSetting('overlay'),
        ),
        _Permission(
          done: _s.accessibility,
          optional: true,
          title: 'Watch open chats and payment apps',
          why:
              'Optional. Checks messages in the chat you have open (no notification is shown then), and pauses you '
              'before you open a banking or e-wallet app right after a risky chat. Find "Kantoi" under Installed apps.',
          onTap: () => openGuardSetting('accessibility'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'If Android says a setting is restricted: open Settings, then Apps, then Kantoi, tap the three dots at the top and choose '
            '"Allow restricted settings". Android does this for apps installed outside the Play Store.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _s.overlay ? previewPauseCard : () => openGuardSetting('overlay'),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Show me the pause card'),
          ),
        ),
        if (_s.recent.isNotEmpty) ...[
          SectionTitle(
            'Recent warnings on this phone',
            trailing: TextButton(
              onPressed: () async {
                await clearGuardAlerts();
                await _refresh();
              },
              child: const Text('Clear'),
            ),
          ),
          for (final a in _s.recent)
            Card(
              child: ListTile(
                leading: Icon(Icons.warning_amber_rounded, color: a.level == 'danger' ? const Color(0xFFDC2626) : const Color(0xFFEA580C)),
                title: Text('${a.chat} · ${a.label}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [a.reasons.take(2).join(', '), _appName(a.app)].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(TimeOfDay.fromDateTime(a.at).format(context), style: t.bodySmall),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _AlertDetail(alert: a))),
              ),
            ),
        ],
      ],
    );
  }
}

String _appName(String pkg) {
  if (pkg.contains('whatsapp')) return 'WhatsApp';
  if (pkg.contains('telegram') || pkg.contains('challegram')) return 'Telegram';
  if (pkg.contains('messaging') || pkg.contains('mms') || pkg.contains('sms')) return 'SMS';
  return '';
}

class _Permission extends StatelessWidget {
  final bool done;
  final bool optional;
  final String title;
  final String why;
  final VoidCallback onTap;
  const _Permission({required this.done, required this.title, required this.why, required this.onTap, this.optional = false});

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(
        done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
        color: done ? const Color(0xFF15803D) : Theme.of(context).colorScheme.outline,
      ),
      title: Text(title),
      subtitle: Text(why),
      isThreeLine: true,
      trailing: done ? null : TextButton(onPressed: onTap, child: Text(optional ? 'Turn on' : 'Allow')),
      onTap: onTap,
    ),
  );
}

/// The full check of a message phone protection warned about, with AI if set up.
class _AlertDetail extends StatefulWidget {
  final GuardAlert alert;
  const _AlertDetail({required this.alert});
  @override
  State<_AlertDetail> createState() => _AlertDetailState();
}

class _AlertDetailState extends State<_AlertDetail> {
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
