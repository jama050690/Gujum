import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

// Top-level — background izolatsiyada ishlaydi
@pragma('vm:entry-point')
Future<void> onBackgroundMessage(RemoteMessage message) async {
  if (message.data['type'] != 'incoming_call') return;
  await _showCallNotification(
    callerName: message.data['callerName'] ?? '',
    isVideo: message.data['isVideo'] == 'true',
    callId: message.data['callId'] ?? '0',
  );
}

Future<void> _showCallNotification({
  required String callerName,
  required bool isVideo,
  required String callId,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await plugin.show(
    callId.hashCode & 0x7FFFFFFF,
    callerName,
    isVideo ? "Video qo'ng'iroq keldi" : "Ovozli qo'ng'iroq keldi",
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'incoming_calls',
        'Incoming Calls',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        autoCancel: true,
      ),
    ),
  );
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  String? _username;
  String? _baseUrl;

  Future<void> init() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    // Android notification channel yaratish
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'incoming_calls',
            'Incoming Calls',
            description: "Qo'ng'iroqlar uchun bildirishnomalar",
            importance: Importance.max,
            playSound: false,
            enableVibration: true,
          ),
        );

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // App notification yopiq bo'lganda ochilsa
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message?.data['type'] == 'incoming_call') {
        // Socket ulanadi va pending CALL_OFFER yetkaziladi
        debugPrint('[FCM] App notificationdan ochildi: ${message?.data}');
      }
    });
  }

  Future<void> register({
    required String baseUrl,
    required String username,
  }) async {
    _username = username;
    _baseUrl = baseUrl;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(token);
      FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);
    } catch (e) {
      debugPrint('[FCM] register error: $e');
    }
  }

  Future<void> unregister() async {
    if (_username == null || _baseUrl == null) return;
    final username = _username!;
    final baseUrl = _baseUrl!;
    _username = null;
    _baseUrl = null;
    try {
      await FirebaseMessaging.instance.deleteToken();
      await http.delete(
        Uri.parse('$baseUrl/api/fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username}),
      );
    } catch (e) {
      debugPrint('[FCM] unregister error: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    if (_username == null || _baseUrl == null) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/api/fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': _username, 'token': token}),
      );
      debugPrint('[FCM] Token saqlandi');
    } catch (e) {
      debugPrint('[FCM] save token error: $e');
    }
  }
}
