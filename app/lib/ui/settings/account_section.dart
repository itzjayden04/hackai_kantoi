import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/account.dart';
import '../../auth/auth_service.dart';
import '../../cloud/outbox.dart';
import '../../history/history_log.dart';
import '../../report/report_store.dart';
import '../../state.dart';
import '../auth/privacy_notice.dart';
import '../check/result_page.dart';
import '../kit.dart';
import '../monitor/monitor_page.dart';
import '../theme.dart';
import '../vault/vault_page.dart';
import '../../vault/vault.dart';

/// One settings row: a tinted square icon, a title (and optional line), a
/// count pill or value, and a chevron when it opens something.
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? count;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;
  const SettingsRow(this.icon, this.title, {super.key, this.subtitle, this.count, this.value, this.trailing, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = color ?? K.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            TintIcon(icon, color: c, background: color == null ? K.surfaceMid : c.withValues(alpha: 0.1), size: 38, square: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.titleMedium?.copyWith(color: color ?? K.onSurface, fontWeight: FontWeight.w500),
                  ),
                  if (subtitle != null) Text(subtitle!, style: t.bodySmall?.copyWith(color: K.secondary)),
                ],
              ),
            ),
            if (count != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: K.surfaceMid, borderRadius: BorderRadius.circular(99)),
                child: Text(count!, style: t.labelMedium?.copyWith(color: K.primary)),
              ),
            if (value != null) Text(value!, style: t.labelMedium?.copyWith(color: K.secondary)),
            ?trailing,
            if (onTap != null && trailing == null) Icon(Icons.chevron_right_rounded, color: color ?? K.outline),
          ],
        ),
      ),
    );
  }
}

/// A titled group of rows on one white card.
class SettingsGroup extends StatelessWidget {
  final String title;
  final String? note;
  final bool live;
  final List<Widget> rows;
  const SettingsGroup(this.title, {super.key, this.note, this.live = false, required this.rows});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(title.toUpperCase(), style: t.labelMedium?.copyWith(color: K.secondary, letterSpacing: 0.8)),
                ),
                if (live) ...[const PulseDot(color: K.primary, size: 6), const SizedBox(width: 6)],
                if (note != null) Text(note!, style: t.labelMedium?.copyWith(color: live ? K.primary : K.secondary)),
              ],
            ),
          ),
          KCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (i, r) in rows.indexed) ...[if (i > 0) const Divider(indent: 68, endIndent: 16), r],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Top of Settings: the account, history, safe words, the monitor and the
/// privacy switches added in v1.2.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([auth, historyLog, cloudOutbox, reportStore, vault]),
    builder: (context, _) {
      final t = Theme.of(context).textTheme;
      final u = auth.user;
      final google = u?.method == SignInMethod.google;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (u != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: KCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: K.primaryFixed,
                                child: Text(
                                  u.initials,
                                  style: const TextStyle(color: K.primary, fontWeight: FontWeight.w700, fontSize: 20),
                                ),
                              ),
                              const Positioned(
                                right: -2,
                                bottom: -2,
                                child: CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.white,
                                  child: Icon(Icons.verified_rounded, size: 18, color: K.primary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u.fullName.isEmpty ? u.username : u.fullName, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(
                                  u.email,
                                  style: t.bodyMedium?.copyWith(color: K.secondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: K.surfaceMid, borderRadius: BorderRadius.circular(99)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(google ? Icons.g_mobiledata_rounded : Icons.mark_email_read_outlined, size: 16, color: K.primary),
                                      const SizedBox(width: 4),
                                      Text(google ? 'Google account' : 'Email verified', style: t.labelMedium?.copyWith(color: K.primary)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: K.error),
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Log out'),
                            onPressed: () async {
                              Navigator.of(context).popUntil((r) => r.isFirst);
                              await auth.signOut();
                            },
                          ),
                        ],
                      ),
                    ),
                    Container(
                      color: K.surfaceLow,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_outlined, size: 16, color: K.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              google ? 'Stays signed in on this phone' : 'Logs out after 7 days without use',
                              style: t.labelMedium?.copyWith(color: K.onSurfaceVariant),
                            ),
                          ),
                          Text('Protection always on', style: t.labelMedium?.copyWith(color: K.primary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SettingsGroup(
            'My activity',
            note: 'On this phone',
            rows: [
              SettingsRow(
                Icons.manage_search_rounded,
                'History',
                count: '${historyLog.entries.length}',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryLogPage())),
              ),
              SettingsRow(
                Icons.flag_outlined,
                'My reports',
                count: '${reportStore.reports.length}',
                onTap: () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  appState.tab.value = tabReport;
                },
              ),
              SettingsRow(
                Icons.key_rounded,
                'Safe word vault',
                subtitle: vault.count == 0 ? 'Not set up yet' : '${vault.count} safe word${vault.count == 1 ? '' : 's'} saved',
                onTap: () => openVault(context),
              ),
            ],
          ),
          SettingsGroup(
            'Protection',
            rows: [
              SettingsRow(
                Icons.radar_rounded,
                'Scam Monitor',
                subtitle: 'Watches your messaging apps for scams',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MonitorPage())),
              ),
            ],
          ),
          SettingsGroup(
            'Privacy & data',
            rows: [
              SettingsRow(
                Icons.volunteer_activism_outlined,
                'Share masked scam details to help others',
                subtitle: 'Only scam type, warning signs, website names and masked numbers. Never message text.',
                trailing: Switch(value: cloudOutbox.shareDetections, onChanged: cloudOutbox.setShareDetections),
              ),
              SettingsRow(Icons.outbox_outlined, 'Waiting to share', subtitle: 'Sent when you are online', count: '${cloudOutbox.items.length}'),
              SettingsRow(Icons.download_outlined, 'Download my data', value: 'JSON', onTap: () => _download(context)),
              SettingsRow(
                Icons.policy_outlined,
                'Privacy Notice',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyNoticePage())),
              ),
            ],
          ),
        ],
      );
    },
  );

  /// PDPA access right: everything Kantoi keeps about the user, as JSON.
  /// Safe words are left out on purpose; they never leave the vault.
  Future<void> _download(BuildContext context) async {
    final data = {
      'exported': DateTime.now().toIso8601String(),
      'account': auth.user?.toJson(),
      'history': historyLog.entries.map((e) => e.toJson()).toList(),
      'reports': reportStore.reports.map((r) => r.toJson()).toList(),
      'waitingToShare': cloudOutbox.items.map((i) => i.toJson()).toList(),
      'note': 'Safe words are not included. They stay encrypted in the vault on this phone.',
    };
    await SharePlus.instance.share(ShareParams(text: const JsonEncoder.withIndent('  ').convert(data), subject: 'My Kantoi data'));
  }
}

IconData historyIcon(HistoryType t) => switch (t) {
  HistoryType.check => Icons.shield_outlined,
  HistoryType.trace => Icons.hub_outlined,
  HistoryType.learn => Icons.school_outlined,
  HistoryType.report => Icons.flag_outlined,
};

/// Every check, trace, lesson and report, filterable, newest first.
class HistoryLogPage extends StatefulWidget {
  const HistoryLogPage({super.key});
  @override
  State<HistoryLogPage> createState() => _HistoryLogPageState();
}

class _HistoryLogPageState extends State<HistoryLogPage> {
  HistoryType? _type;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  (String, Color)? _verdict(HistoryEntry e) => switch (e.result) {
    'danger' => ('High risk', K.red),
    'suspicious' => ('Suspicious', K.orange),
    'caution' => ('Careful', K.amber),
    'safe' => ('No signs', K.primary),
    _ => null,
  };

  Widget _result(HistoryEntry e) {
    final t = Theme.of(context).textTheme;
    if (e.type == HistoryType.learn) {
      return e.result.isEmpty
          ? const SizedBox.shrink()
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: K.primaryContainer, borderRadius: BorderRadius.circular(99)),
              child: Text(e.result, style: t.labelMedium?.copyWith(color: Colors.white)),
            );
    }
    if (e.type == HistoryType.report) {
      final sent = e.result == 'sent';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: sent ? K.primary : K.surfaceMid, borderRadius: BorderRadius.circular(99)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sent) ...[const Icon(Icons.check_rounded, size: 14, color: Colors.white), const SizedBox(width: 4)],
            Text(sent ? 'Sent' : (e.result.isEmpty ? 'Draft' : e.result), style: t.labelMedium?.copyWith(color: sent ? Colors.white : K.secondary)),
          ],
        ),
      );
    }
    final v = _verdict(e);
    if (v == null) return e.result.isEmpty ? const SizedBox.shrink() : Pill(e.result, color: K.outline);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: v.$2.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: v.$2, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            v.$1.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: v.$2),
          ),
        ],
      ),
    );
  }

  void _open(HistoryEntry e) {
    switch (e.type) {
      case HistoryType.check:
        final inv = appState.checkAt(e.ref);
        if (inv != null) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultPage(inv: inv)));
        } else {
          showKToast(context, title: 'Not kept in detail', body: 'Only the summary of older checks is saved.');
        }
      case HistoryType.trace:
        Navigator.of(context).popUntil((r) => r.isFirst);
        appState.openTrace(e.ref);
      case HistoryType.report:
        Navigator.of(context).popUntil((r) => r.isFirst);
        appState.tab.value = tabReport;
      case HistoryType.learn:
        Navigator.of(context).popUntil((r) => r.isFirst);
        appState.tab.value = tabLearn;
    }
  }

  String _when(HistoryEntry e, String group) {
    final x = e.at;
    if (group == 'Today' || group == 'Yesterday') {
      return '${x.hour % 12 == 0 ? 12 : x.hour % 12}:${x.minute.toString().padLeft(2, '0')} ${x.hour < 12 ? 'AM' : 'PM'}';
    }
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${x.day} ${m[x.month - 1]} ${x.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListenableBuilder(
        listenable: historyLog,
        builder: (context, _) {
          final items = historyLog.filtered(type: _type, query: _q.text)..sort((a, b) => b.at.compareTo(a.at));
          final now = DateTime.now();
          final counts = <String, int>{};
          for (final e in items) {
            final g = historyGroup(e.at, now);
            counts[g] = (counts[g] ?? 0) + 1;
          }
          String? last;
          final rows = <Widget>[];
          for (final e in items) {
            final g = historyGroup(e.at, now);
            if (g != last) {
              final n = counts[g]!;
              rows.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
                  child: Row(
                    children: [
                      Expanded(child: Text(g, style: t.titleMedium)),
                      Text('$n record${n == 1 ? '' : 's'}', style: t.labelMedium?.copyWith(color: K.secondary)),
                    ],
                  ),
                ),
              );
              last = g;
            }
            final v = _verdict(e);
            final risky = v != null && (e.result == 'danger' || e.result == 'suspicious');
            rows.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Dismissible(
                  key: ValueKey('${e.type}${e.at.microsecondsSinceEpoch}${e.ref}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: const BoxDecoration(color: K.error, borderRadius: K.r16),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline_rounded, color: Colors.white),
                        SizedBox(height: 2),
                        Text(
                          'DELETE',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                        ),
                      ],
                    ),
                  ),
                  onDismissed: (_) => historyLog.remove(e),
                  child: KCard(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    onTap: () => _open(e),
                    child: Row(
                      children: [
                        TintIcon(
                          historyIcon(e.type),
                          color: risky ? v.$2 : K.primary,
                          background: risky ? K.errorContainer.withValues(alpha: 0.7) : K.surfaceMid,
                          size: 46,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                              const SizedBox(height: 2),
                              Text(
                                '${e.type.name[0].toUpperCase()}${e.type.name.substring(1)}  ·  ${_when(e, g)}'
                                '${e.detail.isEmpty ? '' : '  ·  ${e.detail}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyMedium?.copyWith(color: K.secondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _result(e),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(borderRadius: K.r16, boxShadow: K.shadow),
                child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Search by link, number or keyword',
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(borderRadius: K.r16, borderSide: BorderSide.none),
                    enabledBorder: const OutlineInputBorder(borderRadius: K.r16, borderSide: BorderSide.none),
                    suffixIcon: _q.text.isEmpty
                        ? null
                        : IconButton(tooltip: 'Clear', icon: const Icon(Icons.cancel_outlined), onPressed: () => setState(() => _q.clear())),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  children: [
                    for (final (label, type) in [
                      ('All', null),
                      ('Check', HistoryType.check),
                      ('Trace', HistoryType.trace),
                      ('Learn', HistoryType.learn),
                      ('Report', HistoryType.report),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Filter(
                          label: '$label (${type == null ? historyLog.entries.length : historyLog.count(type)})',
                          selected: _type == type,
                          onTap: () => setState(() => _type = type),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const PulseDot(color: K.primary, size: 6),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('SAVED ON THIS PHONE', style: t.labelMedium?.copyWith(color: K.secondary, letterSpacing: 0.8)),
                  ),
                  Text('Swipe left to delete', style: t.labelMedium?.copyWith(color: K.secondary)),
                ],
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      const TintIcon(Icons.history_rounded, background: K.surfaceMid, size: 56),
                      const SizedBox(height: 12),
                      Text(
                        _q.text.isEmpty ? 'Nothing here yet.' : 'Nothing matches "${_q.text}".',
                        textAlign: TextAlign.center,
                        style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ...rows,
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_user_outlined, size: 16, color: K.secondary),
                  const SizedBox(width: 6),
                  Text('Kept only on this phone', style: t.labelMedium?.copyWith(color: K.secondary)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Kantoi keeps your latest ${HistoryLog.maxEntries} records. Delete everything any time in Settings.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: K.secondary),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Filter({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: K.fast,
    decoration: BoxDecoration(
      color: selected ? K.primaryContainer : Colors.white,
      borderRadius: BorderRadius.circular(99),
      boxShadow: selected ? null : K.shadow,
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: selected ? Colors.white : K.onSurface),
          ),
        ),
      ),
    ),
  );
}
