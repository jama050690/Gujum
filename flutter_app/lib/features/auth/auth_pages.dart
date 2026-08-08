import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';
import 'auth_controller.dart';
import 'google_auth_service.dart';
import 'phone_login_page.dart';

enum AuthScreen { welcome, language, signIn, phoneLogin }

class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key});

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  // Qadamlar: salomlashish → til → kirish usuli. Raqam va ism kirgandan
  // keyin so'raladi (OnboardingFlow), Google orqali kirganda ism u yerda
  // o'tkazib yuboriladi.
  //
  // Til aynan shu yerda so'raladi: sozlamalar kirishdan keyin ochiladi,
  // ya'ni ilovani birinchi marta ochgan odam boshqa joyda tilini tanlay
  // olmasdi. Username/parol formasi va "parolni unutdim" olib tashlandi:
  // yangi akkauntlarda parol umuman yo'q.
  AuthScreen _screen = AuthScreen.welcome;

  /// Telefon bilan kirishning ikkinchi qadami (ism). Sahifaning ichida emas,
  /// shu yerda — "orqaga" bitta joyda hal qilinsin.
  bool _phoneNameStep = false;

  DateTime? _lastBackPress;

  /// Qadamning oldingisi. Birinchi qadamda null — u yerda tizim tugmasi
  /// odatdagidek ishlaydi (ilovadan chiqadi).
  AuthScreen? get _previousScreen => switch (_screen) {
        AuthScreen.welcome => null,
        AuthScreen.language => AuthScreen.welcome,
        AuthScreen.signIn => AuthScreen.language,
        AuthScreen.phoneLogin => AuthScreen.signIn,
      };

  @override
  Widget build(BuildContext context) {
    final previous = _previousScreen;
    final settings = context.watch<SettingsController>();
    // Qadamlar Navigator marshrutlari emas, oddiy holat — shuning uchun
    // tizimning "orqaga" tugmasi ular haqida bilmaydi va marshrutlar
    // to'plamida bittagina yozuv (home) borligi uchun ilovadan chiqib
    // ketardi. Ekrandagi strelka ishlab, apparat tugmasi ishlamasdi.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Ism qadamidan avval raqam qadamiga qaytamiz, keyingina ekrandan.
        if (_phoneNameStep) {
          setState(() => _phoneNameStep = false);
          return;
        }
        if (previous != null) {
          setState(() => _screen = previous);
          return;
        }
        // Birinchi qadam. Chiqish bitta bosishda emas, ikkitasida — chat
        // sahifasi va ro'yxatdan o'tish qadamlari ham shunday ishlaydi,
        // bu yerda esa bitta tasodifiy bosish ilovani yopib qo'yardi.
        final now = DateTime.now();
        final last = _lastBackPress;
        if (last != null && now.difference(last) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _lastBackPress = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppStrings.text(settings.localeCode, 'exit_press_again')),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: switch (_screen) {
        AuthScreen.welcome => WelcomePage(
            key: const ValueKey('welcome'),
            onContinue: () => setState(() => _screen = AuthScreen.language),
          ),
        AuthScreen.language => LanguagePage(
            key: const ValueKey('language'),
            onContinue: () => setState(() => _screen = AuthScreen.signIn),
            onBack: () => setState(() => _screen = AuthScreen.welcome),
          ),
        AuthScreen.signIn => SignInPage(
            key: const ValueKey('sign_in'),
            onOpenPhoneLogin: () => setState(() {
              _phoneNameStep = false;
              _screen = AuthScreen.phoneLogin;
            }),
            onBack: () => setState(() => _screen = AuthScreen.language),
          ),
        AuthScreen.phoneLogin => PhoneLoginPage(
            key: const ValueKey('phone_login'),
            nameStep: _phoneNameStep,
            onNeedsName: () => setState(() => _phoneNameStep = true),
            onBack: () => setState(() {
              if (_phoneNameStep) {
                _phoneNameStep = false;
              } else {
                _screen = AuthScreen.signIn;
              }
            }),
          ),
      },
      ),
    );
  }
}

/// Kirish usuli: Google yoki telefon raqami.
///
/// Raqam, ism va kontaktlar keyingi qadamlarda so'raladi (OnboardingFlow),
/// shuning uchun bu yerda hech qanday maydon yo'q.
class SignInPage extends StatefulWidget {
  const SignInPage({
    super.key,
    required this.onOpenPhoneLogin,
    required this.onBack,
  });

  final VoidCallback onOpenPhoneLogin;
  final VoidCallback onBack;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _loading = false;
  String? _error;

  Future<void> _continueWithGoogle() async {
    final settings = context.read<SettingsController>();
    final auth = context.read<AuthController>();
    final googleAuth = context.read<GoogleAuthService>();
    String t(String key) => AppStrings.text(settings.localeCode, key);

    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      final credential = await googleAuth.signInForCredential();
      await auth.loginWithGoogle(credential: credential);
    } on GoogleAuthException catch (error) {
      if (error.code == GoogleAuthErrorCode.cancelled) return;
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
        message = '$message\n${error.details}';
      }
      if (mounted) setState(() => _error = message);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();
    String t(String key) => AppStrings.text(settings.localeCode, key);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              const Center(child: _GujumLogo(size: 96, withShadow: true)),
              const SizedBox(height: 28),
              Text(
                'Gujum',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                t('auth_tagline'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(flex: 3),
              if (_error != null) ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              _GoogleSignInButton(
                loading: _loading,
                label: t('sign_in_google'),
                onPressed: _loading ? null : _continueWithGoogle,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loading ? null : widget.onOpenPhoneLogin,
                child: Text(t('other_sign_in_methods')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1-qadam: salomlashish. Hech narsa so'ramaydi.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();
    String t(String key) => AppStrings.text(settings.localeCode, key);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              const Center(child: _GujumLogo(size: 96, withShadow: true)),
              const SizedBox(height: 28),
              Text(
                'Gujum',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                t('auth_tagline'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(flex: 3),
              FilledButton(
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(t('onboarding_continue')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2-qadam: til. Sozlamalar kirishdan keyin ochilgani uchun til aynan shu
/// yerda so'raladi — aks holda ilovani birinchi ochgan odam uni umuman
/// o'zgartira olmaydi.
class LanguagePage extends StatelessWidget {
  const LanguagePage({
    super.key,
    required this.onContinue,
    required this.onBack,
  });

  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();
    String t(String key) => AppStrings.text(settings.localeCode, key);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: onBack),
        title: Text(t('language')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // Flutter 3.32 dan keyin tanlov holati RadioGroup da yuritiladi;
              // RadioListTile.groupValue/onChanged eskirgan.
              child: RadioGroup<String>(
                groupValue: settings.localeCode,
                onChanged: (value) {
                  if (value != null) settings.setLocaleCode(value);
                },
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final code in AppStrings.supportedLocales)
                      RadioListTile<String>(
                        value: code,
                        // Sozlamalardagi bilan bir xil ko'rinish: kod va
                        // yonida tilning o'z tilidagi nomi.
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              code.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(AppStrings.languageNames[code] ?? code),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onContinue,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(t('onboarding_continue')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GujumLogo extends StatelessWidget {
  const _GujumLogo({
    required this.size,
    this.radius = 22,
    this.padding = 10,
    this.withShadow = false,
  });

  final double size;
  final double radius;
  final double padding;
  final bool withShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: withShadow
            ? const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Image.asset(
        'assets/images/gujum_logo.png',
        fit: BoxFit.contain,
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
