/// The security certificate a website presents.
class TlsInfo {
  final String issuer;
  final String subject;
  final DateTime validFrom;
  final DateTime validTo;
  /// False when the device would not trust it (expired, wrong name, self-made).
  final bool trusted;
  const TlsInfo({required this.issuer, required this.subject, required this.validFrom, required this.validTo, required this.trusted});

  /// The organisation part of the issuer, e.g. "Let's Encrypt".
  String get issuerName {
    final o = RegExp(r'O=([^,/]+)').firstMatch(issuer)?.group(1);
    final cn = RegExp(r'CN=([^,/]+)').firstMatch(issuer)?.group(1);
    return (o ?? cn ?? issuer).trim();
  }

  /// Free, automatic certificate authorities. Fine for most sites, unusual
  /// for a bank.
  bool get freeIssuer => RegExp(r"let'?s ?encrypt|zerossl|cpanel|buypass|\bR1[0-4]\b|\bE[5-9]\b|\bR3\b", caseSensitive: false).hasMatch(issuer);
}
