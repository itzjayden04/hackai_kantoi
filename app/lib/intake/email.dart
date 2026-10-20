import '../engine/models.dart';
import '../engine/url_analyzer.dart' show officialBrandFor, registrableDomain;
import 'normalise.dart' show brandWords;

/// A pasted email with its headers split from the body.
class EmailParts {
  final Map<String, List<String>> headers;
  final String body;
  const EmailParts(this.headers, this.body);

  String? first(String name) => headers[name.toLowerCase()]?.firstOrNull;
  String get subject => first('subject') ?? '';
}

final _headerLine = RegExp(r'^([A-Za-z][A-Za-z0-9-]{1,40}):[ \t]?(.*)$');
const _known = {'from', 'to', 'subject', 'date', 'reply-to', 'return-path', 'received', 'authentication-results', 'message-id', 'cc', 'dkim-signature', 'received-spf', 'mime-version', 'content-type', 'sender'};

/// Returns the parsed email when [text] starts with real headers (at least a
/// From line plus one other known header), else null.
EmailParts? parseEmail(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final headers = <String, List<String>>{};
  String? last;
  var i = 0;
  for (; i < lines.length; i++) {
    final l = lines[i];
    if (l.trim().isEmpty) break;
    if ((l.startsWith(' ') || l.startsWith('\t')) && last != null) {
      final list = headers[last]!;
      list[list.length - 1] = '${list.last} ${l.trim()}';
      continue;
    }
    final m = _headerLine.firstMatch(l);
    if (m == null) {
      if (headers.isEmpty) return null;
      break;
    }
    last = m.group(1)!.toLowerCase();
    headers.putIfAbsent(last, () => []).add(m.group(2)!.trim());
  }
  final knownCount = headers.keys.where(_known.contains).length;
  if (!headers.containsKey('from') || knownCount < 2) return null;
  return EmailParts(headers, lines.skip(i).join('\n').trim());
}

/// Splits `PayPal Support <help@paypa1-secure.com>` into the name and address.
(String, String) splitAddress(String v) {
  final m = RegExp(r'^\s*"?([^"<]*?)"?\s*<([^>]+)>').firstMatch(v);
  if (m != null) return (m.group(1)!.trim(), m.group(2)!.trim().toLowerCase());
  final e = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+').firstMatch(v);
  return ('', (e?.group(0) ?? v).trim().toLowerCase());
}

String domainOf(String address) => registrableDomain(address.split('@').last.toLowerCase().replaceAll(RegExp(r'[>\s]'), ''));

/// Header checks: reply-to and return-path mismatch, SPF/DKIM/DMARC results,
/// and a brand in the display name that the sending domain does not own.
List<Finding> checkEmailHeaders(EmailParts e) {
  final out = <Finding>[];
  Finding f(CueCategory c, String title, String why, int w) =>
      Finding(category: c, title: title, explanation: why, weight: w, tool: 'Email header check');
  final from = e.first('from');
  if (from == null) return out;
  final (name, addr) = splitAddress(from);
  final fromDomain = domainOf(addr);

  final replyTo = e.first('reply-to');
  if (replyTo != null) {
    final rd = domainOf(splitAddress(replyTo).$2);
    if (rd.isNotEmpty && rd != fromDomain) {
      out.add(f(CueCategory.impersonation, 'Replies go to a different address',
          'The email says it is from $fromDomain, but your reply would go to $rd. Scammers do this to receive your answers.', 14));
    }
  }
  final rp = e.first('return-path');
  if (rp != null) {
    final d = domainOf(splitAddress(rp).$2);
    if (d.isNotEmpty && d != fromDomain && replyTo == null) {
      out.add(f(CueCategory.impersonation, 'Sent through a different domain',
          'The email was really sent from $d, not $fromDomain. This is common for bulk mail, but also for fakes.', 4));
    }
  }

  final auth = [...?e.headers['authentication-results'], ...?e.headers['received-spf']].join(' ').toLowerCase();
  final failed = <String>[
    for (final k in ['spf', 'dkim', 'dmarc'])
      if (RegExp('$k=(fail|softfail|permerror|none)').hasMatch(auth) || (k == 'spf' && RegExp(r'^\s*(fail|softfail)').hasMatch(auth))) k.toUpperCase(),
  ];
  final passed = ['spf', 'dkim', 'dmarc'].where((k) => auth.contains('$k=pass')).toList();
  if (failed.isNotEmpty) {
    out.add(f(CueCategory.impersonation, 'Failed sender checks',
        'Email providers could not confirm this email really came from $fromDomain (${failed.join(', ')} failed). Fake senders often fail these checks.', 16));
  } else if (passed.length >= 2) {
    out.add(f(CueCategory.legitimacy, 'Sender checks passed',
        'The email really came from $fromDomain. This only proves who sent it, not that $fromDomain is honest.', -3));
  }

  // "Maybank Security <alert@secure-mbb.xyz>": brand in the name, not in the domain.
  final nameKey = name.toLowerCase();
  final words = nameKey.split(RegExp(r'[^a-z0-9]+')).toSet();
  final squashed = nameKey.replaceAll(RegExp(r'[^a-z0-9]'), '');
  for (final entry in brandWords.entries) {
    if (!words.contains(entry.key) && !(entry.key.length >= 5 && squashed.contains(entry.key))) continue;
    final host = addr.split('@').last;
    final owner = officialBrandFor(host);
    final freeMail = RegExp(r'^(gmail|yahoo|hotmail|outlook|live|icloud|proton(mail)?|aol|ymail)\.').hasMatch(host);
    if (owner != entry.value) {
      out.add(f(CueCategory.impersonation, 'Name does not match the sender',
          'The sender calls itself "$name" but the email came from ${freeMail ? 'a free personal account' : host}, which ${entry.value} does not own.', 20));
    }
    break;
  }
  return out;
}

/// The text to investigate: who it is from, the subject and the body, without
/// the routing headers that would only add noise.
String emailText(EmailParts e) => [
      if (e.first('from') != null) 'From: ${e.first('from')}',
      if (e.first('reply-to') != null) 'Reply-To: ${e.first('reply-to')}',
      if (e.subject.isNotEmpty) 'Subject: ${e.subject}',
      '',
      e.body,
    ].join('\n').trim();
