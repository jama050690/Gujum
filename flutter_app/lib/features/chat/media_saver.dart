import 'package:flutter/services.dart';

/// Faylni tizim galereyasiga yoki Downloads papkasiga saqlaydi.
///
/// Android 10 dan boshlab ochiq papkalarga yozish uchun MediaStore kerak —
/// shuning uchun ish native tomonda bajariladi. MediaStore orqali yozishda
/// hech qanday ruxsat so'ralmaydi.
class MediaSaver {
  const MediaSaver._();

  static const _channel = MethodChannel('bootchat/media_save');

  /// Rasm va videolar uchun — Galereyada ko'rinadi.
  static Future<bool> saveToGallery({
    required String path,
    required String fileName,
    required String mimeType,
  }) =>
      _invoke('saveToGallery', path, fileName, mimeType);

  /// Hujjat, ovoz va boshqa fayllar uchun — Downloads/Gujum ichiga.
  static Future<bool> saveToDownloads({
    required String path,
    required String fileName,
    required String mimeType,
  }) =>
      _invoke('saveToDownloads', path, fileName, mimeType);

  static Future<bool> _invoke(
    String method,
    String path,
    String fileName,
    String mimeType,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>(method, {
        'path': path,
        'fileName': fileName,
        'mimeType': mimeType,
      });
      return result != null && result.isNotEmpty;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Fayl nomidan MIME turini taxmin qiladi — MediaStore uni qaysi to'plamga
  /// qo'yishni shu asosda hal qiladi.
  static String mimeFor(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case '3gp':
        return 'video/3gpp';
      case 'mkv':
        return 'video/x-matroska';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  /// Rasm va videolar galereyaga, qolgani Downloads ga.
  static bool goesToGallery(String mimeType) =>
      mimeType.startsWith('image/') || mimeType.startsWith('video/');
}
