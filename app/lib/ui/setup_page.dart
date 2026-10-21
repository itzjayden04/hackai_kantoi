import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../guard/guard_control.dart';
import 'kit.dart';
import 'theme.dart';

/// Whether the first-run setup has been finished on this phone.
Future<bool> setupSeen() async {
  try {
    return (await SharedPreferences.getInstance()).getBool('setupSeen') ?? false;
  } catch (_) {
    return true;
  }
}

Future<void> _markSetupSeen() async {
  try {
    await (await SharedPreferences.getInstance()).setBool('setupSeen', true);
  } catch (_) {}
}

/// First run: welcome, then every permission one by one, then "you're
/// protected". [onDone] opens the app.
class SetupFlow extends StatefulWidget {
  final VoidCallback onDone;
  final bool startAtPermissions;
  const SetupFlow({super.key, required this.onDone, this.startAtPermissions = false});
  @override
  State<SetupFlow> createState() => _SetupFlowState();
}

class _SetupFlowState extends State<SetupFlow> {
  late int _page = widget.startAtPermissions ? 1 : 0;

  void _finish() {
    _markSetupSeen();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Back goes to the previous setup page, and leaves only from the first.
    canPop: _page == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _page > 0) setState(() => _page--);
    },
    child: Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: K.medium,
          switchInCurve: K.curve,
          transitionBuilder: (w, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a),
              child: w,
            ),
          ),
          child: switch (_page) {
            0 => _Welcome(key: const ValueKey(0), onNext: () => setState(() => _page = 1)),
            1 => PermissionsStep(key: const ValueKey(1), onDone: () => setState(() => _page = 2), onSkip: _finish),
            _ => _AllSet(key: const ValueKey(2), onDone: _finish),
          },
        ),
      ),
    ),
  );
}

class _Welcome extends StatelessWidget {
  final VoidCallback onNext;
  const _Welcome({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            children: [
              const Reveal(child: KantoiLogo(size: 40)),
              const SizedBox(height: 28),
              const Reveal(index: 1, child: _DemoCatch()),
              const SizedBox(height: 28),
              Reveal(index: 2, child: Text('Not sure if it\'s a scam?\nJust ask Kantoi.', style: t.headlineMedium)),
              const SizedBox(height: 8),
              Reveal(
                index: 3,
                child: Text(
                  'Kantoi checks messages, links, calls, QR codes and files, explains what it found in plain words, '
                  'and helps you report it.',
                  style: t.bodyLarge?.copyWith(color: K.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 20),
              const Reveal(
                index: 4,
                child: _Feature(
                  Icons.visibility_outlined,
                  'Watches in the background',
                  'Chats, SMS, calls, links and new apps, with a warning the moment something looks wrong.',
                ),
              ),
              const Reveal(
                index: 5,
                child: _Feature(
                  Icons.lock_outline_rounded,
                  'Private by design',
                  'Messages are checked on your phone. Your name, IC and account numbers are hidden before anything goes online.',
                ),
              ),
              const Reveal(
                index: 6,
                child: _Feature(
                  Icons.travel_explore_rounded,
                  'Traces who is behind it',
                  'Builds a live map of the websites, servers and numbers linked to a scam.',
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: FilledButton(
            onPressed: onNext,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text('Get started'), SizedBox(width: 8), Icon(Icons.arrow_forward_rounded)],
            ),
          ),
        ),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Feature(this.icon, this.title, this.body);
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: K.surfaceLow, borderRadius: K.r8),
            child: Icon(icon, color: K.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleMedium),
                const SizedBox(height: 2),
                Text(body, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A sample scam SMS that gets "caught" on a loop, to show what Kantoi does.
class _DemoCatch extends StatefulWidget {
  const _DemoCatch();
  @override
  State<_DemoCatch> createState() => _DemoCatchState();
}

class _DemoCatchState extends State<_DemoCatch> {
  bool _caught = false;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 2400), (_) => setState(() => _caught = !_caught));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sms_outlined, size: 18, color: K.outline),
              const SizedBox(width: 6),
              Text('SMS · sample', style: t.labelMedium?.copyWith(color: K.outline)),
              const Spacer(),
              Text('Just now', style: t.labelSmall?.copyWith(color: K.outline)),
            ],
          ),
          const SizedBox(height: 8),
          Text('"Pos Laju: Your parcel is on hold for unpaid tax RM3.50. Pay now at poslaju-my-pay.top"', style: t.bodyMedium),
          AnimatedSize(
            duration: K.medium,
            curve: K.curve,
            child: _caught
                ? Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: K.red.withValues(alpha: 0.08),
                      borderRadius: K.r8,
                      border: Border.all(color: K.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.gpp_bad_rounded, color: K.red),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Likely a scam', style: t.titleMedium?.copyWith(color: K.red)),
                              Text('Fake courier link, new website, asks for payment', style: t.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Walks through every permission in [setupItems]. Each card has one button
/// that opens the right Android screen; coming back refreshes the list and
/// the next missing one is highlighted.
class PermissionsStep extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback? onSkip;
  const PermissionsStep({super.key, required this.onDone, this.onSkip});
  @override
  State<PermissionsStep> createState() => _PermissionsStepState();
}

class _PermissionsStepState extends State<PermissionsStep> with WidgetsBindingObserver {
  GuardStatus _s = const GuardStatus();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setGuardEnabled(true);
    _refresh();
    // Some grants (the notification pop-up) don't pause the app, so poll too.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
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

  Future<void> _allow(SetupItem i) async {
    if (i.key == 'accessibility') {
      await showKSheet(
        context,
        icon: Icons.accessibility_new_rounded,
        title: 'One switch to turn on',
        message:
            'Android will open its Accessibility settings.\n\n'
            '1. Tap "Installed apps" (or "Downloaded apps").\n'
            '2. Tap "Kantoi".\n'
            '3. Switch it on and tap "Allow".\n\n'
            'If it says the setting is restricted, come back here and tap "Allow restricted settings" first.',
        primary: 'Open settings',
        onPrimary: () => openGuardSetting('accessibility'),
        secondary: 'Allow restricted settings',
        onSecondary: () => openGuardSetting('appDetails'),
      );
      return;
    }
    await openGuardSetting(i.key);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final done = _s.setupDone;
    final total = setupItems.length;
    final next = setupItems.where((i) => !_s.has(i.key)).firstOrNull;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Text('Setup', style: t.titleMedium),
              const Spacer(),
              if (widget.onSkip != null) TextButton(onPressed: widget.onSkip, child: const Text('Later')),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Text('Turn on your shield', style: t.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Kantoi needs these to catch scams before they reach you. Tap each one and follow the arrows.',
                style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              KCard(
                color: K.primaryContainer,
                borderColor: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shield_rounded, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('$done of $total turned on', style: t.titleMedium?.copyWith(color: Colors.white)),
                        ),
                        Text(
                          '${(100 * done / total).round()}%',
                          style: t.titleMedium?.copyWith(color: Colors.white, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    KProgressBar(value: done / total, color: K.onTertiaryContainer),
                    const SizedBox(height: 8),
                    Text(
                      next == null ? 'All set. You are fully protected.' : 'Next: ${next.title}',
                      style: t.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final (n, i) in setupItems.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Reveal(
                    index: n,
                    child: _PermCard(item: i, done: _s.has(i.key), highlight: identical(i, next), onAllow: () => _allow(i)),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 16, color: K.outline),
                  const SizedBox(width: 6),
                  Expanded(child: Text('You can turn any of these off later in Android Settings.', style: t.bodySmall)),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: FilledButton.icon(
            onPressed: _s.setupComplete ? widget.onDone : (next == null ? null : () => _allow(next)),
            icon: Icon(_s.setupComplete ? Icons.shield_rounded : Icons.arrow_forward_rounded),
            label: Text(_s.setupComplete ? 'Finish setup' : 'Turn on: ${next?.title ?? ''}'),
          ),
        ),
      ],
    );
  }
}

class _PermCard extends StatelessWidget {
  final SetupItem item;
  final bool done;
  final bool highlight;
  final VoidCallback onAllow;
  const _PermCard({required this.item, required this.done, required this.highlight, required this.onAllow});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: K.medium,
      decoration: BoxDecoration(
        borderRadius: K.r16,
        boxShadow: highlight ? [BoxShadow(color: K.primary.withValues(alpha: 0.15), blurRadius: 16, spreadRadius: 1)] : const [],
      ),
      child: KCard(
        onTap: done ? null : onAllow,
        borderColor: highlight ? K.primary : null,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: done ? K.green.withValues(alpha: 0.1) : K.surfaceLow, borderRadius: K.r8),
              child: Icon(item.icon, color: done ? K.green : K.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text(item.why, style: t.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: K.fast,
              transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
              child: done
                  ? const Icon(Icons.check_circle_rounded, key: ValueKey(1), color: K.green, size: 28)
                  : FilledButton.tonal(
                      key: const ValueKey(0),
                      onPressed: onAllow,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
                      child: const Text('Allow'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllSet extends StatelessWidget {
  final VoidCallback onDone;
  const _AllSet({super.key, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
            children: [
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.elasticOut,
                  builder: (_, v, _) => Transform.scale(
                    scale: v,
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: K.green.withValues(alpha: 0.12)),
                      child: const Icon(Icons.verified_user_rounded, size: 56, color: K.green),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Reveal(
                index: 1,
                child: Text('You\'re protected', textAlign: TextAlign.center, style: t.headlineMedium),
              ),
              const SizedBox(height: 6),
              Reveal(
                index: 2,
                child: Text(
                  'Kantoi is now watching for scams in the background.',
                  textAlign: TextAlign.center,
                  style: t.bodyLarge?.copyWith(color: K.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 28),
              Reveal(index: 3, child: Text('What happens next', style: t.titleMedium)),
              const SizedBox(height: 8),
              const Reveal(index: 4, child: _Next(1, 'Use your phone normally. Kantoi works quietly in the background.')),
              const Reveal(
                index: 5,
                child: _Next(2, 'If a message, call or website looks like a scam, Kantoi pauses it and tells you why.'),
              ),
              const Reveal(index: 6, child: _Next(3, 'Got something suspicious right now? Paste it in the Check tab.')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: FilledButton(onPressed: onDone, child: const Text('Start using Kantoi')),
        ),
      ],
    );
  }
}

class _Next extends StatelessWidget {
  final int n;
  final String text;
  const _Next(this.n, this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: K.primary,
          child: Text(
            '$n',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    ),
  );
}

/// The Kantoi mark and name.
class KantoiLogo extends StatelessWidget {
  final double size;
  const KantoiLogo({super.key, this.size = 30});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [K.primaryContainer, K.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(Icons.shield_rounded, color: Colors.white, size: size * 0.6),
      ),
      SizedBox(width: size * 0.3),
      Text(
        'Kantoi',
        style: TextStyle(fontSize: size * 0.62, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: K.primary),
      ),
    ],
  );
}
