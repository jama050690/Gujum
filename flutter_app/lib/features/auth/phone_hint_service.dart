import 'package:flutter/services.dart';

/// Qurilmadagi SIM raqamlarini tizim tanlagichi orqali so'raydi.
///
/// Play Services'ning Phone Number Hint API si ishlatiladi: hech qanday
/// ruxsat so'ralmaydi, ikki SIM bo'lsa ikkalasi ham ro'yxatda chiqadi.
/// Foydalanuvchi bekor qilsa yoki qurilma qo'llab-quvvatlamasa `null` qaytadi —
/// bunday holda qo'lda kiritish oynasiga tushamiz.
class PhoneHintService {
  const PhoneHintService._();

  static const _channel = MethodChannel('gujum/phone_hint');

  static Future<String?> requestSimNumber() async {
    try {
      final number = await _channel.invokeMethod<String>('requestPhoneNumberHint');
      final trimmed = (number ?? '').trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }
}
