import 'package:flutter/material.dart';

import '../bridge/bridge.dart';
import '../engine/models.dart';
import '../guard/guard_control.dart';
import '../state.dart';
import 'phone_guard.dart';
import 'relationship_page.dart';
import 'result_view.dart';
import 'theme.dart';

/// Messages the browser extension flagged in WhatsApp Web and Telegram Web.
class LivePage extends StatelessWidget {
  const LivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final connected = appState.extensionConnected;
        return PageBody(
          children: [
            Text('Live protection', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            if (guardSupported) ...[
              Text(
                'Kantoi checks the messages you receive on this phone and steps in before you pay a scammer.',
                style: t.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              const PhoneGuardSection(),
            ] else ...[
              Text(
                'With the Kantoi browser extension, every message you receive in WhatsApp Web or Telegram Web is checked as it arrives.',
                style: t.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(
                    connected ? Icons.shield_rounded : Icons.shield_outlined,
                    color: connected ? const Color(0xFF15803D) : Theme.of(context).colorScheme.outline,
                    size: 32,
                  ),
                  title: Text(
                    !bridgeSupported
                        ? 'Live protection needs the Kantoi desktop app'
                        : connected
                        ? 'Extension connected'
                        : 'Waiting for the browser extension',
                  ),
                  subtitle: Text(
                    appState.serverError ??
                        (connected
                            ? 'Kantoi is watching your open chats.'
                            : 'Install the Kantoi extension in Chrome or Edge, then open web.whatsapp.com or web.telegram.org.'),
                  ),
                ),
              ),
            ],
            if (guardSupported)
              ...[]
            else if (appState.live.isEmpty) ...[
              const SizedBox(height: 24),
              Center(child: Text('No warnings yet. Flagged messages will appear here.', style: t.bodyMedium)),
            ] else ...[
              const SectionTitle('Flagged messages'),
              for (final item in appState.live)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _LiveDetail(item: item))),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(riskIcon(item.investigation.verdict.level), color: riskColor(item.investigation.verdict.level)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${item.chat} · ${riskLabel(item.investigation.verdict.level)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  if (item.conversation != null && item.conversation!.level.index >= RiskLevel.caution.index)
                                    Text(
                                      'Conversation risk ${item.conversation!.score}: ${riskLabel(item.conversation!.level)}',
                                      style: t.bodySmall?.copyWith(color: riskColor(item.conversation!.level)),
                                    ),
                                ],
                              ),
                            ),
                            Text(TimeOfDay.fromDateTime(item.at).format(context), style: t.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _LiveDetail extends StatelessWidget {
  final LiveItem item;
  const _LiveDetail({required this.item});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(item.chat)),
    body: PageBody(
      children: [
        ResultView(inv: item.investigation),
        if (item.conversation != null) ...[const SectionTitle('The whole conversation'), RelationshipResult(report: item.conversation!)],
      ],
    ),
  );
}
