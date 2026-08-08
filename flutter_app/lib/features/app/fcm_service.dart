import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_strings.dart';

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

  // Background isolate da Provider yo'q — til to'g'ridan-to'g'ri saqlangan
  // sozlamalardan o'qiladi, shunda bildirishnoma matnlari ham tarjima
  // qilinadi va hech qayerda qatorlar qotib qolmaydi.
  try {
    final prefs = await SharedPreferences.getInstance();
    AppStrings.currentLocale =
        prefs.getString('gujum.locale') ?? AppConfig.defaultLocale;
  } catch (_) {}
  String t(String key) => AppStrings.t(key);

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
        textAccept: t('call_accept'),
        textDecline: t('call_decline'),
        incomingCallNotificationChannelName: t('call_channel_incoming'),
        missedCallNotificationChannelName: t('call_channel_missed'),
      ),
    ));
  } catch (e) {
  }
}


class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  String? _username;
  String? _baseUrl;

  Future<void> init({bool askPermissions = true}) async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // Qo'ng'iroq kanali.
    //
    // Kanal ID si 'incoming_calls' dan 'incoming_calls_v2' ga o'zgartirildi:
    // eski kanal playSound: false bilan yaratilgan edi va zaxira
    // (fallback) bildirishnoma ovozsiz kelardi — ya'ni aynan tovush chiqarishi
    // kerak bo'lgan yo'l jim edi. Android kanal sozlamalarini yaratilgandan
    // keyin o'zgartirishga ruxsat bermaydi, shuning uchun yangi ID kerak.
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        'incoming_calls_v2',
        AppStrings.t('notif_calls_channel'),
        description: AppStrings.t('notif_calls_channel_desc'),
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    // Eski jim kanalni ro'yxatdan olib tashlaymiz — sozlamalarda ikkita bir
    // xil nomli kanal turib qolmasin.
    await androidPlugin?.deleteNotificationChannel('incoming_calls');

    // Xabar kanali — FCM notification shu kanalga yuboriladi
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        'messages',
        AppStrings.t('notif_messages_channel'),
        description: AppStrings.t('notif_messages_channel_desc'),
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    // Kanallar har safar tekshiriladi (arzon), ruxsatlar esa faqat bir marta
    // so'raladi. Aks holda har ishga tushishda tizim oynalari chiqaverardi.
    if (!askPermissions) return;

    // Battery optimization o'chirilmasa data-only FCM killed app'ga yetmaydi.
    _requestBatteryExemption();

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Android 13+ uchun notification permission
    await FlutterCallkitIncoming.requestNotificationPermission({
      'rationaleMessagePermission': AppStrings.t('notif_permission_calls'),
      'postNotificationMessagePermission':
          AppStrings.t('notif_permission_generic'),
    });

    // Android 14+ uchun to'liq ekran ruxsati (lock screen da ko'rinishi uchun)
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {}

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
    }
  }

  Future<void> unregister() async {
    if (_username == null || _baseUrl == null) return;
    final username = _username!;
    final baseUrl = _baseUrl!;
    _username = null;
    _baseUrl = null;
    try {
      // Tokenni o'chirishdan oldin olamiz — serverga aynan shu qurilmani
      // ko'rsatish uchun. Aks holda foydalanuvchining boshqa qurilmalari ham
      // ro'yxatdan chiqib, u yerda qo'ng'iroqlar kelmay qolardi.
      String? token;
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
      await FirebaseMessaging.instance.deleteToken();
      await http.delete(
        Uri.parse('$baseUrl/api/fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'token': ?token,
        }),
      );
    } catch (e) {
    }
  }

  static const _audioChannel = MethodChannel('gujum/call_audio');

  void _requestBatteryExemption() {
    _audioChannel.invokeMethod<void>('requestBatteryExemption').catchError((_) {});
  }

  Future<void> _saveToken(String token) async {
    if (_username == null || _baseUrl == null) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/api/fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': _username, 'token': token}),
      );
    } catch (e) {
    }
  }
}
