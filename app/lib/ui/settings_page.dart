import 'package:flutter/material.dart';

import '../engine/llm.dart';
import '../state.dart';
import 'intel_page.dart' show IntelSettingsSection;
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
  String? _test;
  bool _testing = false;

  LlmConfig get _config {
    final key = _key.text.trim().isEmpty && _kind == LlmKind.gemini ? LlmConfig.defaults.apiKey : _key.text.trim();
    return LlmConfig(kind: _kind, apiKey: key, model: _model.text.trim(), baseUrl: _base.text.trim());
  }

  Future<void> _save() async {
    await appState.saveLlm(_config);
    await appState.saveOwnDetails(_own.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet());
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
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hasBuiltIn = LlmConfig.defaults.apiKey.isNotEmpty;
    return PageBody(children: [
      Text('Settings', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SectionTitle('AI explanations'),
      Text('Kantoi\'s own checks always run on your device. The AI adds plain-English explanations and spots extra cues. '
          'Your personal details are masked before anything is sent.', style: t.bodyMedium),
      const SizedBox(height: 12),
      DropdownButtonFormField<LlmKind>(
        initialValue: _kind,
        decoration: const InputDecoration(labelText: 'AI service'),
        items: const [
          DropdownMenuItem(value: LlmKind.gemini, child: Text('Google Gemini (free tier, reads screenshots)')),
          DropdownMenuItem(value: LlmKind.ollama, child: Text('Ollama on this computer (offline, private)')),
          DropdownMenuItem(value: LlmKind.openaiCompatible, child: Text('Groq, DeepSeek or other OpenAI-style service')),
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
          decoration: InputDecoration(
            labelText: 'Server address (optional)',
            hintText: _kind == LlmKind.ollama ? 'http://127.0.0.1:11434' : 'https://api.groq.com/openai/v1',
          ),
        ),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton(onPressed: _kind == LlmKind.none || _testing ? null : _testAi, child: Text(_testing ? 'Testing…' : 'Test connection')),
        if (_test != null) Text(_test!, style: TextStyle(color: _test!.startsWith('Connected') ? const Color(0xFF15803D) : Theme.of(context).colorScheme.error)),
      ]),
      const SectionTitle('Always hide these details'),
      Text('Your name, phone or account numbers. Kantoi masks them in everything it sends or reports. Stored only on this device.',
          style: t.bodyMedium),
      const SizedBox(height: 10),
      TextField(controller: _own, decoration: const InputDecoration(hintText: 'e.g. Tan Mei Ling, 012-345 6789')),
      const SizedBox(height: 20),
      FilledButton(onPressed: _save, child: const Text('Save settings')),
      const IntelSettingsSection(),
      const SectionTitle('Privacy'),
      Text(
        '• Message checks, redaction and relationship scoring run on your device.\n'
        '• Only links (to see where they go and how old the website is) and masked text for AI explanations go online.\n'
        '• The activity log shows a cloud icon on every step that went online.\n'
        '• Nothing is reported anywhere until you approve it.',
        style: t.bodyMedium?.copyWith(height: 1.6),
      ),
    ]);
  }
}
