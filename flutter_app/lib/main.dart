import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/network/session_store.dart';
import 'core/network/socket_service.dart';
import 'features/app/app.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/google_auth_service.dart';
import 'features/auth/auth_repository.dart';
import 'features/chat/chat_controller.dart';
import 'features/chat/chat_repository.dart';
import 'features/settings/settings_controller.dart';
import 'features/social/social_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sessionStore = await SessionStore.create();
  final settingsController = SettingsController(sessionStore)..load();
  final apiClient = ApiClient(
    sessionStore: sessionStore,
    baseUrlProvider: settingsController.currentBaseUrl,
  );
  final authRepository = AuthRepository(apiClient: apiClient);
  final googleAuthService = GoogleAuthService();
  final chatRepository = ChatRepository(apiClient: apiClient);
  final socialRepository = SocialRepository(apiClient: apiClient);
  final socketService = SocketService();
  final authController = AuthController(
    authRepository: authRepository,
    sessionStore: sessionStore,
  );
  await authController.bootstrap();

  final chatController = ChatController(
    chatRepository: chatRepository,
    socketService: socketService,
    authController: authController,
    settingsController: settingsController,
    sessionStore: sessionStore,
  );
  await chatController.bootstrap();

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: sessionStore),
        Provider.value(value: apiClient),
        Provider.value(value: socketService),
        Provider.value(value: socialRepository),
        Provider.value(value: googleAuthService),
        ChangeNotifierProvider.value(value: settingsController),
        ChangeNotifierProvider.value(value: authController),
        ChangeNotifierProvider.value(value: chatController),
      ],
      child: const BootchatApp(),
    ),
  );
}
