import 'package:flutter/material.dart';

import '../../vault/vault.dart';
import '../kit.dart';
import '../theme.dart';

/// Opens the safe word vault.
Future<void> openVault(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VaultPage()));

/// "Ask for your safe word" pop-up, shown when a message or call may be
/// someone pretending to be family or a friend. Offers the vault only when
/// the user has saved safe words.
Future<void> showSafeWordReminder(BuildContext context) async {
  await vault.load();
  if (!context.mounted) return;
  final t = Theme.of(context).textTheme;
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: K.r16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: const Color(0xFFFFFBEB),
          padding: const EdgeInsets.all(20),
          child: const Icon(Icons.record_voice_over_rounded, color: K.amber, size: 40),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Ask for your safe word', style: t.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'This could be someone pretending to be a person you know. Before you send money or share any code, '
              'ask them for your safe word.',
              style: t.bodyMedium,
            ),
            if (vault.count == 0) ...[
              const SizedBox(height: 8),
              Text('No safe words yet? Add one for each family member.', style: t.bodySmall),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              icon: const Icon(Icons.key_rounded),
              label: Text(vault.count > 0 ? 'Open safe word vault' : 'Set up safe words'),
              onPressed: () {
                Navigator.pop(ctx);
                openVault(context);
              },
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("I'll check later")),
          ]),
        ),
      ]),
    ),
  );
}

/// The safe word card on the Emergency tab.
class VaultCard extends StatefulWidget {
  const VaultCard({super.key});
  @override
  State<VaultCard> createState() => _VaultCardState();
}

class _VaultCardState extends State<VaultCard> {
  @override
  void initState() {
    super.initState();
    vault.addListener(_r);
    vault.load();
  }

  @override
  void dispose() {
    vault.removeListener(_r);
    super.dispose();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = vault.count;
    return KCard(
      onTap: () => openVault(context),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: K.primaryContainer.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.key_rounded, color: K.primaryContainer),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Safe word vault', style: t.titleMedium),
            const SizedBox(height: 2),
            Text(
              n == 0
                  ? 'Agree a secret word with family, so you can check who is really calling.'
                  : "Check who's really calling. $n safe word${n == 1 ? '' : 's'} saved.",
              style: t.bodySmall,
            ),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: K.outline),
      ]),
    );
  }
}

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});
  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> with WidgetsBindingObserver {
  final _search = TextEditingController();
  final Set<String> _shown = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vault.addListener(_r);
    vault.crypto.secureScreen(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vault.removeListener(_r);
    vault.crypto.secureScreen(false);
    vault.lock();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Leaving the app locks the vault; the user unlocks again on return.
    if (s == AppLifecycleState.paused) {
      vault.lock();
      _shown.clear();
    }
  }

  void _r() {
    if (mounted) setState(() {});
  }

  Future<void> _unlock() async {
    if (vault.unlocked || _busy) return;
    setState(() => _busy = true);
    try {
      await vault.unlock();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safe words')),
      floatingActionButton: vault.unlocked
          ? FloatingActionButton.extended(
              backgroundColor: K.primaryContainer,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add person'),
              onPressed: () => editSafeWord(context),
            )
          : null,
      body: AnimatedSwitcher(duration: K.medium, child: vault.unlocked ? _list(context) : _locked(context)),
    );
  }

  Widget _locked(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      key: const ValueKey('locked'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: K.primaryContainer, shape: BoxShape.circle),
            child: const Icon(Icons.key_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 20),
          Text('Safe word vault', style: t.headlineMedium),
          const SizedBox(height: 8),
          Text('Your safe words stay only on this phone. Unlock to view them.',
              textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
          const SizedBox(height: 28),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.fingerprint_rounded),
            label: const Text('Unlock'),
            onPressed: _busy ? null : _unlock,
          ),
          const SizedBox(height: 16),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline_rounded, size: 14, color: K.outline),
            const SizedBox(width: 6),
            Text('Never backed up. Never sent anywhere.', style: t.labelSmall?.copyWith(color: K.outline)),
          ]),
        ]),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = vault.search(_search.text);
    return ListView(
      key: const ValueKey('list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        if (vault.noPhoneLock)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: KCard(
              color: const Color(0xFFFEF2F2),
              borderColor: const Color(0xFFFECACA),
              child: Text('Your phone has no screen lock, so anyone holding it can open this vault. Set a PIN or fingerprint in Settings.',
                  style: t.bodyMedium),
            ),
          ),
        KCard(
          color: const Color(0xFFFFFBEB),
          borderColor: const Color(0xFFFEF3C7),
          child: Row(children: [
            const Icon(Icons.lightbulb_outline_rounded, color: K.amber),
            const SizedBox(width: 10),
            Expanded(child: Text('Agree safe words face to face or on a call, never by chat.', style: t.bodyMedium)),
          ]),
        ),
        const SizedBox(height: 12),
        if (vault.entries.length > 3)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name', isDense: true),
            ),
          ),
        Text('${vault.entries.length} ${vault.entries.length == 1 ? 'person' : 'people'}', style: t.labelLarge?.copyWith(color: K.outline)),
        const SizedBox(height: 8),
        if (vault.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text('No safe words yet.\nTap "Add person" to start with your closest family.',
                textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
          ),
        for (final (i, e) in items.indexed) ...[
          Reveal(index: i, child: _entry(context, e)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _entry(BuildContext context, SafeWord e) {
    final t = Theme.of(context).textTheme;
    final shown = _shown.contains(e.id);
    final colors = [K.primaryContainer, K.green, K.orange, const Color(0xFFBE185D), const Color(0xFF0E7490)];
    final c = colors[e.name.codeUnits.fold<int>(0, (a, b) => a + b) % colors.length];
    final checked = e.lastChecked == null ? 'Never checked' : 'Checked ${_ago(e.lastChecked!)}';
    return KCard(
      onTap: () => editSafeWord(context, existing: e),
      child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: c.withValues(alpha: 0.12), child: Text(e.initials, style: TextStyle(color: c, fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(e.name, style: t.titleMedium, overflow: TextOverflow.ellipsis)),
              if (e.relationship.isNotEmpty) ...[const SizedBox(width: 8), Pill(e.relationship, color: c)],
            ]),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: K.fast,
              child: Text(
                shown ? e.word : '••••••  ••••••',
                key: ValueKey(shown),
                style: t.titleMedium?.copyWith(color: shown ? K.primaryContainer : K.outline, letterSpacing: shown ? 0.5 : 2),
              ),
            ),
            if (shown && e.hint.isNotEmpty) Text('Hint: ${e.hint}', style: t.bodySmall),
            Text(checked, style: t.labelSmall?.copyWith(color: K.outline)),
          ]),
        ),
        Column(children: [
          IconButton(
            tooltip: shown ? 'Hide' : 'Show',
            icon: Icon(shown ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => shown ? _shown.remove(e.id) : _shown.add(e.id)),
          ),
          IconButton(
            tooltip: 'They said it right',
            icon: const Icon(Icons.verified_outlined, color: K.green),
            onPressed: () async {
              await vault.markChecked(e.id);
              if (context.mounted) showKToast(context, title: 'Checked', body: '${e.name} gave the right safe word.', icon: Icons.verified_rounded, color: K.green);
            },
          ),
        ]),
      ]),
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inDays >= 14) return '${d.inDays ~/ 7} weeks ago';
  if (d.inDays >= 1) return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  if (d.inHours >= 1) return '${d.inHours} h ago';
  return 'just now';
}

/// Add or edit one person's safe word in a bottom sheet.
Future<void> editSafeWord(BuildContext context, {SafeWord? existing}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EditSheet(existing: existing),
    );

class _EditSheet extends StatefulWidget {
  final SafeWord? existing;
  const _EditSheet({this.existing});
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _word = TextEditingController(text: widget.existing?.word);
  late final _hint = TextEditingController(text: widget.existing?.hint);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late String _rel = widget.existing?.relationship ?? '';

  @override
  void dispose() {
    for (final c in [_name, _phone, _word, _hint, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final e = widget.existing;
    final w = SafeWord(
      id: e?.id ?? 'sw-${DateTime.now().microsecondsSinceEpoch}',
      name: _name.text.trim(),
      relationship: _rel,
      phone: _phone.text.trim(),
      word: _word.text.trim(),
      hint: _hint.text.trim(),
      notes: _notes.text.trim(),
      created: e?.created,
      lastChecked: e?.lastChecked,
    );
    await vault.upsert(w);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final warnings = _word.text.trim().isEmpty ? const <String>[] : safeWordWarnings(_word.text, name: _name.text);
    final ok = _name.text.trim().isNotEmpty && _word.text.trim().length >= 3;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
              child: Container(
                  width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: K.outlineVariant, borderRadius: BorderRadius.circular(2)))),
          Text(widget.existing == null ? 'Add a safe word' : 'Edit safe word', style: t.headlineSmall),
          const SizedBox(height: 16),
          TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Name', isDense: true)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in relationships) ChoiceChip(label: Text(r), selected: _rel == r, onSelected: (_) => setState(() => _rel = _rel == r ? '' : r)),
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number (optional)', isDense: true)),
          const SizedBox(height: 12),
          TextField(
            controller: _word,
            onChanged: (_) => setState(() {}),
            style: t.titleMedium,
            decoration: InputDecoration(
              labelText: 'Safe word',
              suffixIcon: TextButton.icon(
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Suggest'),
                onPressed: () => setState(() => _word.text = suggestSafeWord()),
              ),
            ),
          ),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: K.amber),
                const SizedBox(width: 6),
                Expanded(child: Text(w, style: t.bodySmall?.copyWith(color: const Color(0xFF92400E)))),
              ]),
            ),
          const SizedBox(height: 12),
          TextField(controller: _hint, decoration: const InputDecoration(labelText: 'Hint only you understand (optional)', isDense: true)),
          const SizedBox(height: 12),
          TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)', isDense: true)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: K.outline),
            const SizedBox(width: 6),
            Expanded(child: Text("Don't use birthdays, pet names or anything on social media.", style: t.bodySmall)),
          ]),
          const SizedBox(height: 16),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: ok ? _save : null, child: const Text('Save')),
          if (widget.existing != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: K.red),
              onPressed: () async {
                await vault.remove(widget.existing!.id);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Delete'),
            )
          else
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ]),
      ),
    );
  }
}

/// Shown on a check result when someone may be posing as family or a friend.
class SafeWordBanner extends StatefulWidget {
  const SafeWordBanner({super.key});
  @override
  State<SafeWordBanner> createState() => _SafeWordBannerState();
}

class _SafeWordBannerState extends State<SafeWordBanner> {
  @override
  void initState() {
    super.initState();
    vault.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return KCard(
      color: const Color(0xFFFFFBEB),
      borderColor: const Color(0xFFFEF3C7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.record_voice_over_rounded, color: K.amber),
          const SizedBox(width: 10),
          Expanded(child: Text('Ask for your safe word', style: t.titleMedium)),
        ]),
        const SizedBox(height: 6),
        Text('This may be someone pretending to be a person you know. Ask for your safe word before you send money or share a code.',
            style: t.bodyMedium),
        if (vault.count > 0) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(icon: const Icon(Icons.key_rounded), label: const Text('Open safe word vault'), onPressed: () => openVault(context)),
        ],
      ]),
    );
  }
}
