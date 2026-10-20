import '../engine/attribution/fingerprint.dart' show hostOf;
import '../engine/forensics/homoglyphs.dart' show confusables;
import '../engine/models.dart';
import '../engine/url_analyzer.dart';

/// A site the Web & link blocker decided about.
class SiteVerdict {
  final String host;
  final bool block;
  final RiskLevel level;
  final String headline;
  final List<String> reasons;
  const SiteVerdict(this.host, this.block, this.level, this.headline, this.reasons);

  Map<String, dynamic> toJson() => {
        'host': host,
        'block': block,
        'level': level.name,
        'label': riskLabel(level),
        'headline': headline,
        'reasons': reasons,
      };
}

/// What a browser's address bar shows ("pos-tracking-my.top/pay",
/// "https://maybank2u.com.my") reduced to a link, or null when the text is a
/// search or half-typed.
String? addressBarLink(String text) {
  final s = text.trim();
  if (s.isEmpty || s.contains(' ') || s.length > 2048) return null;
  final m = RegExp(r'^(?:(https?)://)?([a-z0-9¡-￿-]+(?:\.[a-z0-9¡-￿-]+)+)(?::\d+)?(?:[/?#]\S*)?$', caseSensitive: false).firstMatch(s);
  if (m == null) return null;
  final tld = m.group(2)!.split('.').last;
  // "hello.world" style text and file names are not links.
  if (tld.length < 2 || RegExp(r'^\d+$').hasMatch(tld) && !RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(m.group(2)!)) return null;
  if (const {'jpg', 'png', 'pdf', 'txt', 'apk', 'doc', 'docx'}.contains(tld.toLowerCase())) return null;
  return m.group(1) == null ? 'https://$s' : s;
}

/// Decides fast, on the phone, whether to close a page the user opened.
/// [known] says whether the site is in Kantoi's scam list (and whether that
/// entry is demo data). No network: this runs on every page.
Future<SiteVerdict?> siteVerdict(String raw, {(bool, bool) Function(String url)? known}) async {
  final url = addressBarLink(raw);
  if (url == null) return null;
  final host = hostOf(url);
  if (host == null) return null;
  if (officialBrandFor(host) != null) return SiteVerdict(host, false, RiskLevel.safe, 'Official website', const []);

  final reasons = <String>[];
  var score = 0;
  final (listed, demo) = known?.call(url) ?? (false, false);
  if (listed) {
    reasons.add(demo ? 'On Kantoi\'s scam list (demo data)' : 'On Kantoi\'s list of scam websites');
    score += 40;
  }
  final a = await analyzeUrl(url, network: false, log: (tool, action, {sentOffDevice = false}) => LogStep(tool: tool, action: action));
  for (final f in a.findings.where((f) => f.isRisk).toList()..sort((x, y) => y.weight.compareTo(x.weight))) {
    reasons.add(f.title);
    score += f.weight;
  }
  // Latin letters mixed with Cyrillic or Greek look-alikes ("mаybank").
  final typed = RegExp(r'^(?:https?://)?([^/:?#]+)', caseSensitive: false).firstMatch(raw.trim())?.group(1)?.toLowerCase() ?? host;
  final mixed = typed.split('.').any((l) => RegExp('[a-z]').hasMatch(l) && l.split('').any(confusables.containsKey));
  if (mixed && !reasons.contains('Disguised web address')) {
    reasons.add('Uses look-alike letters');
    score += 22;
  }
  final level = score >= 40
      ? RiskLevel.danger
      : score >= 22
          ? RiskLevel.suspicious
          : score >= 8
              ? RiskLevel.caution
              : RiskLevel.safe;
  final block = level.index >= RiskLevel.suspicious.index;
  final imitates = a.report.imitates;
  final headline = listed
      ? 'This website is known for scams.'
      : imitates != null
          ? 'This website pretends to be $imitates, but it is not $imitates\'s real website.'
          : block
              ? 'This website shows several signs of a scam site.'
              : 'No strong scam signs.';
  return SiteVerdict(host, block, level, headline, reasons.take(3).toList());
}
