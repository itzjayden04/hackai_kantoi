import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../intake/intake_settings.dart';
import '../intake/telegram_bot.dart';
import 'theme.dart';

/// Live camera QR scanning is offered on Android; elsewhere people upload a
/// picture of the QR code instead.
bool get cameraQrAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Asks once before a recording (or an unreadable PDF) is sent to Gemini,
/// because personal details cannot be masked inside audio or a scan.
Future<bool> askMediaConsent(BuildContext context, [String what = 'recording']) async {
  await intakeSettings.load();
  if (intakeSettings.mediaConsent == true) return true;
  if (!context.mounted) return false;
  var remember = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Send this to Gemini?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(what == 'PDF'
              ? 'Kantoi could not read the words in this PDF on your device. This sends the PDF to Gemini to read it. Continue?\n\n'
                  'Kantoi cannot hide personal details inside a scanned page, so the file itself is sent. Nothing else leaves your device.'
              : 'This sends the $what to Gemini to turn it into text. Continue?\n\n'
                  'Kantoi cannot hide personal details inside a $what, so the file itself is sent. Nothing else leaves your device.'),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: remember,
            onChanged: (v) => set(() => remember = v ?? true),
            title: const Text("Don't ask me again"),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    ),
  );
  if (ok == true && remember) await intakeSettings.save(consent: true);
  return ok == true;
}

/// Full-screen camera that returns the first QR code it reads, decoded on
/// the device.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});
  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan a QR code')),
        body: Stack(children: [
          MobileScanner(
            controller: _controller,
            onDetect: (c) {
              final v = c.barcodes.map((b) => b.rawValue).whereType<String>().where((s) => s.trim().isNotEmpty).firstOrNull;
              if (v == null || _done) return;
              _done = true;
              Navigator.pop(context, v);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('The camera could not start. Allow camera access, or take a photo of the QR code and add it with the picture button on the Check tab.',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: const Text('Point the camera at the QR code. Kantoi reads it on your phone and does not open it.',
                  style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
            ),
          ),
        ]),
      );
}

/// Settings for the intake checks: VirusTotal key, Telegram bot and the
/// recording consent.
class IntakeSettingsSection extends StatefulWidget {
  const IntakeSettingsSection({super.key});
  @override
  State<IntakeSettingsSection> createState() => _IntakeSettingsSectionState();
}

class _IntakeSettingsSectionState extends State<IntakeSettingsSection> {
  final _tg = TextEditingController();

  @override
  void initState() {
    super.initState();
    intakeSettings.load().then((_) {
      if (!mounted) return;
      _tg.text = intakeSettings.telegramOverride;
      setState(() {});
    });
  }

  Future<void> _save() async {
    await intakeSettings.save(telegram: _tg.text);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Files and recordings'),
      Text('Files are read on your device. With the VirusTotal key above, only a fingerprint of each file (never the file) is checked against its list of known harmful files.',
          style: t.bodyMedium),
      const SizedBox(height: 6),
      ListenableBuilder(
        listenable: intakeSettings,
        builder: (context, _) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Send recordings to Gemini without asking'),
          subtitle: const Text('Needed to turn voice notes and videos into text.'),
          value: intakeSettings.mediaConsent == true,
          onChanged: (v) => v ? intakeSettings.save(consent: true) : intakeSettings.save(clearConsent: true),
        ),
      ),
      const SectionTitle('Telegram bot'),
      Text('Forward a message to your own Telegram bot and get the verdict back. Create a bot with @BotFather and paste its token here. '
          'The bot answers while Kantoi is open on this phone.', style: t.bodyMedium),
      const SizedBox(height: 10),
      TextField(
        controller: _tg,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'Bot token (optional)',
          helperText: intakeSettings.hasBuiltInTelegram ? 'Leave empty to use the bot built into this copy of Kantoi.' : null,
        ),
      ),
      const SizedBox(height: 8),
      ValueListenableBuilder(
        valueListenable: telegramBotStatus,
        builder: (context, s, _) => Text('Telegram bot: ${s[0].toLowerCase()}${s.substring(1)}', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: _save, child: const Text('Save bot settings'))),
    ]);
  }
}
