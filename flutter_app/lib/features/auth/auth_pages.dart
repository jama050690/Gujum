import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/session_store.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';
import 'auth_controller.dart';
import 'auth_repository.dart';
import 'google_auth_service.dart';

enum AuthScreen { login, signup, forgot }

class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key});

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  AuthScreen _screen = AuthScreen.login;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: switch (_screen) {
        AuthScreen.login => LoginPage(
            key: const ValueKey('login'),
            onOpenSignup: () => setState(() => _screen = AuthScreen.signup),
            onOpenForgot: () => setState(() => _screen = AuthScreen.forgot),
          ),
        AuthScreen.signup => SignupPage(
            key: const ValueKey('signup'),
            onBackToLogin: () => setState(() => _screen = AuthScreen.login),
          ),
        AuthScreen.forgot => ForgotPasswordPage(
            key: const ValueKey('forgot'),
            onBackToLogin: () => setState(() => _screen = AuthScreen.login),
          ),
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onOpenSignup,
    required this.onOpenForgot,
  });

  final VoidCallback onOpenSignup;
  final VoidCallback onOpenForgot;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  String _savedUsername = '';
  bool _googleLoading = false;
  bool _obscurePassword = true;
  bool _userInteracted = false;

  @override
  void initState() {
    super.initState();
    _loadSavedUsername();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearInitialAutofill();
      Future<void>.delayed(
        const Duration(milliseconds: 350),
        _clearInitialAutofill,
      );
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final auth = context.watch<AuthController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    final compact = MediaQuery.sizeOf(context).height < 900;
    final showSavedUsernameSuggestion = _shouldShowSavedUsernameSuggestion();
    final suggestionPrompt = switch (settings.localeCode) {
      'ru' => 'Использовать сохраненный username?',
      'en' => 'Use saved username?',
      _ => 'Shuni xohlaysizmi?',
    };
    final suggestionActionLabel = switch (settings.localeCode) {
      'ru' => 'Выбрать',
      'en' => 'Use',
      _ => 'Tanlash',
    };

    return _AuthScaffold(
      title: t('app_title'),
      subtitle: t('login_title'),
      settings: settings,
      compact: compact,
      header: _LoginHeader(
        title: t('app_title'),
        subtitle: t('login_title'),
        settings: settings,
        compact: compact,
        showAvatar: false,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) _ErrorBanner(message: _error!, compact: compact),
          _AuthFieldLabel(label: t('username'), compact: compact),
          SizedBox(height: compact ? 6 : 8),
          TextField(
            controller: _usernameController,
            onTap: _markUserInteracted,
            onChanged: (_) {
              _markUserInteracted();
              setState(() => _error = null);
            },
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.newUsername],
            decoration: _authInputDecoration(
              label: t('username'),
              icon: Icons.person_outline_rounded,
              compact: compact,
            ),
          ),
          if (showSavedUsernameSuggestion) ...[
            SizedBox(height: compact ? 6 : 8),
            _SavedUsernameSuggestion(
              compact: compact,
              prompt: suggestionPrompt,
              username: _savedUsername,
              actionLabel: suggestionActionLabel,
              onTap: _applySavedUsernameSuggestion,
            ),
          ],
          SizedBox(height: compact ? 12 : 16),
          _AuthFieldLabel(label: t('password'), compact: compact),
          SizedBox(height: compact ? 6 : 8),
          TextField(
            controller: _passwordController,
            onTap: _markUserInteracted,
            onChanged: (_) {
              _markUserInteracted();
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            obscureText: _obscurePassword,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.newPassword],
            decoration: _authInputDecoration(
              label: t('password'),
              icon: Icons.lock_outline_rounded,
              compact: compact,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 14 : 20),
          _GradientAuthButton(
            compact: compact,
            onPressed: auth.isLoading ? null : () => _submit(context),
            child: auth.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _AuthActionLabel(
                    icon: Icons.login_rounded,
                    label: t('sign_in'),
                  ),
          ),
          SizedBox(height: compact ? 12 : 16),
          _AuthDivider(label: t('or'), compact: compact),
          SizedBox(height: compact ? 12 : 16),
          _GoogleSignInButton(
            loading: _googleLoading,
            label: _googleLoading
                ? t('sign_in_google_loading')
                : t('sign_in_google'),
            darkStyle: true,
            compact: compact,
            onPressed: auth.isLoading || _googleLoading
                ? null
                : () => _loginWithGoogle(context),
          ),
          SizedBox(height: compact ? 4 : 8),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 8,
                vertical: compact ? 2 : 4,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: widget.onOpenForgot,
            child: _AuthActionLabel(
              icon: Icons.lock_reset_rounded,
              label: t('forgot_password'),
            ),
          ),
          SizedBox(height: compact ? 2 : 4),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: compact ? 2 : 4,
            runSpacing: compact ? 2 : 4,
            children: [
              Text(t('no_account')),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 4 : 8,
                    vertical: compact ? 2 : 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: widget.onOpenSignup,
                child: _AuthActionLabel(
                  icon: Icons.person_add_alt_1_rounded,
                  label: t('sign_up'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final auth = context.read<AuthController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);

    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _error = t('error_required'));
      return;
    }

    setState(() => _error = null);
    try {
      await auth.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _loginWithGoogle(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final auth = context.read<AuthController>();
    final googleAuth = context.read<GoogleAuthService>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);

    setState(() {
      _error = null;
      _googleLoading = true;
    });

    try {
      final credential = await googleAuth.signInForCredential();
      await auth.loginWithGoogle(credential: credential);
    } on GoogleAuthException catch (error) {
      if (error.code == GoogleAuthErrorCode.cancelled) {
        return;
      }

      var message = switch (error.code) {
        GoogleAuthErrorCode.notConfigured => t('google_not_configured'),
        GoogleAuthErrorCode.androidClientMismatch =>
          t('google_android_client_mismatch'),
        GoogleAuthErrorCode.missingIdToken => t('google_token_missing'),
        GoogleAuthErrorCode.failed => t('google_sign_in_failed'),
        GoogleAuthErrorCode.cancelled => '',
      };
      if (error.details != null && error.details!.trim().isNotEmpty) {
        debugPrint('Google login details: ${error.details}');
        if (kDebugMode) {
          message = '$message\n${error.details}';
        }
      }
      setState(() => _error = message);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _googleLoading = false);
      }
    }
  }

  void _markUserInteracted() {
    if (_userInteracted) {
      return;
    }
    setState(() => _userInteracted = true);
  }

  Future<void> _loadSavedUsername() async {
    final sessionStore = context.read<SessionStore>();
    final savedUsername = sessionStore.lastLoginUsername?.trim() ?? '';
    if (!mounted || savedUsername.isEmpty) {
      return;
    }
    setState(() => _savedUsername = savedUsername);
  }

  void _clearInitialAutofill() {
    if (!mounted || _userInteracted) {
      return;
    }
    if (_usernameController.text.isEmpty && _passwordController.text.isEmpty) {
      return;
    }
    _usernameController.clear();
    _passwordController.clear();
  }

  bool _shouldShowSavedUsernameSuggestion() {
    final typedValue = _usernameController.text.trim();
    if (typedValue.isEmpty || _savedUsername.isEmpty) {
      return false;
    }
    if (typedValue.toLowerCase() == _savedUsername.toLowerCase()) {
      return false;
    }
    return _savedUsername.toLowerCase().startsWith(typedValue.toLowerCase());
  }

  void _applySavedUsernameSuggestion() {
    _markUserInteracted();
    _usernameController.value = TextEditingValue(
      text: _savedUsername,
      selection: TextSelection.collapsed(offset: _savedUsername.length),
    );
    setState(() => _error = null);
  }
}

class SignupPage extends StatefulWidget {
  const SignupPage({
    super.key,
    required this.onBackToLogin,
  });

  final VoidCallback onBackToLogin;

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _ageController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isMale = true;
  bool _otpStep = false;
  String? _error;
  String? _info;
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _ageController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    final compact = MediaQuery.sizeOf(context).height < 900;

    return _AuthScaffold(
      title: t('app_title'),
      subtitle: t('signup_title'),
      settings: settings,
      compact: compact,
      header: _LoginHeader(
        title: t('app_title'),
        subtitle: t('signup_title'),
        settings: settings,
        compact: compact,
        showAvatar: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) _ErrorBanner(message: _error!),
          if (_info != null) _InfoBanner(message: _info!),
          if (!_otpStep) ...[
            TextField(
              controller: _fullNameController,
              decoration: _authInputDecoration(
                label: t('full_name'),
                icon: Icons.badge_outlined,
                compact: compact,
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            TextField(
              controller: _usernameController,
              decoration: _authInputDecoration(
                label: t('username'),
                icon: Icons.man_rounded,
                compact: compact,
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            TextField(
              controller: _phoneController,
              decoration: _authInputDecoration(
                label: t('phone'),
                icon: Icons.call_outlined,
                compact: compact,
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            TextField(
              controller: _emailController,
              decoration: _authInputDecoration(
                label: t('email'),
                icon: Icons.mail_outline_rounded,
                compact: compact,
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: _authInputDecoration(
                label: t('password'),
                icon: Icons.lock_outline_rounded,
                compact: compact,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: _authInputDecoration(
                label: t('age'),
                icon: Icons.cake_outlined,
                compact: compact,
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment<bool>(value: true, label: Text(t('male'))),
                ButtonSegment<bool>(value: false, label: Text(t('female'))),
              ],
              selected: {_isMale},
              onSelectionChanged: (value) {
                setState(() => _isMale = value.first);
              },
            ),
            SizedBox(height: compact ? 14 : 20),
            FilledButton(
              onPressed: _loading ? null : () => _sendOtp(context),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _AuthActionLabel(
                      icon: Icons.arrow_forward_rounded,
                      label: t('continue'),
                    ),
            ),
            SizedBox(height: compact ? 10 : 12),
            _GoogleSignInButton(
              loading: _googleLoading,
              label: _googleLoading
                  ? t('sign_in_google_loading')
                  : t('sign_in_google'),
              onPressed: _loading || _googleLoading
                  ? null
                  : () => _loginWithGoogle(context),
            ),
          ] else ...[
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              decoration: _authInputDecoration(
                label: t('otp_code'),
                icon: Icons.verified_user_outlined,
                compact: compact,
              ),
            ),
            SizedBox(height: compact ? 14 : 20),
            FilledButton(
              onPressed: _loading ? null : () => _verifyOtp(context),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _AuthActionLabel(
                      icon: Icons.verified_rounded,
                      label: t('verify'),
                    ),
            ),
            TextButton(
              onPressed: _loading ? null : () => _resendOtp(context),
              child: _AuthActionLabel(
                icon: Icons.refresh_rounded,
                label: t('resend_code'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: widget.onBackToLogin,
            child: _AuthActionLabel(
              icon: Icons.arrow_back_rounded,
              label: t('back_to_login'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendOtp(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final auth = context.read<AuthController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    final age = int.tryParse(_ageController.text.trim());

    if (_fullNameController.text.trim().isEmpty ||
        _usernameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.length < 8 ||
        age == null) {
      setState(() {
        _error = _passwordController.text.length < 8
            ? t('password_rules')
            : t('error_required');
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      final response = await auth.sendSignupOtp(
        SignupDraft(
          fullName: _fullNameController.text.trim(),
          username: _usernameController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          age: age,
          gender: _isMale,
        ),
      );
      setState(() {
        _otpStep = true;
        _info = response.devOtp == null
            ? response.message
            : '${response.message}. Dev OTP: ${response.devOtp}';
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyOtp(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final auth = context.read<AuthController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);

    if (_otpController.text.trim().isEmpty) {
      setState(() => _error = t('error_required'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      await auth.verifySignupOtp(
        email: _emailController.text.trim(),
        code: _otpController.text.trim(),
      );
      widget.onBackToLogin();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resendOtp(BuildContext context) async {
    final auth = context.read<AuthController>();
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      final response = await auth.resendSignupOtp(_emailController.text.trim());
      setState(() {
        _info = response.devOtp == null
            ? response.message
            : '${response.message}. Dev OTP: ${response.devOtp}';
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loginWithGoogle(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final auth = context.read<AuthController>();
    final googleAuth = context.read<GoogleAuthService>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);

    setState(() {
      _error = null;
      _info = null;
      _googleLoading = true;
    });

    try {
      final credential = await googleAuth.signInForCredential();
      await auth.loginWithGoogle(credential: credential);
    } on GoogleAuthException catch (error) {
      if (error.code == GoogleAuthErrorCode.cancelled) {
        return;
      }

      var message = switch (error.code) {
        GoogleAuthErrorCode.notConfigured => t('google_not_configured'),
        GoogleAuthErrorCode.androidClientMismatch =>
          t('google_android_client_mismatch'),
        GoogleAuthErrorCode.missingIdToken => t('google_token_missing'),
        GoogleAuthErrorCode.failed => t('google_sign_in_failed'),
        GoogleAuthErrorCode.cancelled => '',
      };
      if (error.details != null && error.details!.trim().isNotEmpty) {
        debugPrint('Google signup details: ${error.details}');
        if (kDebugMode) {
          message = '$message\n${error.details}';
        }
      }
      setState(() => _error = message);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _googleLoading = false);
      }
    }
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    super.key,
    required this.onBackToLogin,
  });

  final VoidCallback onBackToLogin;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _otpStep = false;
  bool _done = false;
  bool _loading = false;
  String? _error;
  String? _info;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);

    return _AuthScaffold(
      title: t('app_title'),
      subtitle: t('forgot_title'),
      settings: settings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) _ErrorBanner(message: _error!),
          if (_info != null) _InfoBanner(message: _info!),
          if (!_otpStep && !_done) ...[
            TextField(
              controller: _emailController,
              decoration: _authInputDecoration(
                label: t('email'),
                icon: Icons.mail_outline_rounded,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : () => _sendCode(context),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _AuthActionLabel(
                      icon: Icons.mark_email_read_outlined,
                      label: t('send_code'),
                    ),
            ),
          ],
          if (_otpStep && !_done) ...[
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              decoration: _authInputDecoration(
                label: t('otp_code'),
                icon: Icons.verified_user_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: _authInputDecoration(
                label: t('new_password'),
                icon: Icons.lock_reset_rounded,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : () => _resetPassword(context),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _AuthActionLabel(
                      icon: Icons.password_rounded,
                      label: t('reset_password'),
                    ),
            ),
          ],
          if (_done) ...[
            FilledButton(
              onPressed: widget.onBackToLogin,
              child: _AuthActionLabel(
                icon: Icons.check_circle_outline_rounded,
                label: t('done'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: widget.onBackToLogin,
            child: _AuthActionLabel(
              icon: Icons.arrow_back_rounded,
              label: t('back_to_login'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendCode(BuildContext context) async {
    final auth = context.read<AuthController>();
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      final response =
          await auth.requestPasswordReset(_emailController.text.trim());
      setState(() {
        _otpStep = true;
        _info = response.devOtp == null
            ? response.message
            : '${response.message}. Dev OTP: ${response.devOtp}';
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resetPassword(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final auth = context.read<AuthController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      await auth.resetPassword(
        email: _emailController.text.trim(),
        code: _otpController.text.trim(),
        newPassword: _passwordController.text,
      );
      setState(() {
        _done = true;
        _otpStep = false;
        _info = t('done');
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.settings,
    required this.child,
    this.compact = false,
    this.header,
  });

  final String title;
  final String subtitle;
  final SettingsController settings;
  final Widget child;
  final bool compact;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: settings.isDarkMode
                ? const [
                    Color(0xFF08131D),
                    Color(0xFF10283B),
                    Color(0xFF17344A)
                  ]
                : const [
                    Color(0xFF50C7FF),
                    Color(0xFF2B7CFF),
                    Color(0xFF7E57FF)
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 24,
              vertical: compact ? 10 : 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 18 : 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (header != null)
                        header!
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Icon(
                                    Icons.bolt_rounded,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 30,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(subtitle),
                                  ],
                                ),
                              ],
                            ),
                            _LocaleMenu(settings: settings),
                          ],
                        ),
                      SizedBox(height: compact ? 16 : 24),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader({
    required this.title,
    required this.subtitle,
    required this.settings,
    this.compact = false,
    this.showAvatar = true,
  });

  final String title;
  final String subtitle;
  final SettingsController settings;
  final bool compact;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _LocaleMenu(settings: settings),
        ),
        SizedBox(height: compact ? 6 : 8),
        Container(
          width: compact ? 64 : 78,
          height: compact ? 64 : 78,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.bolt_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: compact ? 34 : 42,
          ),
        ),
        SizedBox(height: compact ? 12 : 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: compact ? 22 : null,
              ),
        ),
        SizedBox(height: compact ? 4 : 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: compact ? 14 : null,
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withValues(alpha: 0.7),
              ),
        ),
        if (showAvatar) ...[
          SizedBox(height: compact ? 12 : 18),
          Container(
            width: compact ? 84 : 112,
            height: compact ? 84 : 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFB5D4FF), width: 4),
            ),
            child: const Icon(
              Icons.account_circle_rounded,
              size: 72,
              color: Color(0xFFB8BEC8),
            ),
          ),
        ],
      ],
    );
  }
}

class _LocaleMenu extends StatelessWidget {
  const _LocaleMenu({required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: settings.localeCode,
      underline: const SizedBox.shrink(),
      items: const [
        DropdownMenuItem(value: 'uz', child: Text('UZ')),
        DropdownMenuItem(value: 'en', child: Text('EN')),
        DropdownMenuItem(value: 'ru', child: Text('RU')),
      ],
      onChanged: (value) {
        if (value != null) {
          settings.setLocaleCode(value);
        }
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.compact = false});

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: compact ? 12 : 18),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message),
    );
  }
}

InputDecoration _authInputDecoration({
  required String label,
  required IconData icon,
  bool compact = false,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: label,
    prefixIcon: Icon(icon, size: compact ? 20 : 22),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0xFFF7FAFF),
    isDense: compact,
    contentPadding: EdgeInsets.symmetric(
      horizontal: compact ? 14 : 18,
      vertical: compact ? 14 : 18,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(compact ? 16 : 18),
      borderSide: const BorderSide(color: Color(0xFFD7E3F2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(compact ? 16 : 18),
      borderSide: const BorderSide(color: Color(0xFFD7E3F2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(compact ? 16 : 18),
      borderSide: const BorderSide(color: Color(0xFF2B7CFF), width: 1.5),
    ),
  );
}

class _AuthFieldLabel extends StatelessWidget {
  const _AuthFieldLabel({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: compact ? 14 : null,
          ),
    );
  }
}

class _SavedUsernameSuggestion extends StatelessWidget {
  const _SavedUsernameSuggestion({
    required this.prompt,
    required this.username,
    required this.actionLabel,
    required this.onTap,
    this.compact = false,
  });

  final String prompt;
  final String username;
  final String actionLabel;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF5FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD7E3F2)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 18,
                color: Color(0xFF4F6B95),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      prompt,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF61738F),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                actionLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF2B7CFF),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthActionLabel extends StatelessWidget {
  const _AuthActionLabel({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

class _AuthDivider extends StatelessWidget {
  const _AuthDivider({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(height: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: compact ? 13 : null,
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withValues(alpha: 0.65),
                ),
          ),
        ),
        const Expanded(child: Divider(height: 1)),
      ],
    );
  }
}

class _GradientAuthButton extends StatelessWidget {
  const _GradientAuthButton({
    required this.onPressed,
    required this.child,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: disabled
            ? null
            : const LinearGradient(
                colors: [Color(0xFF3D86FF), Color(0xFFAF17FF)],
              ),
        color: disabled ? const Color(0xFFD8E7FF) : null,
        boxShadow: disabled
            ? null
            : const [
                BoxShadow(
                  color: Color(0x221D5EFF),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: compact ? 14 : 18,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.loading,
    required this.label,
    required this.onPressed,
    this.darkStyle = false,
    this.compact = false,
  });

  final bool loading;
  final String label;
  final VoidCallback? onPressed;
  final bool darkStyle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: darkStyle ? const Color(0xFF1B2540) : null,
        foregroundColor: darkStyle ? Colors.white : null,
        side: BorderSide(
          color:
              darkStyle ? const Color(0xFF1B2540) : const Color(0xFFD7E3F2),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: compact ? 11 : 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Text(
              'G',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4285F4),
              ),
            ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}
