import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../l10n/app_strings.dart';
import '../settings/settings_controller.dart';
import 'auth_controller.dart';
import 'google_auth_service.dart';
import 'phone_login_page.dart';

enum AuthScreen { welcome, phoneLogin }

class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key});

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  // Kirish Google tugmasidan boshlanadi. Google hisobi bo'lmagan
  // qurilmalar uchun ikkinchi yo'l — raqam va ism (PhoneLoginPage).
  // Username/parol formasi va "parolni unutdim" olib tashlandi: yangi
  // akkauntlarda parol umuman yo'q.
  AuthScreen _screen = AuthScreen.welcome;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: switch (_screen) {
        AuthScreen.welcome => WelcomePage(
            key: const ValueKey('welcome'),
            onOpenOtherMethods: () =>
                setState(() => _screen = AuthScreen.phoneLogin),
          ),
        AuthScreen.phoneLogin => PhoneLoginPage(
            key: const ValueKey('phone_login'),
            onBack: () => setState(() => _screen = AuthScreen.welcome),
          ),
      },
    );
  }
}

/// Birinchi ekran: bitta katta "Google bilan davom etish" tugmasi.
///
/// Raqam, ism va kontaktlar keyingi qadamlarda so'raladi (OnboardingFlow),
/// shuning uchun bu yerda hech qanday maydon yo'q.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.onOpenOtherMethods});

  final VoidCallback onOpenOtherMethods;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _loading = false;
  String? _error;

  Future<void> _continueWithGoogle() async {
    final settings = context.read<SettingsController>();
    final auth = context.read<AuthController>();
    final googleAuth = context.read<GoogleAuthService>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);

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
    final t = (String key) => AppStrings.text(settings.localeCode, key);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Til tanlash faqat sozlamalarda edi, ular esa kirishdan keyin
              // ochiladi — ilovani birinchi marta ochgan odam o'z tilini
              // tanlay olmasdi. Ilgari bu tanlagich eski kirish formasida
              // turardi va uz/en/ru dan boshqasini ko'rsatmasdi.
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _LocaleMenu(settings: settings),
              ),
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
                onPressed: _loading ? null : widget.onOpenOtherMethods,
                child: Text(t('other_sign_in_methods')),
              ),
            ],
          ),
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

class _LocaleMenu extends StatelessWidget {
  const _LocaleMenu({required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    // Ro'yxat AppStrings dan olinadi. Ilgari bu yerda uz/en/ru qo'lda
    // yozilgan edi va arabcha yoki koreyscha tanlangan foydalanuvchi kirish
    // ekraniga qaytsa DropdownButton yiqilardi: uning qiymati ro'yxatda
    // yo'q edi ("There should be exactly one item with the value").
    return DropdownButton<String>(
      value: AppStrings.supportedLocales.contains(settings.localeCode)
          ? settings.localeCode
          : AppStrings.supportedLocales.first,
      underline: const SizedBox.shrink(),
      items: [
        for (final code in AppStrings.supportedLocales)
          DropdownMenuItem(
            value: code,
            child: Text(AppStrings.languageNames[code] ?? code.toUpperCase()),
          ),
      ],
      onChanged: (value) {
        if (value != null) {
          settings.setLocaleCode(value);
        }
      },
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
