import '../engine/entities.dart';
import '../engine/models.dart';

/// Agencies and banks whose letterheads are forged most often, with the
/// words that mark a letter as theirs.
const _letterheads = <String, String>{
  'court': r"\b(mahkamah (majistret|sesyen|tinggi)|magistrates?'? court|sessions court|high court|notis mahkamah|court (order|summons|notice))\b",
  'LHDN': r'\b(lembaga hasil dalam negeri|lhdn|inland revenue board|hasil\.gov\.my)\b',
  'PDRM': r'\b(polis diraja malaysia|royal malaysia police|pdrm|ibu pejabat polis)\b',
  'Bank Negara': r'\b(bank negara malaysia|central bank of malaysia)\b',
  'a bank': r'\b(maybank|cimb bank|public bank|rhb bank|hong leong bank|ambank|bank islam|bank rakyat|bsn)\b',
  'MCMC': r'\b(suruhanjaya komunikasi dan multimedia|mcmc)\b',
};

final _payInstruction = RegExp(
    r'\b(transfer|pindahkan|bayar|pay(ment)?|deposit|bank[- ]in|masukkan)\b.{0,80}\b(account|akaun|a/c|no\.? akaun|bank)\b|\b(account|akaun) (no|number|nombor)\b',
    caseSensitive: false);
final _payeeName = RegExp(r'\b(account name|nama akaun|nama pemegang akaun|payee|beneficiary|penerima)\s*[:\-]\s*([^\n]{3,60})', caseSensitive: false);
final _company = RegExp(r'\b(sdn\.? bhd|berhad|bhd|enterprise|trading|plc|ltd|limited|bank|kerajaan|government|jabatan|lembaga|hasil|negara|treasury|perbendaharaan|accountant general|akauntan negara)\b', caseSensitive: false);
final _courtCase = RegExp(r'\b(case no\.?|no\.? kes|guaman no\.?|saman no\.?|case number)\s*[:\-]?\s*([A-Z0-9/\-\s]{4,40})', caseSensitive: false);
final _courtFormat = RegExp(r'[A-Z]{2,3}-?\s?[A-Z0-9]{2,8}-\d{1,5}-\d{1,2}/\d{4}');
final _taxRef = RegExp(r'\b(no\.? (rujukan|cukai)|tax (ref(erence)?|file) no\.?|income tax no\.?)\s*[:\-]?\s*([A-Z0-9 ]{5,20})', caseSensitive: false);
final _taxFormat = RegExp(r'^(SG|OG|IG|C|D|E|F|J|TF|TP|TA|PT|TC|CS|TR|LE|TN)\s?\d{6,11}', caseSensitive: false);

const _months = {
  'jan': 1, 'january': 1, 'januari': 1, 'feb': 2, 'february': 2, 'februari': 2, 'mar': 3, 'march': 3, 'mac': 3,
  'apr': 4, 'april': 4, 'may': 5, 'mei': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7, 'julai': 7, 'aug': 8,
  'august': 8, 'ogos': 8, 'sep': 9, 'sept': 9, 'september': 9, 'oct': 10, 'october': 10, 'oktober': 10,
  'nov': 11, 'november': 11, 'dec': 12, 'december': 12, 'disember': 12,
};

/// Dates written in a letter: 12/03/2026, 12-03-2026 and 12 Mac 2026.
List<DateTime> datesIn(String text) {
  final out = <DateTime>[];
  for (final m in RegExp(r'\b(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})\b').allMatches(text)) {
    final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) out.add(DateTime(y, mo, d));
  }
  for (final m in RegExp(r'\b(\d{1,2})\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})\b').allMatches(text)) {
    final mo = _months[m.group(2)!.toLowerCase()];
    if (mo != null) out.add(DateTime(int.parse(m.group(3)!), mo, int.parse(m.group(1)!)));
  }
  return out;
}

/// Cues that a letter or notice is forged: an official letterhead combined
/// with payment instructions or a personal payee, reference numbers in the
/// wrong shape, and dates that do not agree with the file itself.
List<Finding> fakeDocumentFindings(String text, Map<String, String> meta) {
  final out = <Finding>[];
  Finding f(CueCategory c, String title, String why, int w) =>
      Finding(category: c, title: title, explanation: why, weight: w, tool: 'Fake document check');
  final claims = [
    for (final e in _letterheads.entries)
      if (RegExp(e.value, caseSensitive: false).hasMatch(text)) e.key,
  ];
  final official = claims.where((c) => c != 'a bank').toList();
  final hasAccount = extractEntities(text).any((e) => e.type == EntityType.bankAccount);
  final pays = _payInstruction.hasMatch(text);

  if (official.isNotEmpty && (pays || hasAccount)) {
    out.add(f(CueCategory.impersonation, 'Official letter asks for payment',
        'This looks like a letter from ${official.first}, but it tells you to pay into a bank account. ${official.first} does not collect money this way; pay only through its official website or counter.', 22));
  }
  final payee = _payeeName.firstMatch(text);
  if (payee != null && claims.isNotEmpty && !_company.hasMatch(payee.group(2)!)) {
    out.add(f(CueCategory.payment, 'Payment to a personal account',
        'Money is to go to "${payee.group(2)!.trim()}", a personal name, not the agency or bank itself. Official bodies never collect money in a person\'s name.', 20));
  }
  if (claims.contains('court')) {
    final c = _courtCase.firstMatch(text);
    if (c != null && !_courtFormat.hasMatch(c.group(2)!.toUpperCase())) {
      out.add(f(CueCategory.impersonation, 'Case number in an unusual format',
          'Malaysian court case numbers look like "WA-22NCvC-123-01/2026". This one does not follow that pattern.', 6));
    }
  }
  if (claims.contains('LHDN')) {
    final t = _taxRef.firstMatch(text);
    if (t != null && !_taxFormat.hasMatch(t.group(4)!.trim())) {
      out.add(f(CueCategory.impersonation, 'Tax number in an unusual format',
          'LHDN tax numbers start with letters such as IG, SG or OG followed by digits. This one does not.', 6));
    }
  }

  final created = DateTime.tryParse(meta['Created'] ?? '');
  final modified = DateTime.tryParse(meta['Modified'] ?? '');
  if (created != null && modified != null && modified.isBefore(created.subtract(const Duration(days: 1)))) {
    out.add(f(CueCategory.file, 'File dates do not add up', 'The file says it was changed before it was created, which happens when a document is edited to look older.', 4));
  }
  final letterDates = datesIn(text);
  if (created != null && letterDates.isNotEmpty && claims.isNotEmpty) {
    final earliest = letterDates.reduce((a, b) => a.isBefore(b) ? a : b);
    if (created.difference(earliest).inDays > 60) {
      out.add(f(CueCategory.impersonation, 'Letter date does not match the file',
          'The letter is dated ${_d(earliest)} but the file was only made on ${_d(created)}. Forged letters are often backdated.', 6));
    }
  }
  final tool = '${meta['Made with'] ?? ''} ${meta['Producer'] ?? ''}'.toLowerCase();
  if (claims.isNotEmpty && RegExp(r'canva|photoshop|ilovepdf|smallpdf|pdfescape|sejda|picsart|wps').hasMatch(tool)) {
    out.add(f(CueCategory.file, 'Made with an editing app',
        'This "official" letter was made with ${RegExp(r'canva|photoshop|ilovepdf|smallpdf|pdfescape|sejda|picsart|wps').firstMatch(tool)!.group(0)}, an app often used to fake letterheads. On its own this is a small sign.', 4));
  }
  return out;
}

String _d(DateTime d) => '${d.day}/${d.month}/${d.year}';
