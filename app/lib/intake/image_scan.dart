import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import '../engine/models.dart';

/// What Kantoi reads from a picture on the device: any QR code, the editing
/// software and dates in its metadata, and raw pixels for on-device OCR.
class ImageScan {
  final String? qr;
  final Map<String, String> meta;
  final int width;
  final int height;
  final Uint8List? rgba;
  const ImageScan({this.qr, this.meta = const {}, this.width = 0, this.height = 0, this.rgba});
}

/// Decodes the picture and looks for a QR code. Pure Dart, so it runs the
/// same on Android, Windows and the web; call it through `compute`.
ImageScan scanImage(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('Not a picture Kantoi can open');
  final meta = <String, String>{};
  try {
    final exif = img.decodeJpgExif(bytes) ?? image.exif;
    final soft = exif.imageIfd.software?.trim();
    if (soft != null && soft.isNotEmpty) meta['Software'] = soft;
    final taken = exif.exifIfd[0x9003]?.toString().trim();
    if (taken != null && taken.isNotEmpty) meta['Taken'] = taken;
    final changed = exif.imageIfd[0x0132]?.toString().trim();
    if (changed != null && changed.isNotEmpty) meta['Changed'] = changed;
  } catch (_) {}
  final soft = image.textData?['Software'];
  if (soft != null) meta['Software'] = soft;
  final small = image.width > 1600 || image.height > 1600
      ? img.copyResize(image, width: image.width >= image.height ? 1600 : null, height: image.height > image.width ? 1600 : null)
      : image;
  final rgba = small.convert(format: img.Format.uint8, numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
  return ImageScan(qr: decodeQr(image), meta: meta, width: small.width, height: small.height, rgba: rgba);
}

/// Finds and decodes a QR code anywhere in [image], trying a few sizes and
/// binarisers because screenshots and phone photos differ a lot.
String? decodeQr(img.Image image) {
  final sizes = <int>{1200, 800, 500};
  final longest = image.width > image.height ? image.width : image.height;
  for (final size in sizes) {
    final scaled = longest > size
        ? img.copyResize(image, width: image.width >= image.height ? size : null, height: image.height > image.width ? size : null)
        : image;
    final pixels = scaled.convert(format: img.Format.uint8, numChannels: 4).getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List();
    final source = RGBLuminanceSource(scaled.width, scaled.height, pixels);
    final hints = DecodeHints()..put(DecodeHintType.tryHarder);
    for (final bitmap in [BinaryBitmap(HybridBinarizer(source)), BinaryBitmap(GlobalHistogramBinarizer(source))]) {
      try {
        final r = QRCodeReader().decode(bitmap, hints: hints);
        if (r.text.trim().isNotEmpty) return r.text.trim();
      } catch (_) {}
    }
    if (longest <= size) break;
  }
  return null;
}

/// Editing software or mismatched dates in a picture's metadata: a minor
/// signal, because screenshots are often legitimately cropped.
List<Finding> imageMetaFindings(Map<String, String> meta) {
  final soft = meta['Software'] ?? '';
  final edited = RegExp(r'photoshop|gimp|picsart|snapseed|canva|lightroom|pixlr|photopea|meitu|facetune', caseSensitive: false).firstMatch(soft);
  return [
    if (edited != null)
      Finding(
        category: CueCategory.file,
        title: 'Picture was edited',
        explanation: 'This picture was saved with ${edited.group(0)}, a photo editor. Fake receipts and letters are often made this way. On its own this is a small sign.',
        weight: 5,
        tool: 'Picture details check',
      ),
    if (meta['Taken'] != null && meta['Changed'] != null && meta['Taken'] != meta['Changed'] && edited == null)
      const Finding(
        category: CueCategory.file,
        title: 'Picture changed after it was taken',
        explanation: 'The picture was saved again after it was taken. This is common, but also happens when a photo is edited.',
        weight: 2,
        tool: 'Picture details check',
      ),
  ];
}
