import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device OCR is available on Android through Google ML Kit (Latin and
/// Chinese scripts, which covers Malay and English too).
bool get onDeviceOcrAvailable => Platform.isAndroid;

/// Reads the words in a picture on the device. Returns null when OCR is not
/// available or fails, so the caller can fall back to AI reading.
Future<String?> recogniseText(Uint8List rgba, int width, int height) async {
  if (!onDeviceOcrAvailable) return null;
  final input = InputImage.fromBitmap(bitmap: rgba, width: width, height: height);
  Future<String> run(TextRecognitionScript script) async {
    final r = TextRecognizer(script: script);
    try {
      return (await r.processImage(input)).text;
    } finally {
      await r.close();
    }
  }

  try {
    final latin = await run(TextRecognitionScript.latin);
    var chinese = '';
    try {
      chinese = await run(TextRecognitionScript.chinese);
    } catch (_) {}
    // The Chinese model also reads Latin letters, so prefer it when it found Han characters.
    final text = RegExp(r'[一-鿿]').hasMatch(chinese) ? chinese : latin;
    return text.trim().isEmpty ? null : text.trim();
  } catch (_) {
    return null;
  }
}
