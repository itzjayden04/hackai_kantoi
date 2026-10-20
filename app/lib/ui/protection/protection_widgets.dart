import 'package:flutter/material.dart';

import '../../guard/guard_control.dart';
import '../kit.dart';
import '../phone_guard.dart';
import '../theme.dart';

/// The dark blue master card: big switch, since when, and real counters.
class ShieldCard extends StatelessWidget {
  final GuardStatus s;
  final bool loaded;
  final ValueChanged<bool> onChanged;
  const ShieldCard({super.key, required this.s, required this.loaded, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final on = s.enabled;
    final missing = setupItems.where((i) => !s.has(i.key)).length;
    final since = s.since;
    final sub = !loaded
        ? 'Checking phone protection...'
        : !on
            ? 'Turn it on and Kantoi checks calls, messages, websites, new apps and pictures for you.'
            : missing > 0
                ? '$missing permission${missing == 1 ? '' : 's'} still needed for full protection.'
                : since != null
                    ? 'Guarding this phone since ${_when(context, since)}.'
                    : 'Guarding this phone.';
    return AnimatedContainer(
      duration: K.medium,
      curve: K.curve,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: on ? const [K.primaryContainer, K.primary] : const [K.inverseSurface, Color(0xFF2E4058)],
        ),
        boxShadow: [BoxShadow(color: K.primary.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(on ? Icons.verified_user_rounded : Icons.shield_outlined, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                on ? const PulseDot(color: K.onTertiaryContainer, size: 7) : const SizedBox.shrink(),
                if (on) const SizedBox(width: 6),
                Text('PHONE PROTECTION',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Colors.white.withValues(alpha: 0.75))),
              ]),
              const SizedBox(height: 2),
              Text(on ? 'Auto-protection: on' : 'Auto-protection: off',
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
          if (loaded)
            Switch(
              value: on,
              onChanged: onChanged,
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? K.onTertiaryContainer : Colors.white24),
            ),
        ]),
        const SizedBox(height: 12),
        Text(sub, style: TextStyle(fontSize: 14, height: 1.4, color: Colors.white.withValues(alpha: 0.82))),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.16), borderRadius: K.r16),
          child: Row(children: [
            _Stat('${s.stat('warnings')}', 'Warnings shown'),
            _divider(),
            _Stat('${s.stat('pages')}', 'Pages blocked'),
            _divider(),
            _Stat('${s.stat('calls')}', 'Calls flagged'),
          ]),
        ),
      ]),
    );
  }

  static String _when(BuildContext context, DateTime t) {
    final now = DateTime.now();
    final time = TimeOfDay.fromDateTime(t).format(context);
    if (t.year == now.year && t.month == now.month && t.day == now.day) return time;
    return MaterialLocalizations.of(context).formatShortMonthDay(t);
  }

  Widget _divider() => Container(width: 1, height: 32, color: Colors.white.withValues(alpha: 0.16));
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: double.tryParse(value) ?? 0),
            duration: K.medium,
            curve: K.curve,
            builder: (_, v, _) => Text('${v.round()}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
        ]),
      );
}

/// One guard: icon, name, counter, plain explanation, permission state, switch.
class GuardRow extends StatelessWidget {
  final Guard guard;
  final GuardStatus s;
  final ValueChanged<bool> onChanged;
  final VoidCallback onFix;
  const GuardRow({super.key, required this.guard, required this.s, required this.onChanged, required this.onFix});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final unsupported = guard.key == 'calls' && !s.callScreeningSupported;
    final on = s.enabled && s.guardOn(guard.key) && !unsupported;
    final needs = guard.needs == null ? null : setupItems.where((i) => i.key == guard.needs).firstOrNull;
    final missing = needs != null && !s.has(needs.key) && !unsupported;
    final count = s.stat(guard.stat);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedContainer(
          duration: K.fast,
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: on ? K.surfaceHigh : K.surfaceLow, borderRadius: const BorderRadius.all(Radius.circular(12))),
          child: Icon(guard.icon, color: on ? K.primaryContainer : K.outline),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(guard.title, style: t.titleMedium),
              if (count > 0) Pill('$count ${guard.unit}', color: K.primaryContainer),
            ]),
            const SizedBox(height: 4),
            Text(guard.what, style: t.bodySmall),
            if (unsupported) ...[
              const SizedBox(height: 6),
              Text('Needs Android 10 or newer.', style: t.bodySmall?.copyWith(color: K.outline)),
            ] else if (missing) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: onFix,
                borderRadius: K.r8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: K.amber),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Needs: ${needs.title}. Tap to allow',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: K.amber)),
                    ),
                  ]),
                ),
              ),
            ] else if (on && needs != null) ...[
              const SizedBox(height: 6),
              const Row(children: [
                Icon(Icons.check_circle_rounded, size: 16, color: K.green),
                SizedBox(width: 6),
                Text('Allowed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: K.green)),
              ]),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Switch(value: on, onChanged: s.enabled && !unsupported ? onChanged : null),
      ]),
    );
  }
}

/// One recent warning.
class WarningTile extends StatelessWidget {
  final GuardAlert a;
  final VoidCallback onTap;
  const WarningTile({super.key, required this.a, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final level = guardLevel(a.level);
    final color = riskColor(level);
    final (icon, kind) = guardKind(a.kind);
    final from = guardAppName(a.app);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('$kind · ${a.label}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                ),
                Text(_ago(context, a.at), style: t.bodySmall),
              ]),
              const SizedBox(height: 2),
              Text(a.chat, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              if (a.reasons.isNotEmpty || from.isNotEmpty)
                Text(
                  [a.reasons.take(2).join(', '), from].where((x) => x.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall,
                ),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: K.outline),
        ]),
      ),
    );
  }

  static String _ago(BuildContext context, DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return TimeOfDay.fromDateTime(at).format(context);
    if (d.inDays == 1) return 'Yesterday';
    return MaterialLocalizations.of(context).formatShortMonthDay(at);
  }
}
