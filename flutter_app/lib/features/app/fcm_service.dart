import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

// Top-level — background/killed holatda ishlaydi
@pragma('vm:entry-point')
Future<void> onBackgroundMessage(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Duplicate-app xatosini oldini olish
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  if (message.data['type'] != 'incoming_call') return;
  final callId = (message.data['callId'] ?? '').toString();
  final callerName = (message.data['callerName'] ?? '').toString();
  final isVideo = message.data['isVideo'] == 'true';

  if (callId.isEmpty) return;

  try {
    await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Gujum',
      handle: callerName,
      type: isVideo ? 1 : 0,
      duration: 30000,
      android: AndroidParams(
        isCustomNotification: true,
        isFullScreen: true,
        isShowFullLockedScreen: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0C111A',
        actionColor: '#4D82E3',
        textAccept: "Qabul qilish",
        textDecline: "Rad etish",
        incomingCallNotificationChannelName: "Qo'ng'iroq",
        missedCallNotificationChannelName: "O'tkazib yuborilgan",
      ),
    ));
  } catch (e) {
    debugPrint('[FCM] showCallkitIncoming error: $e');
  }
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

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Asosiy kanal — CallKit shu kanaldan notification ko'rsatadi
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'incoming_calls',
        'Incoming Calls',
        description: "Qo'ng'iroqlar uchun bildirishnomalar",
        importance: Importance.max,
        playSound: false,
        enableVibration: true,
      ),
    );

    // Jim kanal — FCM notification maydoni uchun (foydalanuvchiga ko'rinmaydi)
    // Android OS shu kanal orqali app'ni kafolatli uyg'otadi
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'fcm_silent',
        'FCM Delivery',
        description: 'FCM yetkazib berish kanali',
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Android 13+ uchun notification permission
    await FlutterCallkitIncoming.requestNotificationPermission({
      'rationaleMessagePermission': "Qo'ng'iroqlar uchun bildirishnoma ruxsati kerak",
      'postNotificationMessagePermission': "Bildirishnomalar uchun ruxsat bering",
    });

    // Android 14+ uchun to'liq ekran ruxsati (lock screen da ko'rinishi uchun)
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {}

    // App notification orqali ochilganda
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message?.data['type'] == 'incoming_call') {
        debugPrint('[FCM] App callkit notificationdan ochildi: ${message?.data}');
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
