import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/account.dart';
import '../../auth/auth_service.dart';
import '../kit.dart';
import '../theme.dart';
import 'privacy_notice.dart';

enum _Page { login, register, code, forgot }

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
    showDialog<void>(context: context, builder: (ctx) => _ExpiredDialog(onDone: widget.onDone));
    auth.expired = false;
  }

  void _go(_Page p) => setState(() => _page = p);

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _page == _Page.login,
        onPopInvokedWithResult: (did, _) {
          if (!did) _go(_page == _Page.code ? _Page.register : _Page.login);
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
                    onRegister: () => _go(_Page.register),
                    onForgot: () => _go(_Page.forgot),
                  ),
                _Page.register => _Register(
                    key: const ValueKey('register'),
                    initial: _pending,
                    onDone: widget.onDone,
                    onBack: () => _go(_Page.login),
                    onCodeSent: (r) => setState(() {
                      _pending = r;
                      _page = _Page.code;
                    }),
                  ),
                _Page.code => _Code(
                    key: const ValueKey('code'),
                    reg: _pending!,
                    onBack: () => _go(_Page.register),
                    onDone: widget.onDone,
                  ),
                _Page.forgot => _Forgot(key: const ValueKey('forgot'), onBack: () => _go(_Page.login), onDone: widget.onDone),
              },
            ),
          ),
        ),
      );
}

// ------------------------------------------------------------ shared parts

/// Top bar of the sign-in screens: back arrow and the screen name.
class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  const _TopBar(this.title, {this.onBack});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Row(children: [
          if (onBack != null) IconButton(onPressed: onBack, tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded)) else const SizedBox(width: 16),
          const Icon(Icons.verified_user_outlined, color: K.primary, size: 20),
          const SizedBox(width: 6),
          Text('KANTOI', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: K.onSurfaceVariant, letterSpacing: 1.2)),
          Expanded(child: Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(width: 92),
        ]),
      );
}

class _Hero extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool round;
  const _Hero({required this.icon, required this.title, required this.subtitle, this.round = false});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      const SizedBox(height: 12),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.7, end: 1),
        duration: K.medium,
        curve: Curves.easeOutBack,
        builder: (_, s, c) => Transform.scale(scale: s, child: c),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: K.primaryContainer,
            borderRadius: round ? null : K.r16,
            shape: round ? BoxShape.circle : BoxShape.rectangle,
            boxShadow: K.shadow,
          ),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
      const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: t.headlineMedium),
      const SizedBox(height: 4),
      Text(subtitle, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: K.secondary)),
      const SizedBox(height: 24),
    ]);
  }
}

/// Label above a tinted input box, with an optional state icon on the right.
class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final String? error;
  final bool obscure;
  final Widget? trailing;
  final TextInputType? keyboard;
  final List<String>? autofill;
  final String? prefix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization caps;
  const _Field({
    required this.label,
    required this.controller,
    required this.icon,
    this.hint,
    this.error,
    this.obscure = false,
    this.trailing,
    this.keyboard,
    this.autofill,
    this.prefix,
    this.onChanged,
    this.onSubmitted,
    this.caps = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FieldLabel(label,
            trailing: error != null ? Text('Check this', style: t.labelSmall?.copyWith(color: K.error)) : null),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          autofillHints: autofill,
          textCapitalization: caps,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            fillColor: error != null ? K.errorContainer.withValues(alpha: 0.35) : null,
            prefixIcon: Icon(icon, color: error != null ? K.error : K.secondary, size: 20),
            prefix: prefix == null
                ? null
                : Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: K.surfaceMid, borderRadius: BorderRadius.circular(6)),
                    child: Text(prefix!, style: t.labelMedium),
                  ),
            suffixIcon: error != null ? const Icon(Icons.error_rounded, color: K.error, size: 20) : trailing,
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: K.error),
              const SizedBox(width: 6),
              Expanded(child: Text(error!, style: t.bodySmall?.copyWith(color: K.error))),
            ]),
          ),
      ]),
    );
  }
}

const _ok = Padding(padding: EdgeInsets.all(12), child: Icon(Icons.check_circle_rounded, color: K.primaryContainer, size: 20));

Widget _busyOr(bool busy, String label, {bool arrow = true}) => busy
    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
    : Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label),
        if (arrow) ...[const SizedBox(width: 8), const Icon(Icons.arrow_forward_rounded, size: 18)],
      ]);

/// PDPA consent for Google sign-in: the box starts unticked, as on the
/// register form.
class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog();
  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  bool _agreed = false;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      icon: const TintIcon(Icons.privacy_tip_outlined, background: K.surfaceMid, size: 48),
      title: const Text('Before you continue'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Kantoi uses your Google name and email for your account. Checks run on your phone, and only masked scam details are shared.',
            style: t.bodyMedium?.copyWith(color: K.onSurfaceVariant)),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => setState(() => _agreed = !_agreed),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(value: _agreed, onChanged: (v) => setState(() => _agreed = v ?? false)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text.rich(TextSpan(style: t.bodyMedium, children: [
                  const TextSpan(text: "I agree to Kantoi's "),
                  TextSpan(
                    text: 'Privacy Notice and Terms',
                    style: const TextStyle(color: K.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyNoticePage())),
                  ),
                  const TextSpan(text: ' (PDPA 2010).'),
                ])),
              ),
            ),
          ]),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _agreed ? () => Navigator.pop(context, true) : null, child: const Text('Continue')),
      ],
    );
  }
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
    // Google accounts skip the register form, so they get the same unticked
    // PDPA consent here before the first sign-in on this phone.
    if (!await _consented()) return;
    if (!mounted) return;
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

  static const _kConsent = 'auth.googleConsent';

  Future<bool> _consented() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getString(_kConsent) == consentVersion) return true;
    } catch (_) {}
    if (!mounted) return false;
    final ok = await showDialog<bool>(context: context, builder: (_) => const _ConsentDialog()) ?? false;
    if (ok) {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(_kConsent, consentVersion);
      } catch (_) {}
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(borderRadius: K.r12, boxShadow: K.shadow),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), backgroundColor: Colors.white, side: BorderSide.none, foregroundColor: K.onSurface),
          onPressed: _busy ? null : _go,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const _GoogleG(),
            const SizedBox(width: 12),
            const Text('Continue with Google'),
          ]),
        ),
      );
}

/// The four-colour Google "G", drawn so no image asset is needed.
class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => const SweepGradient(
          colors: [Color(0xFFEA4335), Color(0xFFFBBC05), Color(0xFF34A853), Color(0xFF4285F4), Color(0xFFEA4335)],
          stops: [0.0, 0.3, 0.55, 0.8, 1.0],
          startAngle: 3.6,
          endAngle: 3.6 + 6.283,
        ).createShader(r),
        child: const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21, color: Colors.white, height: 1)),
      );
}

Widget _or(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(children: [
        const Expanded(child: Divider(color: K.surfaceHigh)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('OR', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: K.secondary, letterSpacing: 1))),
        const Expanded(child: Divider(color: K.surfaceHigh)),
      ]),
    );

class _ExpiredDialog extends StatelessWidget {
  final VoidCallback onDone;
  const _ExpiredDialog({required this.onDone});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: K.shadow),
                child: const Icon(Icons.lock_clock_outlined, color: K.primaryContainer, size: 30),
              ),
              Positioned(
                right: 2,
                bottom: 4,
                child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: K.onTertiaryContainer, shape: BoxShape.circle)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Text('Please log in again', textAlign: TextAlign.center, style: t.headlineSmall),
          const SizedBox(height: 8),
          Text("You haven't opened Kantoi for 7 days, so we logged you out to keep your account safe. Phone protection is still on.",
              textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: K.secondary)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: K.green.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(99)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.verified_outlined, color: K.green, size: 18),
              const SizedBox(width: 8),
              Flexible(child: Text('Phone protection keeps running', style: t.labelLarge?.copyWith(color: K.green))),
            ]),
          ),
          const SizedBox(height: 16),
          _GoogleButton(onDone: () {
            Navigator.pop(context);
            onDone();
          }),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => Navigator.pop(context), child: _busyOr(false, 'Log in')),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ login

class _Login extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback onRegister;
  final VoidCallback onForgot;
  const _Login({super.key, required this.onDone, required this.onRegister, required this.onForgot});
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
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      const _TopBar('Sign in'),
      const _Hero(icon: Icons.shield_outlined, title: 'Welcome back', subtitle: 'Log in to keep Kantoi protecting you.'),
      KCard(
        padding: const EdgeInsets.all(18),
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _GoogleButton(onDone: widget.onDone),
            _or(context),
            _Field(
              label: 'Username or email',
              controller: _id,
              icon: Icons.person_outline_rounded,
              hint: 'e.g. ahmad_razak or name@example.com',
              keyboard: TextInputType.emailAddress,
              autofill: const [AutofillHints.username],
            ),
            _Field(
              label: 'Password',
              controller: _pw,
              icon: Icons.lock_outline_rounded,
              hint: 'Enter your password',
              obscure: _hide,
              autofill: const [AutofillHints.password],
              onSubmitted: (_) => _login(),
              trailing: IconButton(
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: K.secondary),
                  onPressed: () => setState(() => _hide = !_hide)),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: widget.onForgot, child: const Text('Forgot password?'))),
            if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_err!, style: t.bodySmall?.copyWith(color: K.error))),
            const SizedBox(height: 4),
            FilledButton(onPressed: _busy ? null : _login, child: _busyOr(_busy, 'Log in')),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('New to Kantoi?', style: t.bodyMedium?.copyWith(color: K.secondary)),
        TextButton(onPressed: widget.onRegister, child: const Text('Create an account', style: TextStyle(fontSize: 16))),
      ]),
      const SizedBox(height: 8),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: K.surfaceLow, borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline_rounded, size: 16, color: K.secondary),
            const SizedBox(width: 8),
            Flexible(child: Text('Phone protection keeps running even when you are logged out.', style: t.labelMedium?.copyWith(color: K.secondary))),
          ]),
        ),
      ),
    ]);
  }
}

// --------------------------------------------------------------- register

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

  void _clear(String key) {
    if (_err.containsKey(key)) setState(() => _err = Map.of(_err)..remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final strength = _pw.text.isEmpty ? -1 : passwordStrength(_pw.text);
    final sc = [K.error, K.onTertiaryContainer, K.primaryContainer, K.primaryContainer];
    const sl = ['Weak', 'Okay', 'Strong password', 'Very strong'];
    final userOk = RegExp(r'^[a-zA-Z0-9_.]{3,}$').hasMatch(_user.text.trim());
    final match = _pw2.text.isNotEmpty && _pw2.text == _pw.text;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      _TopBar('Register', onBack: widget.onBack),
      const _Hero(icon: Icons.verified_user_rounded, title: 'Create your account', subtitle: 'One account keeps your reports and history safe.'),
      _GoogleButton(onDone: widget.onDone),
      _or(context),
      KCard(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Field(
              label: 'Full name',
              controller: _name,
              icon: Icons.person_outline_rounded,
              hint: 'e.g. Ahmad Razak',
              caps: TextCapitalization.words,
              error: _err['fullName'],
              onChanged: (_) => _clear('fullName')),
          _Field(
              label: 'Email address',
              controller: _email,
              icon: Icons.mail_outline_rounded,
              hint: 'name@example.com',
              keyboard: TextInputType.emailAddress,
              error: _err['email'],
              onChanged: (_) => _clear('email')),
          if (_err['email']?.contains('Log in') == true)
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: widget.onBack, child: const Text('Log in instead'))),
          _Field(
              label: 'Phone number (optional)',
              controller: _phone,
              icon: Icons.call_outlined,
              hint: '12 345 6789',
              prefix: '+60',
              keyboard: TextInputType.phone,
              error: _err['phone'],
              onChanged: (_) => _clear('phone')),
          _Field(
              label: 'Username',
              controller: _user,
              icon: Icons.alternate_email_rounded,
              hint: 'ahmad_razak',
              error: _err['username'],
              trailing: userOk ? _ok : null,
              onChanged: (_) {
                _clear('username');
                setState(() {});
              }),
          _Field(
            label: 'Password',
            controller: _pw,
            icon: Icons.lock_outline_rounded,
            hint: 'At least 8 characters',
            obscure: _hide,
            error: _err['password'],
            onChanged: (_) {
              _clear('password');
              setState(() {});
            },
            trailing: IconButton(
                icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: K.secondary),
                onPressed: () => setState(() => _hide = !_hide)),
          ),
          Transform.translate(
            offset: const Offset(0, -6),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(children: [
                Row(children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: K.fast,
                        height: 5,
                        margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                        decoration: BoxDecoration(
                            color: strength >= 0 && i <= strength.clamp(0, 2) ? sc[strength] : K.surfaceMid, borderRadius: BorderRadius.circular(99)),
                      ),
                    ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Text(strength < 0 ? 'Password strength' : sl[strength],
                      style: t.labelSmall?.copyWith(color: strength < 0 ? K.secondary : sc[strength])),
                  const Spacer(),
                  Text(strength < 0 ? 'None' : 'Min. 8 chars', style: t.labelSmall?.copyWith(color: K.secondary)),
                ]),
              ]),
            ),
          ),
          _Field(
            label: 'Confirm password',
            controller: _pw2,
            icon: Icons.lock_reset_rounded,
            hint: 'Re-enter your password',
            obscure: _hide,
            error: _err['pw2'],
            trailing: match ? _ok : null,
            onChanged: (_) {
              _clear('pw2');
              setState(() {});
            },
          ),
        ]),
      ),
      const SizedBox(height: 14),
      InkWell(
        borderRadius: K.r12,
        onTap: () => setState(() => _agreed = !_agreed),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(value: _agreed, onChanged: (v) => setState(() => _agreed = v ?? false)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, right: 4),
              child: Text.rich(TextSpan(style: t.bodySmall?.copyWith(color: K.secondary, height: 1.45), children: [
                const TextSpan(text: "I agree to Kantoi's "),
                TextSpan(
                  text: 'Privacy Notice and Terms',
                  style: const TextStyle(color: K.primaryContainer, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
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
      if (_err['agreed'] != null) Text(_err['agreed']!, style: t.bodySmall?.copyWith(color: K.error)),
      if (_err['form'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err['form']!, style: t.bodySmall?.copyWith(color: K.error))),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy || !_agreed ? null : _send,
        child: _busyOr(_busy, auth.emailCodes ? 'Send verification code' : 'Create account'),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('Already have an account?', style: t.bodyMedium?.copyWith(color: K.secondary)),
        TextButton(onPressed: widget.onBack, child: const Text('Log in')),
      ]),
    ]);
  }
}

// ------------------------------------------------------------- the code

/// Six boxes filled from an on-screen keypad; long-press pastes a code.
class _CodeBoxes extends StatelessWidget {
  final String digits;
  final bool error;
  final VoidCallback onPaste;
  const _CodeBoxes({required this.digits, required this.error, required this.onPaste});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GestureDetector(
      onLongPress: onPaste,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var i = 0; i < 6; i++)
          AnimatedContainer(
            duration: K.fast,
            width: 48,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: K.r12,
              boxShadow: K.shadow,
              border: error ? Border.all(color: K.error) : (i == digits.length ? Border.all(color: K.primaryContainer, width: 1.5) : null),
            ),
            child: i < digits.length
                ? Text(digits[i], style: t.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))
                : i == digits.length
                    ? const _Caret()
                    : Container(width: 8, height: 8, decoration: const BoxDecoration(color: K.surfaceHighest, shape: BoxShape.circle)),
          ),
      ]),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret();
  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _c, child: Container(width: 2, height: 24, color: K.primaryContainer));
}

class _Keypad extends StatelessWidget {
  final ValueChanged<String> onKey;
  final VoidCallback onDelete;
  const _Keypad({required this.onKey, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Material(
              color: onTap == null ? Colors.transparent : Colors.white,
              borderRadius: K.r12,
              child: InkWell(
                borderRadius: K.r12,
                onTap: onTap == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onTap();
                      },
                child: SizedBox(height: 50, child: Center(child: child)),
              ),
            ),
          ),
        );
    const style = TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: K.onSurface);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(color: K.surfaceLow, borderRadius: K.r16),
      child: Column(children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final d in row) key(Text(d, style: style), () => onKey(d))]),
        Row(children: [
          key(const SizedBox.shrink(), null),
          key(const Text('0', style: style), () => onKey('0')),
          key(const Icon(Icons.backspace_outlined, color: K.secondary), onDelete),
        ]),
      ]),
    );
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
  String _digits = '';
  int _wait = 60;
  Timer? _timer;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _tick();
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
    super.dispose();
  }

  void _key(String d) {
    if (_busy || _digits.length >= 6) return;
    setState(() {
      _digits += d;
      _err = null;
    });
    if (_digits.length == 6) _verify();
  }

  Future<void> _paste() async {
    final c = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (c.length < 6) return;
    setState(() => _digits = c.substring(0, 6));
    _verify();
  }

  Future<void> _verify() async {
    if (_digits.length != 6) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final e = await auth.finishRegistration(widget.reg, _digits);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = e;
    });
    if (e == null) {
      showKToast(context, title: 'Account created', body: 'Welcome to Kantoi, ${widget.reg.fullName.split(' ').first}.', icon: Icons.verified_rounded, color: K.green);
      widget.onDone();
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _digits = '');
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      _TopBar('Verify email', onBack: widget.onBack),
      _Hero(
        icon: Icons.mail_outline_rounded,
        round: true,
        title: 'Enter the 6-digit code',
        subtitle: 'We sent a code to ${maskEmail(widget.reg.email)}. It expires in 10 minutes.',
      ),
      _CodeBoxes(digits: _digits, error: _err != null, onPaste: _paste),
      if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: K.error))),
      const SizedBox(height: 14),
      Center(
        child: _wait > 0
            ? Text.rich(TextSpan(style: t.bodyMedium?.copyWith(color: K.secondary), children: [
                const TextSpan(text: "Didn't get it?  Resend in "),
                TextSpan(text: '0:${_wait.toString().padLeft(2, '0')}', style: const TextStyle(color: K.onSurface, fontWeight: FontWeight.w600)),
              ]))
            : TextButton(onPressed: _resend, child: const Text('Resend code')),
      ),
      const SizedBox(height: 16),
      KCard(
        color: K.surfaceLow,
        child: Row(children: [
          TintIcon(Icons.shield_outlined, color: K.onTertiaryContainer, size: 32),
          const SizedBox(width: 12),
          Expanded(child: Text('Check your spam folder. Kantoi will never ask you for this code by phone or chat.', style: t.bodyMedium?.copyWith(color: K.secondary))),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: _busy || _digits.length != 6 ? null : _verify, child: _busyOr(_busy, 'Verify', arrow: false)),
      const SizedBox(height: 16),
      _Keypad(
        onKey: _key,
        onDelete: () {
          if (_digits.isNotEmpty) setState(() => _digits = _digits.substring(0, _digits.length - 1));
        },
      ),
    ]);
  }
}

/// j***n@gmail.com
String maskEmail(String email) {
  final e = email.trim();
  final at = e.indexOf('@');
  if (at < 2) return e;
  return '${e.substring(0, 1)}***${e.substring(at - 1)}';
}

// ----------------------------------------------------------------- forgot

class _Forgot extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onDone;
  const _Forgot({super.key, required this.onBack, required this.onDone});
  @override
  State<_Forgot> createState() => _ForgotState();
}

class _ForgotState extends State<_Forgot> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _pw = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  bool _hide = true;
  String? _err;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() f, VoidCallback onOk) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    final e = await f();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = e;
    });
    if (e == null) onOk();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      _TopBar('Reset password', onBack: widget.onBack),
      _Hero(
        icon: Icons.key_rounded,
        title: _sent ? 'Choose a new password' : 'Forgot your password?',
        subtitle: _sent ? 'Enter the code we sent to ${maskEmail(_email.text)}.' : "We'll email you a 6-digit code to set a new one.",
      ),
      KCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Field(label: 'Email address', controller: _email, icon: Icons.mail_outline_rounded, hint: 'name@example.com', keyboard: TextInputType.emailAddress),
          if (_sent) ...[
            _Field(label: '6-digit code', controller: _code, icon: Icons.pin_outlined, hint: '123456', keyboard: TextInputType.number),
            _Field(
              label: 'New password',
              controller: _pw,
              icon: Icons.lock_outline_rounded,
              hint: 'At least 8 characters',
              obscure: _hide,
              trailing: IconButton(
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: K.secondary),
                  onPressed: () => setState(() => _hide = !_hide)),
            ),
          ],
          if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_err!, style: t.bodySmall?.copyWith(color: K.error))),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _sent
                    ? _run(() => auth.finishReset(_email.text, _code.text, _pw.text), () {
                        showKToast(context, title: 'Password changed', icon: Icons.verified_rounded, color: K.green);
                        widget.onDone();
                      })
                    : _run(() => auth.startReset(_email.text), () => setState(() => _sent = true)),
            child: _busyOr(_busy, _sent ? 'Reset and log in' : 'Send code'),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Text('Signed up with Google? You have no Kantoi password. Use "Continue with Google" instead.',
          textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: K.secondary)),
    ]);
  }
}
