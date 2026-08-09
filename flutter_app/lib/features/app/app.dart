import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import '../../core/network/session_store.dart';
import '../../l10n/app_strings.dart';
import '../auth/auth_pages.dart';
import '../auth/onboarding_flow.dart';
import '../call/call_overlay.dart';
import 'home_shell.dart';
import 'back_handler.dart';
import 'connection_banner.dart';
import '../settings/settings_controller.dart';

class GujumApp extends StatelessWidget {
  const GujumApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final auth = context.watch<AuthController>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gujum',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      locale: settings.locale,
      // Arabcha tanlanganda interfeys o'zi o'ngdan chapga o'giriladi.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales:
          AppStrings.supportedLocales.map((code) => Locale(code)).toList(),
      // Tarmoq holati butun ilova bo'ylab ko'rinadi — qaysi ekranda
      // bo'lishidan qat'i nazar.
      home: ConnectionBanner(
        child: CallOverlayHost(
          child: !auth.isAuthenticated
              ? const AuthFlow()
              : OnboardingFlow.isNeeded(auth, context.read<SessionStore>())
                  ? const OnboardingFlow()
                  // "Orqaga" asosiy ekran uchun bitta joyda hal qilinadi.
                  // Kirish va ro'yxatdan o'tish oqimlarining o'z
                  // qadamlari bor va ular o'zlari hal qiladi — ularni
                  // ham o'rasak, bitta bosishda ikkalasi ham ishlab
                  // ketardi.
                  : const AppBackHandler(child: HomeShell()),
        ),
      ),
    );
  }
}
