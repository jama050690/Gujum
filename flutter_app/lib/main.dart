import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/network/session_store.dart';
import 'core/network/socket_service.dart';
import 'features/app/app.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/google_auth_service.dart';
import 'features/auth/auth_repository.dart';
import 'features/call/call_controller.dart';
import 'features/call/call_kit_service.dart';
import 'features/chat/chat_controller.dart';
import 'features/chat/chat_repository.dart';
import 'features/settings/settings_controller.dart';
import 'features/social/social_repository.dart';
import 'features/app/fcm_service.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);

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
  final callController = CallController(
    socketService: socketService,
    authController: authController,
  );
  CallKitService.instance.init();

  final chatController = ChatController(
    chatRepository: chatRepository,
    socketService: socketService,
    authController: authController,
    settingsController: settingsController,
    sessionStore: sessionStore,
  );
  await chatController.bootstrap();

  // Killed holatda qabul qilingan qo'ng'iroqni tekshirish
  unawaited(() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final call in calls) {
        if (call.isAccepted) {
          callController.setPendingAutoAccept(call.id);
          break;
        }
      }
    } catch (_) {}
  }());
  // Backup: notifikatsiya bosilgandan 750ms o'tgach method channel orqali keladi
  FlutterCallkitIncoming.acceptCallHandle((data) {
    final callId = (data['id'] ?? '').toString();
    if (callId.isNotEmpty) callController.setPendingAutoAccept(callId);
  });

  authController.addListener(() {
    if (authController.isAuthenticated && authController.user != null) {
      FcmService.instance.register(
        baseUrl: settingsController.baseUrl,
        username: authController.user!.username,
      );
    } else {
      FcmService.instance.unregister();
    }
  });

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
        ChangeNotifierProvider.value(value: callController),
        ChangeNotifierProvider.value(value: chatController),
      ],
      child: const GujumApp(),
    ),
  );

  // FCM init runApp dan keyin — UI bloklanmasin
  unawaited(() async {
    await FcmService.instance.init();
    if (authController.isAuthenticated && authController.user != null) {
      await FcmService.instance.register(
        baseUrl: settingsController.baseUrl,
        username: authController.user!.username,
      );
    }
  }());
}
