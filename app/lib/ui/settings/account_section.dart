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

/// Top of Settings: the account, history, safe words, the monitor and the
/// privacy switches added in v1.2.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([auth, historyLog, cloudOutbox, reportStore]),
        builder: (context, _) {
          final t = Theme.of(context).textTheme;
          final u = auth.user;
          Widget row(IconData i, String title, {String? value, VoidCallback? onTap, Color? color}) => ListTile(
                leading: Icon(i, color: color ?? K.primary),
                title: Text(title, style: TextStyle(color: color)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (value != null) Text(value, style: t.bodySmall),
                  if (onTap != null) const Icon(Icons.chevron_right_rounded, color: K.outline),
                ]),
                onTap: onTap,
              );
          Widget group(String title, List<Widget> rows) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text(title.toUpperCase(), style: t.labelSmall?.copyWith(color: K.outline))),
                  KCard(padding: EdgeInsets.zero, child: Column(children: rows)),
                ]),
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (u != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: KCard(
                  child: Row(children: [
                    CircleAvatar(radius: 26, backgroundColor: K.primaryContainer, child: Text(u.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(u.fullName.isEmpty ? u.email : u.fullName, style: t.titleMedium),
                        Text(u.email, style: t.bodySmall),
                        const SizedBox(height: 4),
                        Pill(u.method == SignInMethod.google ? 'Signed in with Google' : 'Email account', color: K.primary),
                      ]),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        await auth.signOut();
                      },
                      child: const Text('Log out'),
                    ),
                  ]),
                ),
              ),
            group('My activity', [
              row(Icons.history_rounded, 'History', value: '${historyLog.entries.length}', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryLogPage()))),
              row(Icons.flag_outlined, 'My reports', value: '${reportStore.reports.length}', onTap: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                appState.tab.value = tabReport;
              }),
              row(Icons.key_rounded, 'Safe word vault', onTap: () => openVault(context)),
              row(Icons.radar_rounded, 'Scam Monitor', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MonitorPage()))),
            ]),
            group('Privacy', [
              SwitchListTile(
                secondary: const Icon(Icons.volunteer_activism_outlined, color: K.primary),
                value: cloudOutbox.shareDetections,
                onChanged: cloudOutbox.setShareDetections,
                title: const Text('Share masked scam details to help others'),
                subtitle: const Text('Only scam type, warning signs, website names and masked numbers. Never message text.'),
              ),
              row(Icons.outbox_outlined, 'Waiting to share', value: '${cloudOutbox.items.length}'),
              row(Icons.download_outlined, 'Download my data', onTap: () => _download(context)),
              row(Icons.policy_outlined, 'Privacy Notice', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyNoticePage()))),
            ]),
          ]);
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

  Widget _result(HistoryEntry e) {
    if (e.type == HistoryType.learn) return Pill(e.result, color: K.primary);
    if (e.type == HistoryType.report) return Pill(e.result == 'sent' ? 'Sent' : e.result, color: K.primary);
    final (label, c) = switch (e.result) {
      'danger' => ('High', K.red),
      'suspicious' => ('Suspicious', K.orange),
      'caution' => ('Careful', K.amber),
      'safe' => ('No signs', K.green),
      _ => (e.result, K.outline),
    };
    return label.isEmpty ? const SizedBox.shrink() : Pill(label, color: c);
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListenableBuilder(
        listenable: historyLog,
        builder: (context, _) {
          final items = historyLog.filtered(type: _type, query: _q.text);
          final now = DateTime.now();
          String? last;
          final rows = <Widget>[];
          for (final e in items) {
            final g = historyGroup(e.at, now);
            if (g != last) {
              rows.add(Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text(g, style: t.labelLarge?.copyWith(color: K.outline))));
              last = g;
            }
            rows.add(Dismissible(
              key: ValueKey('${e.type}${e.at.microsecondsSinceEpoch}${e.ref}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: const BoxDecoration(color: K.red, borderRadius: K.r16),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
              ),
              onDismissed: (_) => historyLog.remove(e),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: KCard(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  onTap: () => _open(e),
                  child: Row(children: [
                    CircleAvatar(radius: 20, backgroundColor: K.surfaceHigh, child: Icon(historyIcon(e.type), color: K.primary, size: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                            '${e.type.name[0].toUpperCase()}${e.type.name.substring(1)} · ${e.at.hour % 12 == 0 ? 12 : e.at.hour % 12}:${e.at.minute.toString().padLeft(2, '0')} ${e.at.hour < 12 ? 'AM' : 'PM'}'
                            '${e.detail.isEmpty ? '' : ' · ${e.detail}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    _result(e),
                  ]),
                ),
              ),
            ));
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search history', isDense: true),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (label, type) in [('All', null), ('Check', HistoryType.check), ('Trace', HistoryType.trace), ('Learn', HistoryType.learn), ('Report', HistoryType.report)])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(type == null ? label : '$label (${historyLog.count(type)})'),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                  ),
              ]),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text('Nothing here yet.', textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
              ),
            ...rows,
          ]);
        },
      ),
    );
  }
}
