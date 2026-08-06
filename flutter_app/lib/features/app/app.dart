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
import '../chat/chat_page.dart';
import '../settings/settings_controller.dart';

class BootchatApp extends StatelessWidget {
  const BootchatApp({super.key});

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
      home: CallOverlayHost(
        child: !auth.isAuthenticated
            ? const AuthFlow()
            : OnboardingFlow.isNeeded(auth, context.read<SessionStore>())
                ? const OnboardingFlow()
                : const ChatPage(),
      ),
    );
  }
}
