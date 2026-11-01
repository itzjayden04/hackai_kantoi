import '../models.dart';
import '../url_analyzer.dart' show brands, officialBrandFor, registrableDomain;

/// What the landing page's HTML shows, read as text. No script on the page is
/// ever run.
class LandingReport {
  final String? title;
  final bool asksPassword;
  final bool asksOtp;
  final bool asksCard;
  final bool loginWording;
  final Set<String> brandsSeen;
  final List<String> offsiteForms;
  /// A redirect done by a refresh tag or script, which plain redirects miss.
  final Uri? hiddenRedirect;
  final String? hiddenRedirectKind;
  /// Where the page posts what you type when it is not a normal form, e.g.
  /// "a Telegram bot" (read from the page's scripts, never run).
  final String? exfiltration;
  /// Official sites the page loads its logos and styles from.
  final Set<String> hotlinkedFrom;
  /// Tricks that stop people inspecting the page (right-click blocked,
  /// scrambled script).
  final List<String> evasions;
  final List<Finding> findings;
  const LandingReport({
    this.title,
    this.asksPassword = false,
    this.asksOtp = false,
    this.asksCard = false,
    this.loginWording = false,
    this.brandsSeen = const {},
    this.offsiteForms = const [],
    this.hiddenRedirect,
    this.hiddenRedirectKind,
    this.exfiltration,
    this.hotlinkedFrom = const {},
    this.evasions = const [],
    this.findings = const [],
  });
}

const _tool = 'Landing-page check';

// Brand names as they appear on web pages, mapped to the brands map keys.
const Map<String, String> _pageBrands = {
  'maybank': 'Maybank', 'maybank2u': 'Maybank', 'cimb': 'CIMB', 'public bank': 'Public Bank', 'pbe': 'Public Bank',
  'rhb': 'RHB', 'hong leong': 'Hong Leong Bank', 'ambank': 'AmBank', 'bank islam': 'Bank Islam', 'bsn': 'BSN',
  "touch 'n go": "Touch 'n Go", 'touch n go': "Touch 'n Go", 'tng digital': "Touch 'n Go", 'pos malaysia': 'Pos Malaysia',
  'poslaju': 'Pos Malaysia', 'pos laju': 'Pos Malaysia', 'j&t express': 'J&T Express', 'j&amp;t': 'J&T Express',
  'lhdn': 'LHDN', 'hasil': 'LHDN', 'mytax': 'LHDN', 'jpj': 'JPJ', 'pdrm': 'PDRM', 'polis diraja': 'PDRM', 'kwsp': 'KWSP',
  'i-akaun': 'KWSP', 'myeg': 'MyEG', 'bank negara': 'Bank Negara', 'shopee': 'Shopee', 'lazada': 'Lazada', 'paypal': 'PayPal',
  'netflix': 'Netflix', 'dhl': 'DHL',
};

final _titleRe = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false);
final _inputRe = RegExp(r'<input\b[^>]*>', caseSensitive: false);
final _formRe = RegExp(r'''<form\b[^>]*\baction\s*=\s*["']?([^"'\s>]+)''', caseSensitive: false);
final _metaRefreshRe = RegExp(
    r'''<meta\b[^>]*http-equiv\s*=\s*["']?refresh["']?[^>]*content\s*=\s*["']?\s*\d*\s*;?\s*url\s*=\s*['"]?([^"'>\s]+)''',
    caseSensitive: false);
final _jsRedirectRe = RegExp(
    r'''(?:window\.|document\.|self\.|top\.)?location(?:\.href)?\s*=\s*["']([^"']+)["']|location\.(?:replace|assign)\(\s*["']([^"']+)["']''',
    caseSensitive: false);
final _imgRe = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _loginRe = RegExp(
    r'\b(log ?in|sign ?in|log masuk|daftar masuk|username|user id|id pengguna|kata laluan|secure ?word|online banking|perbankan internet)\b',
    caseSensitive: false);

/// Services phishing kits post stolen logins to, straight from the page.
const Map<String, String> _exfilEndpoints = {
  r'api\.telegram\.org/bot': 'a Telegram bot',
  r'discord(app)?\.com/api/webhooks': 'a Discord webhook',
  r'hooks\.slack\.com/services': 'a Slack webhook',
  r'script\.google\.com/macros/s/': 'a Google Apps Script',
  r'webhook\.site/': 'a webhook.site address',
  r'formspree\.io/f/': 'a Formspree form',
  r'getform\.io/f/': 'a Getform form',
  r'submit-form\.com/': 'a submit-form.com form',
  r'formsubmit\.co/': 'a FormSubmit form',
  r'api\.ipify\.org|ipapi\.co/json|ip-api\.com/json': 'a visitor-tracking service',
};
/// Big platforms whose images and styles appear on ordinary sites (share
/// buttons, embeds, affiliate pictures), so loading from them proves nothing.
const _embeddedEverywhere = {'Google', 'Facebook', 'Microsoft', 'Apple', 'WhatsApp', 'Telegram', 'PayPal', 'Netflix', 'Shopee', 'Lazada', 'Grab'};
final _resourceRe = RegExp(r'''<(?:img|link)\b[^>]*\b(?:src|href)\s*=\s*["']?(https?://[^"'\s>]+)''', caseSensitive: false);
final _noRightClickRe = RegExp(
    r'''oncontextmenu\s*=\s*["']?\s*return\s+false|addEventListener\(\s*["']contextmenu["']|event\.button\s*==+\s*2|keyCode\s*==+\s*123|key\s*==+\s*["']F12["']|devtools(open|detect|-detect)''',
    caseSensitive: false);
final _scrambledRe = RegExp(
    r'''eval\s*\(\s*(atob|unescape|decodeURIComponent|function\s*\(\s*p\s*,\s*a\s*,\s*c\s*,\s*k\s*,\s*e)|document\.write\s*\(\s*(unescape|atob)\s*\(|\\x[0-9a-f]{2}(\\x[0-9a-f]{2}){40,}|["'][A-Za-z0-9+/=]{800,}["']''',
    caseSensitive: false);
final _countdownRe = RegExp(
    r'\b(offer|link|session|page|tawaran|pautan) (expires|ends|tamat) in\b|\b(countdown|count-down)\b.{0,200}\b(setInterval|setTimeout)\b|\b\d{1,2}:\d{2}\s*(minutes?|minit|left|lagi)\b',
    caseSensitive: false);

String _attr(String tag, String name) {
  final m = RegExp('\\b$name\\s*=\\s*["\']?([^"\'>]*)', caseSensitive: false).firstMatch(tag);
  return (m?.group(1) ?? '').toLowerCase();
}

/// The text a visitor sees: no scripts, styles, comments or tags, with the
/// common HTML entities decoded.
String visibleText(String html) => html
    .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
    .replaceAll(RegExp(r'<(script|style|noscript|template|svg)\b[\s\S]*?</\1>', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAllMapped(RegExp(r'&#(x[0-9a-f]+|\d+);', caseSensitive: false), (m) {
      final v = m[1]!.toLowerCase().startsWith('x') ? int.tryParse(m[1]!.substring(1), radix: 16) : int.tryParse(m[1]!);
      return v == null || v > 0x10FFFF ? ' ' : String.fromCharCode(v);
    })
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Reads a landing page's HTML for the signs of a phishing page.
LandingReport analyzeLandingHtml(String html, Uri page) {
  final host = page.host.toLowerCase();
  final official = officialBrandFor(host);
  final findings = <Finding>[];
  void add(CueCategory c, String title, String why, int w) =>
      findings.add(Finding(category: c, title: title, explanation: why, weight: w, tool: _tool));

  final title = _titleRe.firstMatch(html)?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
  var password = false, otp = false, card = false;
  for (final m in _inputRe.allMatches(html)) {
    final tag = m.group(0)!;
    final type = _attr(tag, 'type');
    final ids = '${_attr(tag, 'name')} ${_attr(tag, 'id')} ${_attr(tag, 'placeholder')} ${_attr(tag, 'autocomplete')} ${_attr(tag, 'aria-label')}';
    if (type == 'password' || RegExp(r'password|kata ?laluan|passwd|secureword').hasMatch(ids)) password = true;
    if (RegExp(r'\botp\b|\btac\b|one-time-code|verification|verify ?code|\bpin\b|kod').hasMatch(ids)) otp = true;
    if (RegExp(r'cc-number|cardnumber|card_number|card-number|card ?no|cvv|cvc|cc-csc|cc-exp|expiry|nombor kad').hasMatch(ids)) card = true;
  }

  final text = visibleText(html);
  final titleAndText = '${title ?? ''} $text'.toLowerCase();
  final seen = <String>{};
  // Brands in the title or a logo count more than a passing mention.
  final prominent = <String>{};
  bool mentions(String hay, String key) => RegExp('(^|[^a-z])${RegExp.escape(key)}([^a-z]|\$)').hasMatch(hay);
  for (final e in _pageBrands.entries) {
    if (mentions(titleAndText, e.key)) seen.add(e.value);
    if (mentions((title ?? '').toLowerCase(), e.key)) prominent.add(e.value);
  }
  for (final m in _imgRe.allMatches(html)) {
    final tag = m.group(0)!.toLowerCase();
    final src = '${_attr(tag, 'src')} ${_attr(tag, 'alt')}';
    for (final e in _pageBrands.entries) {
      if (e.key.length >= 3 && src.contains(e.key.replaceAll(' ', ''))) {
        seen.add(e.value);
        prominent.add(e.value);
      }
    }
  }
  final login = _loginRe.hasMatch(titleAndText);

  final offsite = <String>[];
  for (final m in _formRe.allMatches(html)) {
    final action = Uri.tryParse(m.group(1)!.replaceAll('&amp;', '&'));
    if (action == null) continue;
    final target = page.resolveUri(action);
    if (target.host.isEmpty || !target.scheme.startsWith('http')) continue;
    if (registrableDomain(target.host.toLowerCase()) != registrableDomain(host)) offsite.add(target.host);
  }

  Uri? hidden;
  String? hiddenKind;
  final meta = _metaRefreshRe.firstMatch(html);
  if (meta != null) {
    hidden = Uri.tryParse(meta.group(1)!);
    hiddenKind = 'page refresh tag';
  } else {
    final js = _jsRedirectRe.firstMatch(html);
    final target = js == null ? null : (js.group(1) ?? js.group(2));
    if (target != null && !target.startsWith('#') && !target.startsWith('javascript')) {
      hidden = Uri.tryParse(target);
      hiddenKind = 'script';
    }
  }
  if (hidden != null) {
    hidden = page.resolveUri(hidden);
    if (hidden.host.isEmpty || hidden == page) {
      hidden = null;
      hiddenKind = null;
    }
  }

  // Where scripts send what you type, read without running them.
  String? exfil;
  for (final e in _exfilEndpoints.entries) {
    if (RegExp(e.key, caseSensitive: false).hasMatch(html)) {
      exfil = e.value;
      break;
    }
  }
  // Logos and styles loaded straight from a real brand's website.
  final hotlinked = <String>{};
  if (official == null) {
    for (final m in _resourceRe.allMatches(html)) {
      final h = Uri.tryParse(m.group(1)!)?.host.toLowerCase() ?? '';
      final b = h.isEmpty ? null : officialBrandFor(h);
      if (b != null && !_embeddedEverywhere.contains(b) && registrableDomain(h) != registrableDomain(host)) hotlinked.add(b);
    }
  }
  final evasions = [
    if (_noRightClickRe.hasMatch(html)) 'blocks right-click or developer tools',
    if (_scrambledRe.hasMatch(html)) 'scrambled script',
  ];
  final countdown = _countdownRe.hasMatch(html);

  // Findings. A real brand page on its own domain is fine.
  if (official == null) {
    final fakeOf = seen.where((b) => brands.containsKey(b)).toList();
    final asksSecret = password || otp || card;
    if (asksSecret && fakeOf.isNotEmpty) {
      add(CueCategory.credentials, 'Asks for your ${_what(password, otp, card)} on a fake ${fakeOf.first} site',
          'The page shows the ${fakeOf.first} name and has a box for your ${_what(password, otp, card)}, but $host is not a ${fakeOf.first} website (${brands[fakeOf.first]!.first}).', 30);
    } else if (password) {
      add(CueCategory.credentials, 'Asks for your password on an unknown site',
          'The page has a password box, and $host is not a bank or company Kantoi knows. Never type a password you use elsewhere.', 14);
    } else if (card) {
      add(CueCategory.credentials, 'Asks for your card details',
          'The page asks for a card number or CVV on $host, which is not a known payment page.', 16);
    } else if (otp) {
      add(CueCategory.credentials, 'Asks for a one-time code',
          'The page has a box for a TAC, OTP or PIN. Typing it there lets someone else approve a payment.', 14);
    }
    final shown = prominent.where((b) => brands.containsKey(b)).toList();
    if (shown.isNotEmpty && !asksSecret && (login || shown.length == 1)) {
      add(CueCategory.impersonation, 'Uses ${shown.first}\'s name on a site it does not own',
          'The page shows the ${shown.first} name or logo, but $host is not an official ${shown.first} website.', login ? 14 : 8);
    }
  }
  if (offsite.isNotEmpty) {
    add(CueCategory.credentials, 'Sends what you type to another website',
        'A form on this page sends your answers to ${offsite.first}, a different website from the one you see.', 12);
  }
  final secrets = password || otp || card;
  // Without a box to type into, only chat bots are telling: ordinary sites
  // use forms services and IP lookups too.
  if (exfil != null && official == null && (secrets || exfil.contains('bot') || exfil.contains('Discord'))) {
    add(CueCategory.credentials, secrets ? 'Sends what you type to $exfil' : 'Page reports to $exfil',
        secrets
            ? 'The page\'s script posts what you type straight to $exfil. Phishing kits use this to collect stolen logins and codes.'
            : 'The page\'s script contacts $exfil, which phishing kits use to collect visitors\' details.',
        secrets ? 26 : 10);
  }
  if (hotlinked.isNotEmpty) {
    add(CueCategory.impersonation, 'Borrows ${hotlinked.first}\'s logos from the real site',
        'The page loads its pictures or styles straight from the official ${hotlinked.first} website, so it looks real, but $host is not ${hotlinked.first}.',
        16);
  }
  if (evasions.isNotEmpty && official == null) {
    add(CueCategory.obfuscation, 'Hides how the page works',
        'The page ${evasions.join(' and ')}. Genuine sites have no reason to stop you looking.', 8);
  }
  if (countdown && official == null && (password || otp || card || seen.isNotEmpty)) {
    add(CueCategory.urgency, 'Countdown timer on the page', 'A ticking timer rushes you into typing your details before you think.', 6);
  }
  if (hidden != null) {
    add(CueCategory.link, 'Sends you on with a hidden redirect',
        'The page moves you to ${hidden.host} using a $hiddenKind, a trick used to hide the final page from link checkers.', 6);
  }

  return LandingReport(
    title: title == null || title.isEmpty ? null : (title.length > 120 ? '${title.substring(0, 120)}…' : title),
    asksPassword: password,
    asksOtp: otp,
    asksCard: card,
    loginWording: login,
    brandsSeen: seen,
    offsiteForms: offsite,
    hiddenRedirect: hidden,
    hiddenRedirectKind: hiddenKind,
    exfiltration: exfil,
    hotlinkedFrom: hotlinked,
    evasions: evasions,
    findings: findings,
  );
}

String _what(bool password, bool otp, bool card) {
  final parts = [
    if (password) 'password',
    if (otp) 'one-time code',
    if (card) 'card details',
  ];
  return parts.length < 2 ? parts.join() : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}

/// Compares the page a desktop visitor sees with what a Malaysian phone sees.
/// Scam sites often show phones the trap and desktops (where checkers run) a
/// harmless page.
Finding? compareViews({
  required int? mobileStatus,
  required int? desktopStatus,
  required Uri mobileFinal,
  required Uri desktopFinal,
  required String? mobileTitle,
  required String? desktopTitle,
  required int mobileBytes,
  required int desktopBytes,
  bool mobileAsksSecrets = false,
  bool desktopAsksSecrets = false,
}) {
  final reasons = <String>[];
  final okM = mobileStatus != null && mobileStatus < 400;
  final okD = desktopStatus != null && desktopStatus < 400;
  if (okM != okD) reasons.add('one view loads and the other is blocked ($mobileStatus on phone, $desktopStatus on computer)');
  if (registrableDomain(mobileFinal.host.toLowerCase()) != registrableDomain(desktopFinal.host.toLowerCase())) {
    reasons.add('phones are sent to ${mobileFinal.host} but computers to ${desktopFinal.host}');
  }
  final tm = (mobileTitle ?? '').trim().toLowerCase(), td = (desktopTitle ?? '').trim().toLowerCase();
  if (tm != td && (tm.isNotEmpty || td.isNotEmpty)) reasons.add('the page titles differ');
  if (mobileAsksSecrets != desktopAsksSecrets) {
    reasons.add('only the ${mobileAsksSecrets ? 'phone' : 'computer'} view asks for a password, code or card');
  }
  final big = mobileBytes > desktopBytes ? mobileBytes : desktopBytes;
  final small = mobileBytes > desktopBytes ? desktopBytes : mobileBytes;
  if (big - small > 5000 && big > small * 3) reasons.add('one page is ${small == 0 ? 'empty' : 'over 3 times bigger'}');
  // A title change alone can be a harmless A/B test; ask for two differences
  // or a hard one.
  final hard = reasons.any((r) => r.startsWith('one view') || r.startsWith('phones') || r.startsWith('only the'));
  if (reasons.isEmpty || (!hard && reasons.length < 2)) return null;
  return Finding(
    category: CueCategory.link,
    title: 'Shows different pages to different visitors',
    explanation: 'Kantoi opened the link as a Malaysian phone and as a computer: ${reasons.join('; ')}. '
        'Scam sites do this to hide from checkers.',
    weight: 14,
    tool: 'Cloaking check',
  );
}
