import 'dart:typed_data';

/// No on-device OCR on this platform; the caller falls back to AI reading.
bool get onDeviceOcrAvailable => false;

Future<String?> recogniseText(Uint8List rgba, int width, int height) async => null;
