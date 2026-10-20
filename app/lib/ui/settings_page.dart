import 'package:flutter/material.dart';

import '../engine/llm.dart';
import '../state.dart';
import 'forensic_settings.dart';
import 'guardian_ui.dart';
import 'intel_page.dart' show IntelSettingsSection;
import 'privacy_controls.dart';
import 'intake_widgets.dart';
import 'kit.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late LlmKind _kind = appState.llm.kind;
  late final _key = TextEditingController(text: appState.llm.apiKey == LlmConfig.defaults.apiKey ? '' : appState.llm.apiKey);
  late final _model = TextEditingController(text: appState.llm.model);
  late final _base = TextEditingController(text: appState.llm.baseUrl);
  late final _own = TextEditingController(text: appState.ownDetails.join(', '));
  late final _keys = ForensicKeysController(appState.keys);
  String? _test;
  bool _testing = false;

  LlmConfig get _config {
    final key = _key.text.trim().isEmpty && _kind == LlmKind.gemini ? LlmConfig.defaults.apiKey : _key.text.trim();
    return LlmConfig(kind: _kind, apiKey: key, model: _model.text.trim(), baseUrl: _base.text.trim());
  }

  Future<void> _save() async {
    await appState.saveLlm(_config);
    await appState.saveOwnDetails(_own.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet());
    await appState.saveKeys(_keys.value);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved.')));
  }

  Future<void> _testAi() async {
    setState(() {
      _testing = true;
      _test = null;
    });
    final c = LlmClient(_config);
    try {
      final j = await c.completeJson(system: 'Reply with JSON only.', user: 'Reply with {"ok": true}.');
      setState(() => _test = j['ok'] == true ? 'Connected. AI is working.' : 'Connected, but the reply was unexpected.');
    } catch (e) {
      setState(() => _test = 'Not working: $e');
    } finally {
      c.close();
      setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_key, _model, _base, _own]) {
      c.dispose();
    }
    _keys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hasBuiltIn = LlmConfig.defaults.apiKey.isNotEmpty;
    return PageBody(children: [
      _Section(
        icon: Icons.auto_awesome_outlined,
        title: 'AI explanations',
        intro: 'Kantoi\'s own checks always run on your phone. The AI adds plain-language explanations and spots extra signs. '
            'Your personal details are masked before anything is sent.',
        children: [
          DropdownButtonFormField<LlmKind>(
            initialValue: _kind,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'AI service'),
            items: const [
              DropdownMenuItem(value: LlmKind.gemini, child: Text('Google Gemini (reads screenshots)')),
              DropdownMenuItem(value: LlmKind.openaiCompatible, child: Text('Groq, DeepSeek or other OpenAI-style service')),
              DropdownMenuItem(value: LlmKind.ollama, child: Text('Your own Ollama server')),
              DropdownMenuItem(value: LlmKind.none, child: Text('No AI (built-in checks only)')),
            ],
            onChanged: (v) => setState(() {
              _kind = v ?? LlmKind.gemini;
              _model.text = '';
              _base.text = '';
              _test = null;
            }),
          ),
          if (_kind == LlmKind.gemini || _kind == LlmKind.openaiCompatible) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _key,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'API key',
                helperText: _kind == LlmKind.gemini
                    ? (hasBuiltIn ? 'Leave empty to use the key built into this copy of Kantoi.' : 'Get a free key at aistudio.google.com.')
                    : 'From your provider, e.g. console.groq.com.',
              ),
            ),
          ],
          if (_kind != LlmKind.none) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _model,
              decoration: InputDecoration(
                labelText: 'Model (optional)',
                hintText: switch (_kind) {
                  LlmKind.gemini => 'gemini-flash-latest',
                  LlmKind.ollama => 'qwen2.5:7b',
                  _ => 'llama-3.3-70b-versatile',
                },
              ),
            ),
          ],
          if (_kind == LlmKind.ollama || _kind == LlmKind.openaiCompatible) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _base,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Server address (optional)',
                hintText: _kind == LlmKind.ollama ? 'http://192.168.1.20:11434' : 'https://api.groq.com/openai/v1',
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering_rounded, size: 18),
              onPressed: _kind == LlmKind.none || _testing ? null : _testAi,
              label: Text(_testing ? 'Testing…' : 'Test connection'),
            ),
            if (_test != null)
              Text(_test!, style: TextStyle(color: _test!.startsWith('Connected') ? K.green : K.error, fontWeight: FontWeight.w600)),
          ]),
        ],
      ),
      _Section(
        icon: Icons.visibility_off_outlined,
        title: 'Always hide these details',
        intro: 'Your name, phone or account numbers. Kantoi masks them in everything it sends or reports. Stored only on this phone.',
        children: [
          TextField(controller: _own, decoration: const InputDecoration(hintText: 'e.g. Tan Mei Ling, 012-345 6789')),
        ],
      ),
      _Section(
        icon: Icons.travel_explore_outlined,
        title: 'Link safety services (optional)',
        children: [ForensicKeysSection(controller: _keys)],
      ),
      FilledButton.icon(icon: const Icon(Icons.save_outlined), onPressed: _save, label: const Text('Save settings')),
      const SectionTitle('Family guardian'),
      const GuardianStatusTile(),
      const IntelSettingsSection(),
      const IntakeSettingsSection(),
      const SizedBox(height: 16),
      _Section(
        icon: Icons.lock_outline_rounded,
        title: 'Privacy',
        children: [
          for (final (icon, line) in const [
            (Icons.lock_outline_rounded, 'Message checks, masking and relationship scoring run on your phone.'),
            (Icons.cloud_outlined, 'Only links (to see where they go and how old the website is) and masked text for AI explanations go online.'),
            (
              Icons.insert_drive_file_outlined,
              'Files are read on your phone. Only their fingerprint is checked online, unless you agree to send a recording to Gemini.'
            ),
            (Icons.list_alt_rounded, 'Every step that went online shows a cloud icon.'),
            (Icons.front_hand_outlined, 'Nothing is reported anywhere until you approve it.'),
            (
              Icons.auto_delete_outlined,
              'Old data is deleted automatically, and you can delete everything below. '
                  'Kantoi handles your data in line with Malaysia\'s Personal Data Protection Act 2010 (PDPA).'
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 18, color: K.outline),
                const SizedBox(width: 10),
                Expanded(child: Text(line, style: t.bodySmall?.copyWith(color: K.onSurface))),
              ]),
            ),
          const PrivacyControls(),
        ],
      ),
    ]);
  }
}

/// One settings group: an icon, a title, a short explanation and controls.
class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? intro;
  final List<Widget> children;
  const _Section({required this.icon, required this.title, this.intro, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: KCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: K.surfaceMid, borderRadius: K.r8),
              child: Icon(icon, size: 20, color: K.primary),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: t.titleMedium)),
          ]),
          if (intro != null) ...[const SizedBox(height: 8), Text(intro!, style: t.bodySmall)],
          const SizedBox(height: 12),
          ...children,
        ]),
      ),
    );
  }
}
