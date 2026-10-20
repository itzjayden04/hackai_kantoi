import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Files go to the share sheet (save to Files, Drive, WhatsApp or email).
/// The save dialog is only a fallback for running the app in tests or a
/// debug build on a computer.
bool get useShareSheet =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Returns a short message for a snackbar, or null if the user cancelled.
Future<String?> saveOrShare(
  List<({String name, Uint8List bytes, String mime})> files, {
  String? subject,
}) async {
  if (files.isEmpty) return null;
  try {
    if (useShareSheet) {
      await SharePlus.instance.share(ShareParams(
        subject: subject,
        files: [for (final f in files) XFile.fromData(f.bytes, mimeType: f.mime, name: f.name)],
        fileNameOverrides: [for (final f in files) f.name],
      ));
      return 'Choose where to send or save it.';
    }
    final first = files.first;
    final loc = await getSaveLocation(suggestedName: first.name);
    if (loc == null) return null;
    await XFile.fromData(first.bytes, mimeType: first.mime, name: first.name).saveTo(loc.path);
    return 'Saved ${first.name}.';
  } catch (e) {
    return 'Could not save the file: $e';
  }
}

void showSnack(BuildContext context, String? message) {
  if (message == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
