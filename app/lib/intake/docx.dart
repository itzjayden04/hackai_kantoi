import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../engine/models.dart';

/// What a Word document contains, read on the device.
class DocxInfo {
  final String text;
  final List<String> links;
  final bool hasMacros;
  final List<String> externalTemplates;
  final List<String> embeddedObjects;
  final Map<String, String> meta;
  const DocxInfo({
    required this.text,
    this.links = const [],
    this.hasMacros = false,
    this.externalTemplates = const [],
    this.embeddedObjects = const [],
    this.meta = const {},
  });
}

String _xml(Archive a, String name) {
  final f = a.findFile(name);
  return f == null ? '' : utf8.decode(f.content, allowMalformed: true);
}

String unescapeXml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16)))
    .replaceAll('&amp;', '&');

/// Reads a .docx/.docm: body text, hyperlinks, macros, remote templates and
/// author/date metadata. Throws [FormatException] if it is not a Word file.
DocxInfo readDocx(Uint8List bytes) {
  final a = ZipDecoder().decodeBytes(bytes);
  final doc = _xml(a, 'word/document.xml');
  if (doc.isEmpty) throw const FormatException('No word/document.xml inside');
  final text = StringBuffer();
  for (final p in RegExp(r'<w:p[ >][\s\S]*?</w:p>|<w:p/>').allMatches(doc)) {
    final para = p.group(0)!;
    for (final m in RegExp(r'<w:t(?: [^>]*)?>([^<]*)</w:t>|<w:tab/>|<w:br/>').allMatches(para)) {
      final g = m.group(0)!;
      text.write(g.startsWith('<w:tab') ? '\t' : g.startsWith('<w:br') ? '\n' : unescapeXml(m.group(1)!));
    }
    text.write('\n');
  }
  final links = <String>[];
  final templates = <String>[];
  final objects = <String>[];
  for (final f in a.files.where((f) => f.isFile && f.name.endsWith('.rels'))) {
    final rels = utf8.decode(f.content, allowMalformed: true);
    for (final r in RegExp(r'<Relationship\b[^>]*>').allMatches(rels)) {
      final tag = r.group(0)!;
      final type = RegExp(r'Type="([^"]*)"').firstMatch(tag)?.group(1) ?? '';
      final target = unescapeXml(RegExp(r'Target="([^"]*)"').firstMatch(tag)?.group(1) ?? '');
      final external = tag.contains('TargetMode="External"');
      if (!external) continue;
      if (type.endsWith('/hyperlink')) {
        links.add(target);
      } else if (type.endsWith('/attachedTemplate') || type.endsWith('/frame') || type.endsWith('/subDocument')) {
        templates.add(target);
      } else if (type.endsWith('/oleObject')) {
        objects.add(target);
      }
    }
  }
  final hasMacros = a.files.any((f) => f.name.toLowerCase().endsWith('vbaproject.bin'));
  objects.addAll(a.files.where((f) => f.name.startsWith('word/embeddings/')).map((f) => f.name.split('/').last));

  final meta = <String, String>{};
  final core = _xml(a, 'docProps/core.xml');
  for (final (tag, key) in [
    ('dc:creator', 'Author'),
    ('cp:lastModifiedBy', 'Last edited by'),
    ('dcterms:created', 'Created'),
    ('dcterms:modified', 'Modified'),
    ('dc:title', 'Title'),
  ]) {
    final m = RegExp('<$tag[^>]*>([^<]*)</$tag>').firstMatch(core);
    if (m != null && m.group(1)!.trim().isNotEmpty) meta[key] = unescapeXml(m.group(1)!.trim());
  }
  final app = RegExp(r'<Application>([^<]*)</Application>').firstMatch(_xml(a, 'docProps/app.xml'))?.group(1);
  if (app != null) meta['Made with'] = app;
  return DocxInfo(
    text: text.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim(),
    links: links.toSet().toList(),
    hasMacros: hasMacros,
    externalTemplates: templates,
    embeddedObjects: objects,
    meta: meta,
  );
}

/// Static checks on a Word file: macros, remote templates and embedded objects.
List<Finding> docxFindings(DocxInfo d) => [
      if (d.hasMacros)
        const Finding(
          category: CueCategory.file,
          title: 'Contains macros',
          explanation: 'This Word file has hidden programs (macros) that can install harmful software if you click "Enable content". Never enable it.',
          weight: 30,
          tool: 'Document check',
        ),
      if (d.externalTemplates.isNotEmpty)
        Finding(
          category: CueCategory.file,
          title: 'Loads content from the internet',
          explanation: 'When opened, this file fetches a template from ${d.externalTemplates.first}. This trick is used to sneak in harmful code.',
          weight: 25,
          tool: 'Document check',
        ),
      if (d.embeddedObjects.isNotEmpty)
        Finding(
          category: CueCategory.file,
          title: 'Has files hidden inside',
          explanation: 'The document carries ${d.embeddedObjects.length} embedded object(s). Do not double-click anything inside it.',
          weight: 8,
          tool: 'Document check',
        ),
    ];
