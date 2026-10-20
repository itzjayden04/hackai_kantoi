import 'package:flutter/material.dart';

import '../guard/guard_control.dart';
import 'kit.dart';
import 'phone_guard.dart';
import 'protection/protection_widgets.dart';
import 'theme.dart';

/// Protection centre (Stitch "protection"): the master switch with real
/// counters, one switch per guard with its permission, and recent warnings.
/// Opened from the "Protected" pill in the top bar.
class ProtectionPage extends StatefulWidget {
  /// For tests: the status to show instead of asking Android.
  final GuardStatus? initial;
  const ProtectionPage({super.key, this.initial});
  @override
  State<ProtectionPage> createState() => _ProtectionPageState();
}

class _ProtectionPageState extends State<ProtectionPage> with WidgetsBindingObserver {
  late GuardStatus _s = widget.initial ?? const GuardStatus(supported: true);
  late bool _loaded = widget.initial != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initial == null) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android settings is the moment a permission changes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.initial == null) _refresh();
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
  Future<void> _master(bool on) async {
    await setGuardEnabled(on);
    if (on) {
      final next = setupItems.where((i) => !_s.has(i.key)).firstOrNull;
      if (next != null) await openGuardSetting(next.key);
    }
    await _refresh();
    if (mounted) {
      showKToast(context,
          title: on ? 'Auto-protection is on' : 'Auto-protection is off',
          body: on ? 'Kantoi will warn you about scams, even when the app is closed.' : 'Kantoi will not check anything until you turn it back on.',
          icon: on ? Icons.verified_user_rounded : Icons.shield_outlined,
          color: on ? K.green : K.outline);
    }
  }

  Future<void> _toggle(Guard g, bool on) async {
    await setGuard(g.key, on);
    if (on && g.needs != null && !_s.has(g.needs!)) await openGuardSetting(g.needs!);
    await _refresh();
  }

  Future<void> _preview() async {
    if (!_s.overlay && !_s.accessibility) {
      await showKSheet<void>(
        context,
        title: 'Allow warnings on top first',
        icon: Icons.layers_outlined,
        message: 'Kantoi needs "Display over other apps" to show its warning cards on top of other apps.',
        primary: 'Allow',
        onPrimary: () => openGuardSetting('overlay'),
        secondary: 'Not now',
      );
      return;
    }
    Widget option(IconData icon, String title, String what, String kind) => ListTile(
          leading: Icon(icon, color: K.primaryContainer),
          title: Text(title),
          subtitle: Text(what),
          onTap: () {
            Navigator.pop(context);
            previewWarning(kind);
          },
        );
    await showKSheet<void>(
      context,
      title: 'See what a warning looks like',
      icon: Icons.visibility_outlined,
      message: 'Each one is a sample with made-up details.',
      body: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          option(Icons.back_hand_outlined, 'Pause card', 'Over a chat when a message looks like a scam', 'pause'),
          option(Icons.phone_in_talk_outlined, 'Call warning', 'While a risky number is ringing', 'call'),
          option(Icons.block_rounded, 'Closed website', 'After Kantoi closes a scam page', 'site'),
          option(Icons.shield_outlined, 'Chat badge', 'The risk of the chat you have open', 'badge'),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final active = _s.enabled ? guards.where((g) => _s.guardOn(g.key)).length : 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Protection centre')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: PageBody(children: [
          Reveal(index: 0, child: ShieldCard(s: _s, loaded: _loaded, onChanged: _master)),
          SectionTitle('What Kantoi watches', trailing: Pill('$active on', color: active > 0 ? K.green : K.outline)),
          Reveal(
            index: 1,
            child: KCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final (i, g) in guards.indexed) ...[
                  if (i > 0) const Divider(indent: 74),
                  GuardRow(guard: g, s: _s, onChanged: (v) => _toggle(g, v), onFix: () => openGuardSetting(g.needs!)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Reveal(
            index: 2,
            child: KCard(
              color: K.surfaceLow,
              borderColor: Colors.transparent,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.lock_outline_rounded, size: 20, color: K.primaryContainer),
                  const SizedBox(width: 8),
                  Text('Checked on this phone', style: t.titleMedium),
                ]),
                const SizedBox(height: 6),
                Text('Calls, chats, websites, new apps and pictures are checked on this phone. Kantoi only sees the number of a call, never the call itself.',
                    style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.cloud_outlined, size: 18, color: K.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('When a new message has a link, Kantoi may look that link up online to see where it really leads.',
                        style: t.bodySmall),
                  ),
                ]),
              ]),
            ),
          ),
          SectionTitle(
            'Recent warnings',
            trailing: _s.recent.isEmpty
                ? null
                : TextButton(
                    onPressed: () async {
                      await clearGuardAlerts();
                      await _refresh();
                    },
                    child: const Text('Clear'),
                  ),
          ),
          if (_s.recent.isEmpty)
            KCard(
              child: Row(children: [
                const Icon(Icons.verified_user_outlined, color: K.green),
                const SizedBox(width: 12),
                Expanded(child: Text(_s.enabled ? 'No warnings yet. Kantoi will list them here.' : 'Turn on auto-protection to get warnings.', style: t.bodyMedium)),
              ]),
            )
          else
            KCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final (i, a) in _s.recent.take(10).indexed) ...[
                  if (i > 0) const Divider(indent: 66),
                  WarningTile(a: a, onTap: () => openGuardAlert(context, a)),
                ],
              ]),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _preview,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('See what a warning looks like'),
          ),
          const SizedBox(height: 16),
          Text(
            'If Android says a setting is restricted: open Settings, then Apps, then Kantoi, tap the three dots at the top and choose '
            '"Allow restricted settings". Android does this for apps installed outside the Play Store.',
            style: t.bodySmall,
          ),
        ]),
      ),
    );
  }
}
