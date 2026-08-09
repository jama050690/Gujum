import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Mobil va ish stoli uchun klient.
///
/// Dart da bo'sh turgan ulanish standart holda 15 soniyadan keyin
/// yopiladi. Foydalanuvchi ekranlar orasida shundan uzoqroq yursa,
/// keyingi so'rov yana DNS + TCP + TLS ni boshidan bajaradi. O'lchov:
/// yangi ulanishda so'rov ~0.86 s, tayyor ulanishda ~0.27 s — ya'ni
/// qo'l siqish uchun har safar ~0.6 s.
///
/// 90 soniya — odam bir ekrandan ikkinchisiga o'tguncha ulanish tirik
/// qoladi, lekin uzoq turib qolgan ulanishlar ham ushlab qolinmaydi.
http.Client createHttpClient() {
  final client = HttpClient()
    ..idleTimeout = const Duration(seconds: 90)
    ..connectionTimeout = const Duration(seconds: 20);
  return IOClient(client);
}
