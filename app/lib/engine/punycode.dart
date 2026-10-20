/// Minimal RFC 3492 Punycode decoder, used to reveal what an "xn--" web
/// address really says.
String punycodeDecode(String input) {
  const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700;
  var n = 128, i = 0, bias = 72;
  final output = <int>[];
  final basic = input.lastIndexOf('-');
  if (basic > 0) output.addAll(input.substring(0, basic).codeUnits);
  int digit(int c) {
    if (c >= 48 && c <= 57) return c - 22;
    if (c >= 65 && c <= 90) return c - 65;
    if (c >= 97 && c <= 122) return c - 97;
    throw const FormatException('bad punycode');
  }

  int adapt(int delta, int numPoints, bool first) {
    delta = first ? delta ~/ damp : delta ~/ 2;
    delta += delta ~/ numPoints;
    var k = 0;
    while (delta > ((base - tMin) * tMax) ~/ 2) {
      delta ~/= base - tMin;
      k += base;
    }
    return k + ((base - tMin + 1) * delta) ~/ (delta + skew);
  }

  var pos = basic > 0 ? basic + 1 : 0;
  while (pos < input.length) {
    final oldI = i;
    var w = 1;
    for (var k = base;; k += base) {
      if (pos >= input.length) throw const FormatException('bad punycode');
      final d = digit(input.codeUnitAt(pos++));
      i += d * w;
      final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
      if (d < t) break;
      w *= base - t;
    }
    bias = adapt(i - oldI, output.length + 1, oldI == 0);
    n += i ~/ (output.length + 1);
    i %= output.length + 1;
    output.insert(i, n);
    i++;
  }
  return String.fromCharCodes(output);
}
