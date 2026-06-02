import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_pages.dart';
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
      home: CallOverlayHost(
        child: auth.isAuthenticated ? const ChatPage() : const AuthFlow(),
      ),
    );
  }
}
