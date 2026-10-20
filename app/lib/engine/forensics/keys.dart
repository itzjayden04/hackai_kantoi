/// Optional API keys for the link reputation services. Each comes from a
/// build-time define and can be overridden by the user in Settings. A missing
/// key means that check is skipped (and logged as skipped).
class ForensicKeys {
  static const _safeBrowsing = String.fromEnvironment('SAFE_BROWSING_API_KEY');
  static const _virusTotal = String.fromEnvironment('VIRUSTOTAL_API_KEY');
  static const _abuseCh = String.fromEnvironment('ABUSECH_AUTH_KEY');
  static const _urlscan = String.fromEnvironment('URLSCAN_API_KEY');

  final String safeBrowsing;
  final String virusTotal;
  final String abuseCh;
  final String urlscan;

  const ForensicKeys({
    this.safeBrowsing = _safeBrowsing,
    this.virusTotal = _virusTotal,
    this.abuseCh = _abuseCh,
    this.urlscan = _urlscan,
  });

  /// Keys built into this copy of Kantoi (may all be empty).
  static const defaults = ForensicKeys();

  /// No keys at all, so every reputation lookup is skipped.
  static const none = ForensicKeys(safeBrowsing: '', virusTotal: '', abuseCh: '', urlscan: '');

  /// User-entered keys; an empty field falls back to the built-in key.
  factory ForensicKeys.withOverrides({String? safeBrowsing, String? virusTotal, String? abuseCh, String? urlscan}) {
    String pick(String? user, String built) => (user ?? '').trim().isEmpty ? built : user!.trim();
    return ForensicKeys(
      safeBrowsing: pick(safeBrowsing, _safeBrowsing),
      virusTotal: pick(virusTotal, _virusTotal),
      abuseCh: pick(abuseCh, _abuseCh),
      urlscan: pick(urlscan, _urlscan),
    );
  }

  /// Only the values the user typed (built-in keys are never written out).
  Map<String, String> userValues() => {
        'safeBrowsing': safeBrowsing == _safeBrowsing ? '' : safeBrowsing,
        'virusTotal': virusTotal == _virusTotal ? '' : virusTotal,
        'abuseCh': abuseCh == _abuseCh ? '' : abuseCh,
        'urlscan': urlscan == _urlscan ? '' : urlscan,
      };

  factory ForensicKeys.fromJson(Map<String, dynamic> j) => ForensicKeys.withOverrides(
        safeBrowsing: j['safeBrowsing'] as String?,
        virusTotal: j['virusTotal'] as String?,
        abuseCh: j['abuseCh'] as String?,
        urlscan: j['urlscan'] as String?,
      );

  /// Which services have a key built into this copy of Kantoi.
  static Map<String, bool> get builtIn => {
        'safeBrowsing': _safeBrowsing.isNotEmpty,
        'virusTotal': _virusTotal.isNotEmpty,
        'abuseCh': _abuseCh.isNotEmpty,
        'urlscan': _urlscan.isNotEmpty,
      };
}
