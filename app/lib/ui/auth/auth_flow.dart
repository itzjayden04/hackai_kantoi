import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/account.dart';
import '../../auth/auth_service.dart';
import '../kit.dart';
import '../theme.dart';
import 'privacy_notice.dart';

enum _Page { login, register, code }

/// Log in or create an account. Every user signs in once; Kantoi logs out
/// after 7 days without opening the app. [onDone] continues into the app.
class AuthFlow extends StatefulWidget {
  final VoidCallback onDone;
  const AuthFlow({super.key, required this.onDone});
  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  _Page _page = _Page.login;
  Registration? _pending;

  @override
  void initState() {
    super.initState();
    if (auth.expired) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _expiredDialog());
    }
  }

  void _expiredDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_clock_outlined, color: K.primary, size: 36),
        title: const Text('Please log in again'),
        content: const Text(
            "You haven't opened Kantoi for 7 days, so we logged you out to keep your account safe. Phone protection is still on."),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    auth.expired = false;
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _page == _Page.login,
        onPopInvokedWithResult: (did, _) {
          if (!did) setState(() => _page = _page == _Page.code ? _Page.register : _Page.login);
        },
        child: Scaffold(
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: K.medium,
              switchInCurve: K.curve,
              transitionBuilder: (w, a) => FadeTransition(
                  opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a), child: w)),
              child: switch (_page) {
                _Page.login => _Login(
                    key: const ValueKey('login'),
                    onDone: widget.onDone,
                    onRegister: () => setState(() => _page = _Page.register),
                  ),
                _Page.register => _Register(
                    key: const ValueKey('register'),
                    initial: _pending,
                    onDone: widget.onDone,
                    onBack: () => setState(() => _page = _Page.login),
                    onCodeSent: (r) => setState(() {
                      _pending = r;
                      _page = _Page.code;
                    }),
                  ),
                _Page.code => _Code(
                    key: const ValueKey('code'),
                    reg: _pending!,
                    onBack: () => setState(() => _page = _Page.register),
                    onDone: widget.onDone,
                  ),
              },
            ),
          ),
        ),
      );
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(color: K.primaryContainer, borderRadius: K.r16),
        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 32),
      );
}

class _GoogleButton extends StatefulWidget {
  final VoidCallback onDone;
  const _GoogleButton({required this.onDone});
  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    final err = await auth.signInGoogle();
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      widget.onDone();
    } else if (err != 'Sign-in cancelled.') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), backgroundColor: Colors.white),
        onPressed: _busy ? null : _go,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF4285F4))),
          const SizedBox(width: 12),
          const Text('Continue with Google'),
        ]),
      );
}

Widget _or(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(children: [
        const Expanded(child: Divider()),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: Theme.of(context).textTheme.bodySmall)),
        const Expanded(child: Divider()),
      ]),
    );

class _Login extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback onRegister;
  const _Login({super.key, required this.onDone, required this.onRegister});
  @override
  State<_Login> createState() => _LoginState();
}

class _LoginState extends State<_Login> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    final e = await auth.signInPassword(_id.text, _pw.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = e;
    });
    if (e == null) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), children: [
      const Align(alignment: Alignment.centerLeft, child: _Logo()),
      const SizedBox(height: 20),
      Text('Welcome to Kantoi', style: t.headlineMedium),
      const SizedBox(height: 4),
      Text('Log in to keep Kantoi protecting you.', style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
      const SizedBox(height: 24),
      _GoogleButton(onDone: widget.onDone),
      _or(context),
      TextField(
        controller: _id,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.username],
        decoration: const InputDecoration(labelText: 'Username or email', prefixIcon: Icon(Icons.person_outline_rounded)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pw,
        obscureText: _hide,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) => _login(),
        decoration: InputDecoration(
          labelText: 'Password',
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)),
        ),
      ),
      if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: t.bodySmall?.copyWith(color: K.red))),
      const SizedBox(height: 20),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
        onPressed: _busy ? null : _login,
        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Log in'),
      ),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('New to Kantoi?', style: t.bodyMedium),
        TextButton(onPressed: widget.onRegister, child: const Text('Create an account')),
      ]),
      const SizedBox(height: 24),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.lock_outline_rounded, size: 14, color: K.outline),
        const SizedBox(width: 6),
        Flexible(child: Text('Phone protection keeps running even when you are logged out.', style: t.labelSmall?.copyWith(color: K.outline))),
      ]),
    ]);
  }
}

class _Register extends StatefulWidget {
  final Registration? initial;
  final VoidCallback onDone;
  final VoidCallback onBack;
  final ValueChanged<Registration> onCodeSent;
  const _Register({super.key, this.initial, required this.onDone, required this.onBack, required this.onCodeSent});
  @override
  State<_Register> createState() => _RegisterState();
}

class _RegisterState extends State<_Register> {
  late final _name = TextEditingController(text: widget.initial?.fullName);
  late final _email = TextEditingController(text: widget.initial?.email);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _user = TextEditingController(text: widget.initial?.username);
  late final _pw = TextEditingController(text: widget.initial?.password);
  late final _pw2 = TextEditingController(text: widget.initial?.password);
  late bool _agreed = widget.initial?.agreed ?? false;
  bool _hide = true;
  bool _busy = false;
  Map<String, String> _err = const {};

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _user, _pw, _pw2]) {
      c.dispose();
    }
    super.dispose();
  }

  Registration get _reg => Registration(
      fullName: _name.text, email: _email.text, phone: _phone.text, username: _user.text, password: _pw.text, agreed: _agreed);

  Future<void> _send() async {
    if (_pw.text != _pw2.text) {
      setState(() => _err = {'pw2': "The passwords don't match."});
      return;
    }
    setState(() {
      _busy = true;
      _err = const {};
    });
    final r = _reg;
    final direct = !auth.emailCodes;
    final p = direct ? await auth.registerWithoutCode(r) : await auth.startRegistration(r);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = p;
    });
    if (p.isEmpty) direct ? widget.onDone() : widget.onCodeSent(r);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final strength = passwordStrength(_pw.text);
    const sc = [K.red, K.amber, K.green, K.green];
    const sl = ['Weak', 'Okay', 'Strong', 'Very strong'];
    InputDecoration dec(String label, IconData icon, String key, {Widget? suffix, String? prefix}) =>
        InputDecoration(labelText: label, prefixIcon: Icon(icon), errorText: _err[key], suffixIcon: suffix, prefixText: prefix);
    return ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
      Align(alignment: Alignment.centerLeft, child: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back_rounded))),
      Text('Create your account', style: t.headlineMedium),
      const SizedBox(height: 4),
      Text('One account keeps your reports and history safe.', style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
      const SizedBox(height: 20),
      _GoogleButton(onDone: widget.onDone),
      _or(context),
      TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: dec('Full name', Icons.badge_outlined, 'fullName')),
      const SizedBox(height: 12),
      TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: dec('Email address', Icons.mail_outline_rounded, 'email')),
      const SizedBox(height: 12),
      TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: dec('Phone number (optional)', Icons.phone_outlined, 'phone')),
      const SizedBox(height: 12),
      TextField(controller: _user, decoration: dec('Username', Icons.alternate_email_rounded, 'username')),
      const SizedBox(height: 12),
      TextField(
        controller: _pw,
        obscureText: _hide,
        onChanged: (_) => setState(() {}),
        decoration: dec('Password', Icons.lock_outline_rounded, 'password',
            suffix: IconButton(icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide))),
      ),
      if (_pw.text.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: AnimatedContainer(
                  duration: K.fast,
                  height: 4,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(color: i < (strength + 1).clamp(1, 3) ? sc[strength] : K.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            const SizedBox(width: 8),
            Text(sl[strength], style: t.labelSmall?.copyWith(color: sc[strength])),
          ]),
        ),
      const SizedBox(height: 12),
      TextField(controller: _pw2, obscureText: _hide, decoration: dec('Confirm password', Icons.lock_outline_rounded, 'pw2')),
      const SizedBox(height: 16),
      InkWell(
        onTap: () => setState(() => _agreed = !_agreed),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(value: _agreed, onChanged: (v) => setState(() => _agreed = v ?? false)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text.rich(TextSpan(style: t.bodySmall?.copyWith(color: K.onSurface), children: [
                const TextSpan(text: "I agree to Kantoi's "),
                TextSpan(
                  text: 'Privacy Notice and Terms',
                  style: const TextStyle(color: K.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyNoticePage())),
                ),
                const TextSpan(
                    text: '. Kantoi stores my account details and shares only masked scam details (no message text, no contact names) to help protect others.'),
              ])),
            ),
          ),
        ]),
      ),
      if (_err['agreed'] != null) Text(_err['agreed']!, style: t.bodySmall?.copyWith(color: K.red)),
      if (_err['form'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err['form']!, style: t.bodySmall?.copyWith(color: K.red))),
      const SizedBox(height: 16),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
        onPressed: _busy || !_agreed ? null : _send,
        child: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(auth.emailCodes ? 'Send verification code' : 'Create account'),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('Already have an account?', style: t.bodyMedium),
        TextButton(onPressed: widget.onBack, child: const Text('Log in')),
      ]),
    ]);
  }
}

class _Code extends StatefulWidget {
  final Registration reg;
  final VoidCallback onBack;
  final VoidCallback onDone;
  const _Code({super.key, required this.reg, required this.onBack, required this.onDone});
  @override
  State<_Code> createState() => _CodeState();
}

class _CodeState extends State<_Code> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  int _wait = 60;
  Timer? _timer;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _tick();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _tick() {
    _timer?.cancel();
    _wait = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final e = await auth.finishRegistration(widget.reg, _code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = e;
    });
    if (e == null) {
      showKToast(context, title: 'Account created', body: 'Welcome to Kantoi, ${widget.reg.fullName.split(' ').first}.', icon: Icons.verified_rounded, color: K.green);
      widget.onDone();
    } else {
      _code.clear();
    }
  }

  Future<void> _resend() async {
    final p = await auth.startRegistration(widget.reg);
    if (!mounted) return;
    if (p.isEmpty) {
      _tick();
      showKToast(context, title: 'New code sent');
    } else {
      setState(() => _err = p.values.first);
    }
  }

  String get _masked {
    final e = widget.reg.email.trim();
    final at = e.indexOf('@');
    if (at < 2) return e;
    return '${e.substring(0, 1)}***${e.substring(at - 1)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final digits = _code.text;
    return ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
      Align(alignment: Alignment.centerLeft, child: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back_rounded))),
      const SizedBox(height: 8),
      Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: K.primaryContainer, shape: BoxShape.circle),
        child: const Icon(Icons.mark_email_unread_outlined, color: Colors.white, size: 32),
      ),
      const SizedBox(height: 16),
      Text('Enter the 6-digit code', style: t.headlineMedium),
      const SizedBox(height: 4),
      Text('We sent a code to $_masked. It expires in 10 minutes.', style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
      const SizedBox(height: 24),
      // Six boxes over one hidden field, so paste and autofill work.
      Stack(children: [
        Opacity(
          opacity: 0,
          child: TextField(
            controller: _code,
            focusNode: _focus,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) {
              setState(() {});
              if (v.length == 6) _verify();
            },
          ),
        ),
        GestureDetector(
          onTap: () => _focus.requestFocus(),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var i = 0; i < 6; i++)
              AnimatedContainer(
                duration: K.fast,
                width: 46,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: K.r8,
                  border: Border.all(
                      color: _err != null ? K.red : (i == digits.length ? K.primaryContainer : K.outlineVariant), width: i == digits.length ? 1.5 : 1),
                ),
                child: Text(i < digits.length ? digits[i] : '',
                    style: t.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
          ]),
        ),
      ]),
      if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: t.bodySmall?.copyWith(color: K.red))),
      const SizedBox(height: 16),
      Center(
        child: _wait > 0
            ? Text("Didn't get it? Resend in 0:${_wait.toString().padLeft(2, '0')}", style: t.bodySmall)
            : TextButton(onPressed: _resend, child: const Text('Resend code')),
      ),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.shield_outlined, size: 16, color: K.amber),
        const SizedBox(width: 6),
        Expanded(child: Text('Check your spam folder. Kantoi will never ask you for this code by phone or chat.', style: t.bodySmall)),
      ]),
      const SizedBox(height: 24),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
        onPressed: _busy || digits.length != 6 ? null : _verify,
        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Verify'),
      ),
    ]);
  }
}
