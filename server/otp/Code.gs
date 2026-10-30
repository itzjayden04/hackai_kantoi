/**
 * Kantoi email code service (Google Apps Script).
 *
 * Sends a 6-digit sign-up code from the Kantoi sender Gmail account and
 * checks it. Free: runs as the account that deploys it, so no password or
 * App Password is ever stored anywhere. See README.md in this folder.
 *
 * Script properties (Project settings > Script properties):
 *   APP_KEY     - a random string; the app sends it with every request.
 *   PROOF_KEY   - a random string; signs the "email verified" proof.
 */

var CODE_MINUTES = 10;
var MAX_TRIES = 5;

function doPost(e) {
  var req;
  try {
    req = JSON.parse(e.postData.contents);
  } catch (err) {
    return reply_({ ok: false, error: 'bad_request' });
  }
  var props = PropertiesService.getScriptProperties();
  if (!req || req.appKey !== props.getProperty('APP_KEY')) return reply_({ ok: false, error: 'forbidden' });
  var email = String(req.email || '').trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 254) return reply_({ ok: false, error: 'bad_email' });

  if (req.action === 'send') return reply_(send_(email));
  if (req.action === 'verify') return reply_(verify_(email, String(req.code || ''), props));
  return reply_({ ok: false, error: 'bad_action' });
}

function send_(email) {
  var cache = CacheService.getScriptCache();
  var key = 'otp:' + hash_(email);
  // One code a minute and five an hour per address.
  if (cache.get(key + ':recent')) return { ok: false, error: 'wait', retryAfter: 60 };
  var hourly = Number(cache.get(key + ':hour') || 0);
  if (hourly >= 5) return { ok: false, error: 'too_many', retryAfter: 3600 };
  if (MailApp.getRemainingDailyQuota() < 1) return { ok: false, error: 'quota' };

  var code = code_();
  var salt = Utilities.getUuid();
  cache.put(key, JSON.stringify({ h: hash_(salt + code), s: salt, t: 0 }), CODE_MINUTES * 60);
  cache.put(key + ':recent', '1', 60);
  cache.put(key + ':hour', String(hourly + 1), 3600);

  MailApp.sendEmail({
    to: email,
    subject: 'Your Kantoi code: ' + code,
    name: 'Kantoi',
    body: 'Your Kantoi verification code is ' + code + '.\n\nIt expires in ' + CODE_MINUTES + ' minutes.\n\n' +
      'Kantoi will never ask you for this code by phone, SMS or chat. If you did not ask for it, ignore this email.',
    htmlBody: '<div style="font-family:Inter,Arial,sans-serif;max-width:420px;margin:auto;color:#0F172A">' +
      '<h2 style="color:#1E3A8A;margin:0 0 8px">Your Kantoi code</h2>' +
      '<p style="font-size:32px;letter-spacing:8px;font-weight:700;margin:16px 0">' + code + '</p>' +
      '<p>It expires in ' + CODE_MINUTES + ' minutes.</p>' +
      '<p style="color:#B45309"><b>Kantoi will never ask you for this code by phone, SMS or chat.</b></p>' +
      '<p style="color:#64748B;font-size:12px">If you did not ask for this code, you can ignore this email.</p></div>'
  });
  return { ok: true, expiresIn: CODE_MINUTES * 60 };
}

function verify_(email, code, props) {
  var cache = CacheService.getScriptCache();
  var key = 'otp:' + hash_(email);
  var raw = cache.get(key);
  if (!raw) return { ok: false, error: 'expired' };
  var rec = JSON.parse(raw);
  if (rec.t >= MAX_TRIES) {
    cache.remove(key);
    return { ok: false, error: 'too_many' };
  }
  if (!/^\d{6}$/.test(code) || hash_(rec.s + code) !== rec.h) {
    rec.t++;
    cache.put(key, JSON.stringify(rec), CODE_MINUTES * 60);
    return { ok: false, error: 'wrong', triesLeft: MAX_TRIES - rec.t };
  }
  cache.remove(key);
  var exp = Date.now() + 30 * 60 * 1000;
  var proof = Utilities.base64EncodeWebSafe(
    Utilities.computeHmacSha256Signature(email + '|' + exp, props.getProperty('PROOF_KEY')));
  return { ok: true, email: email, exp: exp, proof: proof };
}

/** Six digits from a random UUID's hash (Apps Script has no crypto RNG API). */
function code_() {
  var bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, Utilities.getUuid() + Date.now());
  var n = 0;
  for (var i = 0; i < 4; i++) n = (n * 256 + (bytes[i] & 255)) % 1000000;
  return ('000000' + n).slice(-6);
}

function hash_(s) {
  var b = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, s);
  return b.map(function (x) { return ('0' + (x & 255).toString(16)).slice(-2); }).join('');
}

function reply_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}
