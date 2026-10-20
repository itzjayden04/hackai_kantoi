import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../awareness/guardian.dart';
import '../engine/models.dart';
import 'theme.dart';

/// Opens WhatsApp or SMS with a short pre-filled alert to the guardian. The
/// user still has to press send there. Falls back to copying the text.
Future<void> tellGuardian(BuildContext context, {Investigation? inv, bool emergency = false}) async {
  final g = guardianStore.ready;
  if (g == null) return;
  final text = guardianAlert(guardianName: g.name, inv: inv, emergency: emergency);
  final m = ScaffoldMessenger.of(context);
  var ok = false;
  try {
    ok = await launchUrl(guardianUri(g, text), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) {
    await Clipboard.setData(ClipboardData(text: text));
    m.showSnackBar(SnackBar(content: Text('Could not open ${g.useSms ? 'SMS' : 'WhatsApp'}. The alert was copied, so you can paste it to ${g.name}.')));
  }
}

/// The "Tell [name]" button. Shows nothing until a guardian is set up with
/// consent, so it never gets in the way.
class GuardianAlertButton extends StatefulWidget {
  final Investigation? inv;
  final bool emergency;
  const GuardianAlertButton({super.key, this.inv, this.emergency = false});
  @override
  State<GuardianAlertButton> createState() => _GuardianAlertButtonState();
}

class _GuardianAlertButtonState extends State<GuardianAlertButton> {
  @override
  void initState() {
    super.initState();
    guardianStore.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: guardianStore,
        builder: (context, _) {
          final g = guardianStore.ready;
          if (g == null) return const SizedBox.shrink();
          return FilledButton.tonalIcon(
            icon: const Icon(Icons.family_restroom_rounded),
            label: Text('Tell ${g.name.trim()}'),
            onPressed: () => tellGuardian(context, inv: widget.inv, emergency: widget.emergency),
          );
        },
      );
}

/// Add, change or remove the trusted family member.
class GuardianPage extends StatefulWidget {
  const GuardianPage({super.key});
  @override
  State<GuardianPage> createState() => _GuardianPageState();
}

class _GuardianPageState extends State<GuardianPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _consent = false;
  bool _sms = false;

  @override
  void initState() {
    super.initState();
    _fill();
    guardianStore.load().then((_) {
      if (mounted) setState(_fill);
    });
  }

  void _fill() {
    final g = guardianStore.guardian;
    if (g == null) return;
    _name.text = g.name;
    _phone.text = g.phone;
    _consent = g.consent;
    _sms = g.useSms;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _phoneOk => normalisePhone(_phone.text) != null;

  Future<void> _save() async {
    await guardianStore.save(Guardian(name: _name.text.trim(), phone: _phone.text.trim(), consent: _consent, useSms: _sms));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_consent ? 'Saved. Kantoi will offer to tell ${_name.text.trim()} when something looks dangerous.' : 'Saved.')));
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = _name.text.trim().isEmpty ? 'them' : _name.text.trim();
    final canSave = _name.text.trim().isNotEmpty && _phoneOk;
    final preview = guardianAlert(guardianName: _name.text, inv: null);
    return Scaffold(
      appBar: AppBar(title: const Text('Family guardian')),
      body: PageBody(children: [
        Text('Pick someone you trust, like a son, daughter or close friend. When Kantoi finds something very likely to be a scam, '
            'or you open "I already paid", you can tell them in one tap.', style: t.bodyLarge?.copyWith(height: 1.4)),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Their name', hintText: 'e.g. Aisyah'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Their phone number',
            hintText: 'e.g. 012-345 6789',
            errorText: _phone.text.isNotEmpty && !_phoneOk ? 'This does not look like a phone number' : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.chat_outlined), label: Text('WhatsApp')),
            ButtonSegment(value: true, icon: Icon(Icons.sms_outlined), label: Text('SMS')),
          ],
          selected: {_sms},
          onSelectionChanged: (s) => setState(() => _sms = s.first),
        ),
        const SizedBox(height: 10),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _consent,
          onChanged: (v) => setState(() => _consent = v ?? false),
          title: Text('I agree Kantoi can prepare alerts to $name'),
          subtitle: const Text('Kantoi opens WhatsApp or SMS with the alert ready. Nothing is sent until you press send. '
              'The alert never includes the message itself or your personal details.'),
        ),
        const SectionTitle('What they will see'),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(padding: const EdgeInsets.all(14), child: Text(preview, style: t.bodyMedium?.copyWith(height: 1.4))),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: canSave ? _save : null, child: const Text('Save guardian')),
        if (guardianStore.guardian != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              await guardianStore.clear();
              if (context.mounted) Navigator.of(context).maybePop();
            },
            child: const Text('Remove guardian'),
          ),
        ],
      ]),
    );
  }
}

/// Small status card for the Learn tab and Settings.
class GuardianStatusTile extends StatefulWidget {
  const GuardianStatusTile({super.key});
  @override
  State<GuardianStatusTile> createState() => _GuardianStatusTileState();
}

class _GuardianStatusTileState extends State<GuardianStatusTile> {
  @override
  void initState() {
    super.initState();
    guardianStore.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: guardianStore,
        builder: (context, _) {
          final g = guardianStore.guardian;
          final ready = guardianStore.ready != null;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Icon(Icons.family_restroom_rounded,
                  color: ready ? const Color(0xFF15803D) : Theme.of(context).colorScheme.outline),
              title: Text(ready
                  ? 'Guardian: ${g!.name}'
                  : g == null
                      ? 'Add a family guardian'
                      : 'Guardian needs your consent'),
              subtitle: Text(ready
                  ? 'You can tell ${g!.name} in one tap if something looks dangerous.'
                  : 'Someone you trust, told in one tap when a message is very likely a scam.'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuardianPage())),
            ),
          );
        },
      );
}
