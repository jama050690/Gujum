import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_pages.dart';
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
      title: 'Bootchat',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      locale: settings.locale,
      home: auth.isAuthenticated ? const ChatPage() : const AuthFlow(),
    );
  }
}
