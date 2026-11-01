import 'package:flutter/material.dart';

import '../../account/account.dart';
import '../kit.dart';
import '../setup_page.dart' show KantoiLogo;
import '../theme.dart';

/// Shows the sign-in screen until the user signs in or chooses to go on
/// without an account. Without Firebase it shows [child] straight away.
class AuthGate extends StatelessWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([auth.user, auth.guest]),
        builder: (context, _) => AnimatedSwitcher(
          duration: K.medium,
          child: needsSignIn ? const SignInPage(key: ValueKey('signin')) : KeyedSubtree(key: const ValueKey('app'), child: child),
        ),
      );
}

/// Shared layout: logo, title, subtitle, then the form, in a scrollable
/// column that stays readable on tablets.
class _AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;
  const _AuthScaffold({required this.title, required this.subtitle, required this.children, this.showBack = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: showBack ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: EdgeInsets.fromLTRB(24, showBack ? 0 : 40, 24, 24),
              children: [
                const Reveal(index: 0, child: Align(alignment: Alignment.centerLeft, child: KantoiLogo(size: 40))),
                const SizedBox(height: 28),
                Reveal(index: 1, child: Text(title, style: t.headlineMedium)),
                const SizedBox(height: 6),
                Reveal(index: 2, child: Text(subtitle, style: t.bodyLarge?.copyWith(color: K.onSurfaceVariant))),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A red box with what went wrong, read out by screen readers.
class _ErrorBox extends StatelessWidget {
  final String? text;
  const _ErrorBox(this.text);

  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: K.fast,
        child: text == null
            ? const SizedBox(width: double.infinity)
            : Semantics(
                liveRegion: true,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(color: K.errorContainer, borderRadius: K.r8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline_rounded, color: K.onErrorContainer, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(text!, style: const TextStyle(color: K.onErrorContainer, fontWeight: FontWeight.w500))),
                  ]),
                ),
              ),
      );
}

InputDecoration _field(String label, IconData icon, {Widget? suffix, String? helper}) => InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
    );

class _PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputAction action;
  final Iterable<String> autofill;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  const _PasswordField({
    required this.controller,
    this.label = 'Password',
    this.validator,
    this.action = TextInputAction.done,
    this.autofill = const [AutofillHints.password],
    this.onSubmitted,
    this.onChanged,
  });
  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hide = true;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _hide,
        enableSuggestions: false,
        autocorrect: false,
        textInputAction: widget.action,
        autofillHints: widget.autofill,
        validator: widget.validator,
        onFieldSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        decoration: _field(widget.label, Icons.lock_outline_rounded,
            suffix: IconButton(
              tooltip: _hide ? 'Show password' : 'Hide password',
              icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _hide = !_hide),
            )),
      );
}

class _BusyButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onPressed;
  const _BusyButton({required this.label, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(label),
      );
}

/// Sign in with email and password.
class SignInPage extends StatefulWidget {
  /// Opened from Settings (has a back button, closes after signing in).
  final bool pushed;
  const SignInPage({super.key, this.pushed = false});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      final u = await auth.signIn(_email.text, _password.text);
      if (!mounted) return;
      if (widget.pushed) nav.popUntil((r) => r.isFirst);
      showKToast(context, title: 'Welcome back, ${u.greetingName}', icon: Icons.verified_user_rounded, color: K.green);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not sign in: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to share scam reports with other Kantoi users and see what they reported.',
      showBack: widget.pushed,
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _ErrorBox(_error),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                validator: (v) => emailProblem(v ?? ''),
                decoration: _field('Email', Icons.mail_outline_rounded),
              ),
              const SizedBox(height: 14),
              _PasswordField(
                controller: _password,
                validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                onSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ForgotPasswordPage(email: _email.text.trim()))),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 4),
              _BusyButton(label: 'Sign in', busy: _busy, onPressed: _submit),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegisterPage(pushed: widget.pushed))),
                child: const Text('Create an account'),
              ),
              if (!widget.pushed) ...[
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : auth.continueAsGuest,
                    child: const Text('Continue without an account'),
                  ),
                ),
                Text(
                  'Checking messages, links and numbers works without an account. '
                  'An account adds community reports.',
                  textAlign: TextAlign.center,
                  style: t.bodySmall,
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

/// Create an account. A verification email goes out straight after.
class RegisterPage extends StatefulWidget {
  final bool pushed;
  const RegisterPage({super.key, this.pushed = false});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _agree = false;
  bool _busy = false;
  String? _error;
  int _strength = 0;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!_agree) {
      setState(() => _error = 'Please agree to how Kantoi uses your reports.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      final u = await auth.register(_name.text, _email.text, _password.text);
      if (!mounted) return;
      nav.popUntil((r) => r.isFirst);
      showKToast(context,
          title: 'Account created',
          body: 'We sent a verification link to ${u.email}. Verify it to share scam reports.',
          icon: Icons.mark_email_read_outlined,
          color: K.green);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create the account: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final colors = [K.red, K.orange, K.amber, K.green];
    final words = ['Too weak', 'Weak', 'Okay', 'Strong'];
    return _AuthScaffold(
      title: 'Create your account',
      subtitle: 'Free. Your account lets you report scams so Kantoi can warn other people.',
      showBack: true,
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _ErrorBox(_error),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: (v) => nameProblem(v ?? ''),
                decoration: _field('Your name', Icons.person_outline_rounded),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                validator: (v) => emailProblem(v ?? ''),
                decoration: _field('Email', Icons.mail_outline_rounded),
              ),
              const SizedBox(height: 14),
              _PasswordField(
                controller: _password,
                action: TextInputAction.next,
                autofill: const [AutofillHints.newPassword],
                validator: (v) => passwordProblem(v ?? ''),
                onChanged: (v) => setState(() => _strength = passwordStrength(v)),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: 'Password strength: ${words[_strength]}',
                child: Row(children: [
                  Expanded(
                    child: KProgressBar(
                      value: _password.text.isEmpty ? 0 : (_strength + 1) / 4,
                      color: colors[_strength],
                      height: 6,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(_password.text.isEmpty ? '8+ characters, letters and numbers' : words[_strength],
                        style: t.bodySmall, textAlign: TextAlign.end),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              _PasswordField(
                controller: _confirm,
                label: 'Confirm password',
                autofill: const [AutofillHints.newPassword],
                validator: (v) => v != _password.text ? 'The passwords do not match' : null,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: _agree,
                onChanged: (v) => setState(() => _agree = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'When I report a scam, Kantoi may share the website, or a masked number or account, '
                  'with other users. My messages never leave my phone.',
                  style: t.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              _BusyButton(label: 'Create account', busy: _busy, onPressed: _submit),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                child: const Text('I already have an account'),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Sends a password reset link.
class ForgotPasswordPage extends StatefulWidget {
  final String email;
  const ForgotPasswordPage({super.key, this.email = ''});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  bool _busy = false;
  String? _error;
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.sendPasswordReset(_email.text);
      if (mounted) setState(() => _sentTo = _email.text.trim());
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not send the link: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _AuthScaffold(
      title: 'Reset your password',
      subtitle: 'Enter your account email. We will send a link to choose a new password.',
      showBack: true,
      children: [
        AnimatedSwitcher(
          duration: K.medium,
          child: _sentTo != null
              ? KCard(
                  key: const ValueKey('sent'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.mark_email_read_outlined, color: K.green, size: 32),
                    const SizedBox(height: 10),
                    Text('Check your inbox', style: t.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      'If an account exists for $_sentTo, a reset link is on its way. '
                      'It can take a few minutes, and may land in spam. '
                      'Kantoi will never ask for your password by message or call.',
                      style: t.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Back to sign in')),
                    TextButton(onPressed: _busy ? null : _submit, child: const Text('Send again')),
                  ]),
                )
              : Form(
                  key: _form,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _ErrorBox(_error),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      validator: (v) => emailProblem(v ?? ''),
                      onFieldSubmitted: (_) => _submit(),
                      decoration: _field('Email', Icons.mail_outline_rounded),
                    ),
                    const SizedBox(height: 20),
                    _BusyButton(label: 'Send reset link', busy: _busy, onPressed: _submit),
                  ]),
                ),
        ),
      ],
    );
  }
}

/// The account card in Settings.
class AccountSection extends StatefulWidget {
  const AccountSection({super.key});
  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on AuthFailure catch (e) {
      if (mounted) showKToast(context, title: e.message, icon: Icons.error_outline_rounded, color: K.red);
    } catch (e) {
      if (mounted) showKToast(context, title: 'Something went wrong', body: '$e', icon: Icons.error_outline_rounded, color: K.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (!auth.available) {
      return Text(
        firebaseConfigured ? firebaseProblem : 'Accounts are off in this build. Everything else works on your phone.',
        style: t.bodySmall,
      );
    }
    return ValueListenableBuilder<AccountUser?>(
      valueListenable: auth.user,
      builder: (context, u, _) {
        if (u == null) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('You are using Kantoi without an account. Sign in to share and see community scam reports.', style: t.bodyMedium),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignInPage(pushed: true))),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in or create account'),
            ),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: K.surfaceMid,
              child: Text(u.greetingName.characters.first.toUpperCase(),
                  style: const TextStyle(color: K.primary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.name.isEmpty ? u.email : u.name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(u.email, style: t.bodySmall),
              ]),
            ),
            u.emailVerified
                ? const Pill('Verified', color: K.green, icon: Icons.verified_rounded)
                : const Pill('Not verified', color: K.amber, icon: Icons.mark_email_unread_outlined),
          ]),
          if (!u.emailVerified) ...[
            const SizedBox(height: 12),
            Text('Verify your email to share scam reports. Open the link we sent, then tap "I have verified".', style: t.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          final ok = await auth.refresh();
                          if (!context.mounted) return;
                          showKToast(context,
                              title: ok ? 'Email verified. Thank you!' : 'Not verified yet',
                              body: ok ? null : 'Open the link in the email first. Check spam too.',
                              icon: ok ? Icons.verified_rounded : Icons.hourglass_empty_rounded,
                              color: ok ? K.green : K.amber);
                        }),
                child: const Text('I have verified'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await auth.resendVerification();
                          if (context.mounted) showKToast(context, title: 'Verification email sent', body: 'Sent to ${u.email}.');
                        }),
                child: const Text('Resend email'),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: K.red),
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await auth.signOut();
                        // Back to the sign-in screen behind Settings.
                        if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                      }),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Sign out'),
            ),
          ),
        ]);
      },
    );
  }
}
