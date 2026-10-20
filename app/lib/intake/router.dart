import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../engine/llm.dart';
import '../engine/models.dart';
import '../engine/vision.dart';
import 'apk.dart';
import 'chat_export.dart';
import 'docx.dart';
import 'email.dart';
import 'fake_document.dart';
import 'fingerprint.dart';
import 'image_scan.dart';
import 'language.dart';
import 'normalise.dart';
import 'ocr.dart';
import 'pdf.dart';
import 'transcribe.dart';

enum IntakeKind { text, url, email, qr, image, audio, video, pdf, docx, apk, chatLog, other }

String kindLabel(IntakeKind k) => switch (k) {
      IntakeKind.text => 'Message text',
      IntakeKind.url => 'Link',
      IntakeKind.email => 'Email with headers',
      IntakeKind.qr => 'QR code',
      IntakeKind.image => 'Picture',
      IntakeKind.audio => 'Voice note or call recording',
      IntakeKind.video => 'Video',
      IntakeKind.pdf => 'PDF document',
      IntakeKind.docx => 'Word document',
      IntakeKind.apk => 'Android app file',
      IntakeKind.chatLog => 'Chat export',
      IntakeKind.other => 'File',
    };

Source _sourceFor(IntakeKind k) => switch (k) {
      IntakeKind.email => Source.email,
      IntakeKind.qr => Source.qr,
      IntakeKind.image => Source.screenshot,
      IntakeKind.audio => Source.voice,
      IntakeKind.video => Source.video,
      IntakeKind.pdf || IntakeKind.docx || IntakeKind.other => Source.document,
      IntakeKind.apk => Source.apk,
      IntakeKind.chatLog => Source.chatExport,
      _ => Source.paste,
    };

/// A problem the user can act on, worded for them.
class IntakeError implements Exception {
  final String message;
  const IntakeError(this.message);
  @override
  String toString() => message;
}

/// The normalised artefact ready for [investigate]: the text to check plus
/// everything the extractors found.
class IntakeResult {
  final String text;
  final IntakeKind kind;
  final Source source;
  final IntakeExtras extras;

  /// A short tip shown above the result, e.g. where to go for a chat export.
  final String? note;
  const IntakeResult({required this.text, required this.kind, required this.source, required this.extras, this.note});
}

typedef ConsentAsker = Future<bool> Function();

/// Works out the kind from magic bytes first, then the name and mime type.
IntakeKind detectKind({Uint8List? bytes, String? name, String? mime, String? text}) {
  if (bytes == null) {
    final t = (text ?? '').trim();
    if (parseEmail(t) != null) return IntakeKind.email;
    if (looksLikeChatExport(t)) return IntakeKind.chatLog;
    if (RegExp(r'^(https?://|www\.)\S+$', caseSensitive: false).hasMatch(t)) return IntakeKind.url;
    return IntakeKind.text;
  }
  final n = (name ?? '').toLowerCase();
  final m = (mime ?? '').toLowerCase();
  bool starts(List<int> sig, [int at = 0]) {
    if (bytes.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[at + i] != sig[i]) return false;
    }
    return true;
  }

  String ascii(int at, int len) => bytes.length >= at + len ? latin1.decode(bytes.sublist(at, at + len)) : '';
  if (starts(const [0x25, 0x50, 0x44, 0x46])) return IntakeKind.pdf;
  if (starts(const [0x50, 0x4B, 0x03, 0x04])) {
    if (n.endsWith('.apk')) return IntakeKind.apk;
    if (n.endsWith('.docx') || n.endsWith('.docm')) return IntakeKind.docx;
    try {
      final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toList();
      if (names.contains('AndroidManifest.xml')) return IntakeKind.apk;
      if (names.contains('word/document.xml')) return IntakeKind.docx;
      if (names.any((f) => f.endsWith('.txt') || f.endsWith('result.json'))) return IntakeKind.chatLog;
    } catch (_) {}
    return IntakeKind.other;
  }
  if (starts(const [0x89, 0x50, 0x4E, 0x47]) || starts(const [0xFF, 0xD8, 0xFF]) || ascii(0, 3) == 'GIF' || (ascii(0, 4) == 'RIFF' && ascii(8, 4) == 'WEBP') || ascii(0, 2) == 'BM') {
    return IntakeKind.image;
  }
  if (ascii(0, 4) == 'OggS' || ascii(0, 3) == 'ID3' || ascii(0, 4) == 'fLaC' || (ascii(0, 4) == 'RIFF' && ascii(8, 4) == 'WAVE') || starts(const [0xFF, 0xFB]) || starts(const [0xFF, 0xF3]) || starts(const [0xFF, 0xF1])) {
    return m.startsWith('video/') ? IntakeKind.video : IntakeKind.audio;
  }
  if (ascii(4, 4) == 'ftyp') {
    final brand = ascii(8, 4);
    return brand.startsWith('M4A') || m.startsWith('audio/') || n.endsWith('.m4a') ? IntakeKind.audio : IntakeKind.video;
  }
  if (starts(const [0x1A, 0x45, 0xDF, 0xA3])) return m.startsWith('audio/') ? IntakeKind.audio : IntakeKind.video;
  if (m.startsWith('image/')) return IntakeKind.image;
  if (m.startsWith('audio/')) return IntakeKind.audio;
  if (m.startsWith('video/')) return IntakeKind.video;
  if (starts(const [0xD0, 0xCF, 0x11, 0xE0])) return IntakeKind.other;
  // Text files: chat exports, saved emails, plain messages.
  try {
    final t = utf8.decode(bytes.length > 4000 ? bytes.sublist(0, 4000) : bytes);
    if (n.endsWith('.json') || looksLikeChatExport(t)) return IntakeKind.chatLog;
    if (n.endsWith('.eml') || parseEmail(t) != null) return IntakeKind.email;
    return IntakeKind.text;
  } catch (_) {
    return IntakeKind.other;
  }
}

/// The router agent: detects what the input is and which languages it holds,
/// runs the matching extractors (in parallel when an input holds more than one
/// kind of content), and returns one normalised artefact for [investigate].
Future<IntakeResult> routeInput({
  String? text,
  Uint8List? bytes,
  String? name,
  String? mime,
  Source? source,
  LlmConfig llm = LlmConfig.defaults,
  String? situation,
  ConsentAsker? askConsent,
  bool network = true,
  String virusTotalKey = '',
  void Function(List<LogStep>)? onStep,
}) async {
  final log = <LogStep>[];
  LogStep step(String tool, String action, {bool sentOffDevice = false}) {
    final s = LogStep(tool: tool, action: action, sentOffDevice: sentOffDevice);
    log.add(s);
    onStep?.call(List.of(log));
    return s;
  }

  void done(LogStep s, String result, [StepStatus status = StepStatus.done]) {
    s
      ..result = result
      ..status = status;
    onStep?.call(List.of(log));
  }

  final kind = detectKind(bytes: bytes, name: name, mime: mime, text: text);
  final label = name == null ? kindLabel(kind) : '${kindLabel(kind)} "$name"';
  final route = step('Intake router', 'Working out what this is');
  done(route, bytes == null ? '$label, ${text?.length ?? 0} characters' : '$label, ${_size(bytes.length)}. ${_plan(kind)}');

  final findings = <Finding>[];
  final meta = <String, String>{'Kind': kindLabel(kind), 'File': ?name};
  String? nextStep, scamType, note;
  var body = text ?? '';

  // Every file gets a fingerprint; only the fingerprint ever goes online.
  Future<void> fingerprint() async {
    if (bytes == null) return;
    final hash = await compute(sha256Of, bytes.toList());
    meta['SHA-256'] = hash;
    done(step('Fingerprint', 'Making a fingerprint (SHA-256) of the file on your device'), '${hash.substring(0, 16)}…');
    if (virusTotalKey.isEmpty || !network) {
      done(step('VirusTotal', 'Looking up the fingerprint'), network ? 'Skipped: no VirusTotal key set up' : 'Skipped: offline', StepStatus.skipped);
      return;
    }
    final s = step('VirusTotal', "Checking the file's fingerprint, not the file", sentOffDevice: true);
    try {
      final (f, summary) = await lookupHash(hash, virusTotalKey);
      if (f != null) findings.add(f);
      done(s, summary);
    } catch (e) {
      done(s, 'Could not check ($e). Only the fingerprint would have been sent.', StepStatus.failed);
    }
  }

  Future<bool> consent() async => askConsent == null ? false : await askConsent();

  Future<void> extract() async {
    switch (kind) {
      case IntakeKind.text || IntakeKind.url:
        if (bytes != null) body = utf8.decode(bytes, allowMalformed: true);
      case IntakeKind.email:
        if (bytes != null) body = utf8.decode(bytes, allowMalformed: true);
        final e = parseEmail(body)!;
        final s = step('Email header check', 'Comparing the sender, reply-to address and sender checks');
        final f = checkEmailHeaders(e);
        findings.addAll(f);
        final (fromName, fromAddr) = splitAddress(e.first('from') ?? '');
        meta['From'] = fromName.isEmpty ? fromAddr : '$fromName <$fromAddr>';
        if (e.first('reply-to') != null) meta['Reply-To'] = e.first('reply-to')!;
        done(s, f.isEmpty ? 'Headers look consistent' : f.map((x) => x.title).join(', '));
        body = emailText(e);
      case IntakeKind.qr:
        body = 'QR code: ${text!.trim()}${describeQr(text) == null ? '' : '\n${describeQr(text)}'}';
      case IntakeKind.image:
        body = await _image(bytes!, name ?? 'picture', mime, llm, findings, meta, step, done);
      case IntakeKind.pdf:
        body = await _pdf(bytes!, llm, consent, findings, meta, step, done);
      case IntakeKind.docx:
        final s = step('Document reader', 'Reading the Word file on your device');
        final DocxInfo d;
        try {
          d = await compute(readDocx, bytes!);
        } catch (e) {
          done(s, 'Could not open it ($e)', StepStatus.failed);
          throw const IntakeError('Kantoi could not open this Word file. It may be damaged or password protected.');
        }
        meta.addAll(d.meta);
        findings.addAll(docxFindings(d));
        done(s, '${d.text.length} characters, ${d.links.length} link(s)${d.hasMacros ? ', macros' : ''}${d.externalTemplates.isNotEmpty ? ', remote template' : ''}');
        body = [d.text, if (d.links.isNotEmpty) 'Links in the document:\n${d.links.join('\n')}'].join('\n\n');
        _fakeDoc(body, meta, findings, step, done);
      case IntakeKind.apk:
        final s = step('App file check', 'Reading the app\'s permission list (the app is not installed or run)');
        final ApkInfo a;
        try {
          a = await compute(readApk, bytes!);
        } catch (e) {
          done(s, 'Could not read it ($e)', StepStatus.failed);
          throw const IntakeError('Kantoi could not read this app file. Do not install it.');
        }
        final f = apkFindings(a, fileName: name ?? 'this app');
        findings.addAll(f);
        if (a.packageName != null) meta['Package'] = a.packageName!;
        final risky = a.permissions.where(riskyPermissions.containsKey).map((p) => p.split('.').last).toList();
        done(s, '${a.permissions.length} permission(s)${risky.isEmpty ? '' : '. Risky: ${risky.join(', ')}'}');
        body = apkSummary(a, name ?? 'app.apk');
        scamType = 'Malicious app (APK) scam';
        if (risky.isNotEmpty) nextStep = apkWarning;
      case IntakeKind.audio || IntakeKind.video:
        final what = kind == IntakeKind.audio ? 'recording' : 'video';
        if (!canReadMedia(llm)) {
          done(step('Speech to text', 'Turning the $what into text'), 'Skipped: needs Gemini', StepStatus.skipped);
          throw IntakeError('Turning a $what into text needs Gemini, which is not set up. Type what was said into the box instead, or set up Gemini in Settings.');
        }
        if (!await consent()) {
          done(step('Speech to text', 'Turning the $what into text'), 'Skipped: you chose not to send it', StepStatus.skipped);
          throw IntakeError('The $what was not sent. You can type what was said into the box instead.');
        }
        final s = step('Speech to text', 'Sending the $what you chose to ${llm.displayName} for a transcript (you agreed to this)', sentOffDevice: true);
        try {
          final t = await transcribe(bytes!, mediaMime(name ?? '') ?? mime ?? (kind == IntakeKind.audio ? 'audio/ogg' : 'video/mp4'), llm);
          done(s, t.isEmpty ? 'No speech found' : '${t.length} characters of speech');
          if (t.isEmpty) throw IntakeError('No speech was found in this $what.');
          body = t;
        } on IntakeError {
          rethrow;
        } catch (e) {
          done(s, 'Failed ($e)', StepStatus.failed);
          throw IntakeError('Could not turn the $what into text: $e');
        }
      case IntakeKind.chatLog:
        final raw = bytes == null ? text! : chatExportText(bytes);
        final msgs = parseAnyChatExport(raw);
        final s = step('Chat parser', 'Splitting the chat into speakers, times and messages');
        final senders = msgs.map((m) => m.sender).toSet();
        done(s, '${msgs.length} messages from ${senders.take(4).join(', ')}');
        meta['Messages'] = '${msgs.length}';
        meta['Speakers'] = senders.join(', ');
        body = msgs.reversed.take(40).toList().reversed.map((m) => '${m.sender}: ${m.text}').join('\n');
        note = 'This is a whole chat. Kantoi checked the last ${msgs.length < 40 ? msgs.length : 40} messages here. '
            'For a full trust check of this person, open the Relationship tab and load the same file.';
      case IntakeKind.other:
        done(step('File reader', 'Looking inside the file'), 'Kantoi cannot look inside this kind of file', StepStatus.skipped);
        body = 'File: ${name ?? 'unknown'} (${_size(bytes!.length)})';
        findings.add(const Finding(
          category: CueCategory.file,
          title: 'Unknown file type',
          explanation: "Kantoi can't look inside this kind of file. Don't open files you weren't expecting, even from people you know.",
          weight: 6,
          tool: 'Intake router',
        ));
    }
  }

  await Future.wait([fingerprint(), extract()]);

  body = body.trim();
  if (body.length > 20000) body = '${body.substring(0, 20000)}\n[... the rest was not checked]';
  if (body.isEmpty) throw const IntakeError('Kantoi found no words to check. Type or paste the message instead.');

  // Shared text steps on whatever the extractors produced.
  findings.addAll(disguisedSpellingFindings(body));
  final langs = detectLanguages(body);
  return IntakeResult(
    text: body,
    kind: kind,
    source: source ?? _sourceFor(kind),
    note: note,
    extras: IntakeExtras(
      kind: kind.name,
      raw: bytes == null ? text : name,
      languages: langs,
      findings: findings,
      steps: log,
      entities: extraEntities(body),
      meta: meta,
      situation: situation,
      nextStep: nextStep,
      scamType: findings.any((f) => f.isRisk && f.category == CueCategory.file) ? scamType : null,
    ),
  );
}

typedef _Step = LogStep Function(String tool, String action, {bool sentOffDevice});
typedef _Done = void Function(LogStep s, String result, [StepStatus status]);

/// A picture: the QR reader and the text reader run side by side, plus a
/// look at the picture's metadata.
Future<String> _image(Uint8List bytes, String name, String? mime, LlmConfig llm, List<Finding> findings, Map<String, String> meta, _Step step, _Done done) async {
  final qrStep = step('QR reader', 'Looking for a QR code on your device');
  final scanFuture = compute(scanImage, bytes);
  Future<(String, String)> readText() async {
    if (onDeviceOcrAvailable) {
      final s = step('Text reader', 'Reading the words on your device');
      try {
        final scan = await scanFuture;
        final t = await recogniseText(scan.rgba!, scan.width, scan.height);
        if (t != null && t.trim().length >= 8) {
          done(s, '${t.length} characters read');
          return (t, '');
        }
        done(s, 'Could not read the words here', StepStatus.failed);
      } catch (e) {
        done(s, 'Could not read the words here', StepStatus.failed);
      }
    }
    if (!llm.usable || llm.kind == LlmKind.openaiCompatible) {
      done(step('Screenshot reader', 'Reading the words with AI'), 'Skipped: no on-device reader here and no Gemini or Ollama set up', StepStatus.skipped);
      return ('', '');
    }
    final s = step('Screenshot reader', 'Sending the picture you chose to ${llm.displayName} to read its words', sentOffDevice: llm.leavesDevice);
    try {
      final lower = name.toLowerCase();
      final m = mime ?? (lower.endsWith('.jpg') || lower.endsWith('.jpeg') ? 'image/jpeg' : lower.endsWith('.webp') ? 'image/webp' : 'image/png');
      final r = await readImage(bytes, llm, mime: m);
      done(s, '${r.text.length} characters read${r.app != 'unknown' ? ', looks like ${r.app}' : ''}');
      return (r.text, r.qr);
    } catch (e) {
      done(s, 'Failed ($e)', StepStatus.failed);
      return ('', '');
    }
  }

  final textFuture = readText();
  ImageScan? scan;
  try {
    scan = await scanFuture;
    done(qrStep, scan.qr == null ? 'No QR code found' : 'Found a QR code: ${_short(scan.qr!)}');
  } catch (e) {
    done(qrStep, 'Could not open the picture', StepStatus.failed);
  }
  final (words, aiQr) = await textFuture;
  if (scan == null && words.isEmpty) throw const IntakeError('Kantoi could not open this picture. Try a PNG or JPG screenshot.');
  if (scan != null) {
    final metaStep = step('Picture details check', 'Reading the picture\'s hidden details');
    meta.addAll(scan.meta);
    final f = imageMetaFindings(scan.meta);
    findings.addAll(f);
    done(metaStep, f.isEmpty ? (scan.meta.isEmpty ? 'No editing traces' : 'Nothing unusual') : f.first.title);
  }
  final qr = scan?.qr ?? (aiQr.trim().isEmpty ? null : aiQr.trim());
  if (qr != null) meta['QR code'] = qr;
  final out = [words.trim(), if (qr != null) 'QR code: $qr', if (qr != null && describeQr(qr) != null) describeQr(qr)!].where((s) => s.isNotEmpty).join('\n');
  if (out.isEmpty) {
    throw IntakeError(llm.usable || onDeviceOcrAvailable
        ? 'Kantoi could not find any words or QR code in this picture. Type or paste the message instead.'
        : 'Reading words in pictures on this computer needs AI. Set up Gemini in Settings, or type the message instead.');
  }
  return out;
}

/// A PDF: static checks and text on the device; AI reading only if the text
/// cannot be extracted and the user agrees.
Future<String> _pdf(Uint8List bytes, LlmConfig llm, ConsentAsker consent, List<Finding> findings, Map<String, String> meta, _Step step, _Done done) async {
  final s = step('Document reader', 'Reading the PDF on your device');
  final PdfInfo p;
  try {
    p = await compute(readPdf, bytes);
  } catch (e) {
    done(s, 'Could not open it ($e)', StepStatus.failed);
    throw const IntakeError('Kantoi could not open this PDF. It may be damaged.');
  }
  meta.addAll(p.meta);
  findings.addAll(pdfFindings(p));
  final active = [if (p.javascript) 'script', if (p.launch) 'launch action', if (p.embeddedFiles) 'embedded files', if (p.submitsForm) 'form'];
  done(s, '${p.pages} page(s), ${p.links.length} link(s)${active.isEmpty ? ', no scripts' : ', has ${active.join(', ')}'}');
  var text = p.textReliable ? p.text : '';
  if (text.isEmpty) {
    if (canReadMedia(llm) && await consent()) {
      final a = step('Document reader', 'Sending the PDF you chose to ${llm.displayName} to read its words (you agreed to this)', sentOffDevice: true);
      try {
        text = await readDocumentWithAi(bytes, llm);
        done(a, '${text.length} characters read');
      } catch (e) {
        done(a, 'Failed ($e)', StepStatus.failed);
      }
    } else {
      done(step('Document reader', 'Reading scanned or protected text'), 'Skipped: the words could not be read on your device', StepStatus.skipped);
    }
  }
  if (text.isEmpty && p.links.isEmpty && findings.isEmpty) {
    throw const IntakeError('Kantoi could not read the words in this PDF. Take a screenshot of it and check that instead.');
  }
  final body = [text, if (p.links.isNotEmpty) 'Links in the document:\n${p.links.join('\n')}'].join('\n\n');
  _fakeDoc(body, meta, findings, step, done);
  return body.trim().isEmpty ? 'PDF document with no readable text' : body;
}

void _fakeDoc(String text, Map<String, String> meta, List<Finding> findings, _Step step, _Done done) {
  final s = step('Fake document check', 'Checking the letterhead, payment details, reference numbers and dates');
  final f = fakeDocumentFindings(text, meta);
  findings.addAll(f);
  done(s, f.isEmpty ? 'No signs of a forged letter' : f.map((x) => x.title).join(', '));
}

/// Plain description of a Malaysian payment QR (DuitNow / EMVCo): who the
/// money goes to.
String? describeQr(String qr) {
  final t = qr.trim();
  if (!t.startsWith('000201')) return null;
  final tags = <String, String>{};
  var i = 0;
  while (i + 4 <= t.length) {
    final id = t.substring(i, i + 2);
    final len = int.tryParse(t.substring(i + 2, i + 4));
    if (len == null || i + 4 + len > t.length) break;
    tags[id] = t.substring(i + 4, i + 4 + len);
    i += 4 + len;
  }
  final name = tags['59'];
  if (name == null) return null;
  final amount = tags['54'];
  return 'Payment QR: pays to "$name"${tags['60'] != null ? ' in ${tags['60']}' : ''}${amount != null ? ', amount RM$amount' : ''}.';
}

String _plan(IntakeKind k) => switch (k) {
      IntakeKind.image => 'Running the QR reader and the text reader together.',
      IntakeKind.pdf || IntakeKind.docx => 'Reading text, links and hidden content.',
      IntakeKind.apk => 'Reading its permissions only.',
      IntakeKind.audio || IntakeKind.video => 'Turning speech into text.',
      IntakeKind.chatLog => 'Reading the chat.',
      _ => '',
    };

String _size(int n) => n >= 1024 * 1024 ? '${(n / 1024 / 1024).toStringAsFixed(1)} MB' : '${(n / 1024).ceil()} KB';

String _short(String s) => s.length > 60 ? '${s.substring(0, 60)}…' : s;
