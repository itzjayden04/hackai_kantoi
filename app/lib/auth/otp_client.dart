import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Talks to Kantoi's email code service (server/otp: a Google Apps Script
/// that sends from the Kantoi Gmail account). The URL and app key are set at
/// build time from the OTP_URL and OTP_APP_KEY secrets.
class OtpClient {
  static const _buildUrl = String.fromEnvironment('OTP_URL');
  static const _buildKey = String.fromEnvironment('OTP_APP_KEY');

  final String url;
  final String appKey;
  final http.Client _http;
  OtpClient({String? url, String? appKey, http.Client? client})
      : url = url ?? _buildUrl,
        appKey = appKey ?? _buildKey,
        _http = client ?? http.Client();

  bool get configured => url.isNotEmpty && appKey.isNotEmpty;

  /// Sends a code. Returns null on success, or a plain-English problem.
  Future<String?> send(String email) async {
    final r = await _post({'action': 'send', 'email': email});
    if (r['ok'] == true) return null;
    return _problem(r);
  }

  /// Checks a code. On success returns the signed proof the service gives.
  Future<OtpResult> verify(String email, String code) async {
    final r = await _post({'action': 'verify', 'email': email, 'code': code});
    if (r['ok'] == true) return OtpResult(proof: r['proof'] as String? ?? '', expires: (r['exp'] as num?)?.toInt() ?? 0);
    return OtpResult(problem: _problem(r), triesLeft: (r['triesLeft'] as num?)?.toInt());
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    if (!configured) return {'ok': false, 'error': 'not_configured'};
    try {
      // Apps Script answers a POST with a 302 to the result. Dart's http
      // client does not follow redirects for POST, so fetch it ourselves.
      var res = await _http
          .post(Uri.parse(url), headers: {'Content-Type': 'text/plain'}, body: jsonEncode({...body, 'appKey': appKey}))
          .timeout(const Duration(seconds: 20));
      for (var hops = 0; hops < 3 && (res.isRedirect || const [301, 302, 303, 307, 308].contains(res.statusCode)); hops++) {
        final to = res.headers['location'];
        if (to == null) break;
        res = await _http.get(Uri.parse(url).resolve(to)).timeout(const Duration(seconds: 20));
      }
      try {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } on FormatException {
        // A web page instead of JSON: usually the script isn't deployed for "Anyone".
        return {'ok': false, 'error': 'bad_reply', 'status': res.statusCode};
      }
    } on TimeoutException {
      return {'ok': false, 'error': 'offline'};
    } catch (_) {
      return {'ok': false, 'error': 'offline'};
    }
  }

  static String _problem(Map<String, dynamic> r) => switch (r['error']) {
        'wait' => 'A code was just sent. Please wait a minute before asking again.',
        'too_many' => 'Too many tries. Please wait an hour and try again.',
        'quota' => "Kantoi has sent too many emails today. Please try again tomorrow or use Google sign-in.",
        'bad_email' => "That email address doesn't look right.",
        'expired' => 'This code has expired. Ask for a new one.',
        'wrong' => "That code isn't right.",
        'not_configured' => 'Email codes are not set up in this build. Please use Google sign-in.',
        'offline' => "Couldn't reach Kantoi. Check your internet connection and try again.",
        'bad_reply' => "Kantoi's email service gave an unexpected answer (HTTP ${r['status']}). Please use Google sign-in for now.",
        _ => 'Something went wrong. Please try again.',
      };
}

class OtpResult {
  final String? proof;
  final int expires;
  final String? problem;
  final int? triesLeft;
  const OtpResult({this.proof, this.expires = 0, this.problem, this.triesLeft});
  bool get ok => problem == null;
}
