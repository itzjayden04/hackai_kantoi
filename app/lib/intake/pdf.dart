import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../engine/models.dart';

/// What a PDF contains, read on the device without any PDF library.
class PdfInfo {
  final String text;
  final bool textReliable;
  final int pages;
  final List<String> links;
  final bool javascript;
  final bool autoRun;
  final bool launch;
  final bool embeddedFiles;
  final bool submitsForm;
  final bool encrypted;
  final Map<String, String> meta;
  const PdfInfo({
    required this.text,
    required this.textReliable,
    this.pages = 0,
    this.links = const [],
    this.javascript = false,
    this.autoRun = false,
    this.launch = false,
    this.embeddedFiles = false,
    this.submitsForm = false,
    this.encrypted = false,
    this.meta = const {},
  });
}

class _Obj {
  final String dict;
  final Uint8List? stream;
  const _Obj(this.dict, this.stream);
}

/// Parses a PDF: objects (including compressed object streams), page text
/// via each font's ToUnicode map, link annotations, active content markers
/// and the document info. Throws [FormatException] if it is not a PDF.
PdfInfo readPdf(Uint8List bytes) {
  final src = latin1.decode(bytes);
  if (!src.startsWith('%PDF') && !src.substring(0, src.length.clamp(0, 1024)).contains('%PDF')) {
    throw const FormatException('Not a PDF file');
  }
  final objs = <int, _Obj>{};
  final head = RegExp(r'(\d+)\s+\d+\s+obj\b');
  var pos = 0;
  while (true) {
    final m = head.allMatches(src, pos).firstOrNull;
    if (m == null) break;
    final start = m.end;
    final num = int.parse(m.group(1)!);
    final endObj = src.indexOf('endobj', start);
    final streamAt = _streamKeyword(src, start, endObj < 0 ? src.length : endObj);
    if (streamAt != null) {
      final dict = src.substring(start, streamAt.$1);
      var dataStart = streamAt.$2;
      final len = int.tryParse(RegExp(r'/Length\s+(\d+)(?!\s+\d+\s+R)').firstMatch(dict)?.group(1) ?? '');
      var dataEnd = len != null && dataStart + len <= src.length && src.substring(dataStart + len).trimLeft().startsWith('endstream')
          ? dataStart + len
          : src.indexOf('endstream', dataStart);
      if (dataEnd < 0) dataEnd = src.length;
      objs[num] = _Obj(dict, _decode(dict, Uint8List.sublistView(bytes, dataStart, dataEnd)));
      final after = src.indexOf('endobj', dataEnd);
      pos = after < 0 ? dataEnd : after + 6;
    } else {
      final end = endObj < 0 ? src.length : endObj;
      objs[num] = _Obj(src.substring(start, end), null);
      pos = endObj < 0 ? src.length : endObj + 6;
    }
  }
  // Compressed object streams hold more objects.
  for (final o in objs.values.toList()) {
    if (o.stream == null || !RegExp(r'/Type\s*/ObjStm').hasMatch(o.dict)) continue;
    final first = int.tryParse(RegExp(r'/First\s+(\d+)').firstMatch(o.dict)?.group(1) ?? '') ?? 0;
    final body = latin1.decode(o.stream!);
    final nums = RegExp(r'\d+').allMatches(body.substring(0, first.clamp(0, body.length))).map((m) => int.parse(m.group(0)!)).toList();
    for (var i = 0; i + 1 < nums.length; i += 2) {
      final s = first + nums[i + 1];
      final e = i + 3 < nums.length ? first + nums[i + 3] : body.length;
      if (s < body.length && e <= body.length && s <= e) objs.putIfAbsent(nums[i], () => _Obj(body.substring(s, e), null));
    }
  }

  final allDicts = objs.values.map((o) => _unhexNames(o.dict)).join('\n') + _unhexNames(_trailers(src));
  final links = <String>{};
  for (final m in RegExp(r'/URI\s*(\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]*>)').allMatches(allDicts)) {
    final v = _pdfString(m.group(1)!).trim();
    if (v.isNotEmpty) links.add(v);
  }
  final js = RegExp(r'/(JavaScript|JS)\b').hasMatch(allDicts);
  final meta = _info(objs, src);

  // Fonts: name -> ToUnicode map, per page with a file-wide fallback.
  final cmaps = <int, _CMap?>{};
  _CMap? cmapFor(int fontObj) {
    final f = objs[fontObj];
    final ref = f == null ? null : RegExp(r'/ToUnicode\s+(\d+)\s+\d+\s+R').firstMatch(f.dict);
    if (ref == null) return null;
    final id = int.parse(ref.group(1)!);
    return cmaps.putIfAbsent(id, () => _CMap.parse(objs[id]?.stream));
  }

  Map<String, _CMap?> fontsIn(String resources) {
    final out = <String, _CMap?>{};
    var fontDict = RegExp(r'/Font\s*<<([\s\S]*?)>>').firstMatch(resources)?.group(1);
    final fontRef = RegExp(r'/Font\s+(\d+)\s+\d+\s+R').firstMatch(resources);
    if (fontDict == null && fontRef != null) fontDict = objs[int.parse(fontRef.group(1)!)]?.dict;
    for (final m in RegExp(r'/([^\s/<>\[\]()]+)\s+(\d+)\s+\d+\s+R').allMatches(fontDict ?? '')) {
      out[m.group(1)!] = cmapFor(int.parse(m.group(2)!));
    }
    return out;
  }

  final globalFonts = <String, _CMap?>{};
  for (final o in objs.values) {
    if (o.dict.contains('/Font')) globalFonts.addAll(fontsIn(o.dict));
  }
  final text = StringBuffer();
  var pages = 0;
  for (final o in objs.values) {
    if (!RegExp(r'/Type\s*/Page(?![s\w])').hasMatch(o.dict)) continue;
    pages++;
    var res = RegExp(r'/Resources\s*(<<[\s\S]*>>)').firstMatch(o.dict)?.group(1) ?? '';
    final resRef = RegExp(r'/Resources\s+(\d+)\s+\d+\s+R').firstMatch(o.dict);
    if (resRef != null) res = objs[int.parse(resRef.group(1)!)]?.dict ?? '';
    final fonts = {...globalFonts, ...fontsIn(res)};
    final contents = RegExp(r'/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)').firstMatch(o.dict)?.group(1) ?? '';
    for (final r in RegExp(r'(\d+)\s+\d+\s+R').allMatches(contents)) {
      final s = objs[int.parse(r.group(1)!)]?.stream;
      if (s != null) text.write(_contentText(s, fonts));
    }
    text.write('\n\n');
  }
  final out = text.toString().replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r' *\n *'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return PdfInfo(
    text: out,
    textReliable: textLooksReadable(out),
    pages: pages,
    links: links.toList(),
    javascript: js,
    autoRun: js && RegExp(r'/(OpenAction|AA)\b').hasMatch(allDicts),
    launch: RegExp(r'/Launch\b').hasMatch(allDicts),
    embeddedFiles: RegExp(r'/EmbeddedFiles?\b').hasMatch(allDicts),
    submitsForm: RegExp(r'/SubmitForm\b').hasMatch(allDicts),
    encrypted: RegExp(r'/Encrypt\b').hasMatch(_trailers(src)),
    meta: meta,
  );
}

/// True when [t] is mostly real words rather than font-code garbage.
bool textLooksReadable(String t) {
  if (t.replaceAll(RegExp(r'\s'), '').length < 15) return false;
  var good = 0, total = 0;
  for (final r in t.runes) {
    if (r == 0x20 || r == 0x0A) continue;
    total++;
    final ok = (r >= 0x21 && r <= 0x7E) || (r >= 0xC0 && r <= 0x24F) || (r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x0B80 && r <= 0x0BFF) || r == 0x2019 || r == 0x201C || r == 0x201D || r == 0x2022;
    if (ok) good++;
  }
  final words = RegExp(r'[A-Za-z]{3,}').allMatches(t).length;
  return total > 0 && good / total > 0.85 && (words >= 3 || RegExp(r'[一-鿿஀-௿]').hasMatch(t));
}

(int, int)? _streamKeyword(String src, int from, int limit) {
  final i = src.indexOf('stream', from);
  if (i < 0 || i > limit) return null;
  if (!src.substring(from, i).trimRight().endsWith('>>')) return null;
  var d = i + 6;
  if (d < src.length && src[d] == '\r') d++;
  if (d < src.length && src[d] == '\n') d++;
  return (i, d);
}

String _trailers(String src) => RegExp(r'trailer\s*<<[\s\S]*?>>').allMatches(src).map((m) => m.group(0)!).join('\n') +
    RegExp(r'/Type\s*/XRef[\s\S]*?>>').allMatches(src).map((m) => m.group(0)!).join('\n');

String _unhexNames(String s) => s.replaceAllMapped(RegExp(r'#([0-9A-Fa-f]{2})'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));

Uint8List? _decode(String dict, Uint8List data) {
  final filter = RegExp(r'/Filter\s*(\[[^\]]*\]|/\w+)').firstMatch(dict)?.group(1) ?? '';
  if (filter.isEmpty) return data;
  if (filter.contains('FlateDecode') && !RegExp(r'/(DCT|JPX|CCITTFax|JBIG2)Decode').hasMatch(filter)) {
    try {
      return ZLibDecoder().decodeBytes(data);
    } catch (_) {
      try {
        return ZLibDecoder().decodeBytes(data, raw: true);
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

Map<String, String> _info(Map<int, _Obj> objs, String src) {
  final ref = RegExp(r'/Info\s+(\d+)\s+\d+\s+R').firstMatch(src);
  var dict = ref == null ? null : objs[int.parse(ref.group(1)!)]?.dict;
  dict ??= objs.values.map((o) => o.dict).where((d) => d.contains('/Producer') || d.contains('/Creator')).firstOrNull;
  final out = <String, String>{};
  if (dict == null) return out;
  for (final (key, label) in [
    ('Title', 'Title'),
    ('Author', 'Author'),
    ('Creator', 'Made with'),
    ('Producer', 'Producer'),
    ('CreationDate', 'Created'),
    ('ModDate', 'Modified'),
  ]) {
    final m = RegExp('/$key\\s*(\\((?:\\\\.|[^\\\\)])*\\)|<[0-9A-Fa-f\\s]*>)').firstMatch(dict);
    if (m == null) continue;
    var v = _pdfString(m.group(1)!).trim();
    if (key.endsWith('Date')) v = pdfDate(v)?.toIso8601String() ?? v;
    if (v.isNotEmpty) out[label] = v;
  }
  return out;
}

/// "D:20260412093000+08'00'" -> DateTime.
DateTime? pdfDate(String s) {
  final m = RegExp(r'D?:?(\d{4})(\d{2})?(\d{2})?(\d{2})?(\d{2})?(\d{2})?').firstMatch(s);
  if (m == null) return null;
  int g(int i, int d) => int.tryParse(m.group(i) ?? '') ?? d;
  return DateTime(g(1, 2000), g(2, 1), g(3, 1), g(4, 0), g(5, 0), g(6, 0));
}

/// Decodes a PDF literal "(..)" or hex "<..>" string, including UTF-16 text.
String _pdfString(String tok) => _bytesToText(_stringBytes(tok));

List<int> _stringBytes(String tok) {
  if (tok.startsWith('<')) {
    var h = tok.substring(1, tok.length - 1).replaceAll(RegExp(r'\s'), '');
    if (h.length.isOdd) h += '0';
    return [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
  }
  return _literal(tok.substring(1, tok.length - 1));
}

List<int> _literal(String s) {
  final out = <int>[];
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c != 0x5C || i + 1 >= s.length) {
      out.add(c & 0xFF);
      continue;
    }
    final n = s[++i];
    switch (n) {
      case 'n':
        out.add(10);
      case 'r':
        out.add(13);
      case 't':
        out.add(9);
      case 'b':
        out.add(8);
      case 'f':
        out.add(12);
      case '\r' || '\n':
        if (n == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      default:
        final oct = RegExp(r'^[0-7]{1,3}').firstMatch(s.substring(i));
        if (oct != null) {
          out.add(int.parse(oct.group(0)!, radix: 8) & 0xFF);
          i += oct.group(0)!.length - 1;
        } else {
          out.add(n.codeUnitAt(0) & 0xFF);
        }
    }
  }
  return out;
}

String _bytesToText(List<int> b) {
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) return _utf16be(b.sublist(2));
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) return utf8.decode(b.sublist(3), allowMalformed: true);
  return latin1.decode(b);
}

String _utf16be(List<int> b) => String.fromCharCodes([for (var i = 0; i + 1 < b.length; i += 2) (b[i] << 8) | b[i + 1]]);

class _CMap {
  final int codeBytes;
  final Map<int, String> map;
  const _CMap(this.codeBytes, this.map);

  static _CMap? parse(Uint8List? data) {
    if (data == null) return null;
    final s = latin1.decode(data);
    final space = RegExp(r'begincodespacerange\s*<([0-9A-Fa-f]+)>').firstMatch(s);
    final bytes = space == null ? 2 : (space.group(1)!.length / 2).ceil();
    final map = <int, String>{};
    String hexText(String h) {
      final b = [for (var i = 0; i + 1 < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
      return _utf16be(b);
    }

    for (final block in RegExp(r'beginbfchar([\s\S]*?)endbfchar').allMatches(s)) {
      for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>').allMatches(block.group(1)!)) {
        map[int.parse(m.group(1)!, radix: 16)] = hexText(m.group(2)!);
      }
    }
    for (final block in RegExp(r'beginbfrange([\s\S]*?)endbfrange').allMatches(s)) {
      for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<[0-9A-Fa-f]*>|\[[^\]]*\])').allMatches(block.group(1)!)) {
        final lo = int.parse(m.group(1)!, radix: 16), hi = int.parse(m.group(2)!, radix: 16);
        if (hi - lo > 0xFFFF || hi < lo) continue;
        final dst = m.group(3)!;
        if (dst.startsWith('[')) {
          final items = RegExp(r'<([0-9A-Fa-f]*)>').allMatches(dst).toList();
          for (var i = 0; i < items.length && lo + i <= hi; i++) {
            map[lo + i] = hexText(items[i].group(1)!);
          }
        } else {
          final h = dst.substring(1, dst.length - 1);
          if (h.isEmpty) continue;
          final base = int.parse(h, radix: 16);
          final width = h.length;
          for (var c = lo; c <= hi; c++) {
            map[c] = hexText((base + c - lo).toRadixString(16).padLeft(width, '0'));
          }
        }
      }
    }
    return map.isEmpty ? null : _CMap(bytes, map);
  }

  String decode(List<int> b) {
    final out = StringBuffer();
    for (var i = 0; i + codeBytes <= b.length; i += codeBytes) {
      var code = 0;
      for (var j = 0; j < codeBytes; j++) {
        code = (code << 8) | b[i + j];
      }
      out.write(map[code] ?? '');
    }
    return out.toString();
  }
}

class _PStr {
  final List<int> b;
  const _PStr(this.b);
}

/// Pulls the shown text out of one page content stream.
String _contentText(Uint8List data, Map<String, _CMap?> fonts) {
  final s = latin1.decode(data);
  final out = StringBuffer();
  final stack = <Object>[];
  _CMap? font;
  double? lastY;
  var last = '';
  void emit(List<int> b) {
    final t = font?.decode(b) ?? latin1.decode(b);
    if (t.isEmpty) return;
    out.write(t);
    last = t[t.length - 1];
  }

  void newline() {
    if (last.isNotEmpty && last != '\n') out.write(last = '\n');
  }

  void space() {
    if (last.isNotEmpty && last != ' ' && last != '\n') out.write(last = ' ');
  }

  var i = 0;
  List<Object>? array;
  while (i < s.length) {
    final c = s[i];
    if (' \t\r\n\f\x00'.contains(c)) {
      i++;
    } else if (c == '%') {
      final e = s.indexOf('\n', i);
      i = e < 0 ? s.length : e + 1;
    } else if (c == '(') {
      var depth = 0, j = i;
      for (; j < s.length; j++) {
        if (s[j] == '\\') {
          j++;
          continue;
        }
        if (s[j] == '(') depth++;
        if (s[j] == ')' && --depth == 0) break;
      }
      (array ?? stack).add(_PStr(_literal(s.substring(i + 1, j.clamp(i + 1, s.length)))));
      i = j + 1;
    } else if (c == '<' && i + 1 < s.length && s[i + 1] == '<') {
      i += 2;
    } else if (c == '>' && i + 1 < s.length && s[i + 1] == '>') {
      i += 2;
    } else if (c == '<') {
      final e = s.indexOf('>', i);
      final end = e < 0 ? s.length : e;
      (array ?? stack).add(_PStr(_stringBytes('${s.substring(i, end)}>')));
      i = end + 1;
    } else if (c == '[') {
      array = [];
      i++;
    } else if (c == ']') {
      stack.add(array ?? <Object>[]);
      array = null;
      i++;
    } else if (c == '/') {
      final m = RegExp(r'/[^\s/<>\[\]()%{}]*').matchAsPrefix(s, i)!;
      (array ?? stack).add(m.group(0)!);
      i = m.end;
    } else if (RegExp(r'[-+.\d]').hasMatch(c)) {
      final m = RegExp(r'[-+]?(\d+\.?\d*|\.\d+)').matchAsPrefix(s, i);
      if (m == null) {
        i++;
        continue;
      }
      (array ?? stack).add(double.parse(m.group(0)!));
      i = m.end;
    } else {
      final m = RegExp(r"[A-Za-z'\x22*]+").matchAsPrefix(s, i);
      if (m == null) {
        i++;
        continue;
      }
      final op = m.group(0)!;
      i = m.end;
      switch (op) {
        case 'Tf':
          final name = stack.whereType<String>().lastOrNull;
          if (name != null) font = fonts[name.substring(1)];
        case 'Tj' || "'" || '"':
          if (op != 'Tj') newline();
          final str = stack.whereType<_PStr>().lastOrNull;
          if (str != null) emit(str.b);
        case 'TJ':
          final arr = stack.whereType<List<Object>>().lastOrNull ?? const [];
          for (final e in arr) {
            if (e is _PStr) emit(e.b);
            if (e is double && e < -200) space();
          }
        case 'Td' || 'TD':
          final nums = stack.whereType<double>().toList();
          if (nums.length >= 2 && nums.last.abs() > 0.1) {
            newline();
          } else {
            space();
          }
        case 'T*':
          newline();
        case 'Tm':
          final nums = stack.whereType<double>().toList();
          if (nums.length >= 6) {
            final y = lastY;
            if (y != null && (nums[5] - y).abs() > 1) {
              newline();
            } else {
              space();
            }
            lastY = nums[5];
          }
        case 'ET':
          space();
        case 'ID':
          final e = RegExp(r'\sEI(\s|$)').firstMatch(s.substring(i));
          i = e == null ? s.length : i + e.end;
      }
      stack.clear();
    }
  }
  return out.toString();
}

/// Static checks on a PDF: scripts, auto-run actions, launch actions,
/// embedded files and forms that send data away.
List<Finding> pdfFindings(PdfInfo p) => [
      if (p.javascript)
        Finding(
          category: CueCategory.file,
          title: p.autoRun ? 'Runs a script when opened' : 'Contains a script',
          explanation: 'This PDF has JavaScript inside${p.autoRun ? ' that starts by itself when you open it' : ''}. Normal letters and bills never need this.',
          weight: p.autoRun ? 25 : 15,
          tool: 'Document check',
        ),
      if (p.launch)
        const Finding(
          category: CueCategory.file,
          title: 'Tries to open a program',
          explanation: 'This PDF has an action that tries to start a program on your computer. Do not allow it.',
          weight: 30,
          tool: 'Document check',
        ),
      if (p.embeddedFiles)
        const Finding(
          category: CueCategory.file,
          title: 'Has files hidden inside',
          explanation: 'This PDF carries other files inside it. Do not open any attachment from it.',
          weight: 12,
          tool: 'Document check',
        ),
      if (p.submitsForm)
        const Finding(
          category: CueCategory.credentials,
          title: 'Form sends your details online',
          explanation: 'Typing into this PDF form sends what you type to a website. Never enter bank or login details in a PDF.',
          weight: 12,
          tool: 'Document check',
        ),
    ];
