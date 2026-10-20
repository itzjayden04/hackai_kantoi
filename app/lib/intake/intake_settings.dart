import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional keys and remembered choices for the intake checks. Keys come from
/// build-time defines and can be overridden in Settings; stored on the device.
class IntakeSettings extends ChangeNotifier {
  static const _buildVirusTotal = String.fromEnvironment('VIRUSTOTAL_API_KEY');
  static const _buildTelegram = String.fromEnvironment('TELEGRAM_BOT_TOKEN');

  String _virusTotal = '';
  String _telegram = '';

  /// Whether the user agreed to send recordings (and unreadable PDFs) to
  /// Gemini for a transcript. Null means ask.
  bool? mediaConsent;
  bool _loaded = false;

  String get virusTotalKey => _virusTotal.isNotEmpty ? _virusTotal : _buildVirusTotal;
  String get telegramToken => _telegram.isNotEmpty ? _telegram : _buildTelegram;
  String get virusTotalOverride => _virusTotal;
  String get telegramOverride => _telegram;
  bool get hasBuiltInVirusTotal => _buildVirusTotal.isNotEmpty;
  bool get hasBuiltInTelegram => _buildTelegram.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _virusTotal = p.getString('intake.virusTotal') ?? '';
      _telegram = p.getString('intake.telegram') ?? '';
      mediaConsent = p.getBool('intake.mediaConsent');
    } catch (_) {}
    notifyListeners();
  }

  Future<void> save({String? virusTotal, String? telegram, bool? consent, bool clearConsent = false}) async {
    if (virusTotal != null) _virusTotal = virusTotal.trim();
    if (telegram != null) _telegram = telegram.trim();
    if (consent != null) mediaConsent = consent;
    if (clearConsent) mediaConsent = null;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('intake.virusTotal', _virusTotal);
      await p.setString('intake.telegram', _telegram);
      if (mediaConsent == null) {
        await p.remove('intake.mediaConsent');
      } else {
        await p.setBool('intake.mediaConsent', mediaConsent!);
      }
    } catch (_) {}
  }
}

final intakeSettings = IntakeSettings();
