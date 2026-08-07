import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Xabarlarga biriktirilgan fayllarning qurilmadagi doimiy nusxasi.
///
/// Server media fayllarini 24 soatdan keyin o'chiradi, ilova esa ularni har
/// safar tarmoqdan yuklab ko'rsatardi — ya'ni eski xabarning matni qolib,
/// rasmi yo'qolardi. Endi fayl kelishi bilan bir marta yuklab olinadi va
/// keyin faqat diskdan o'qiladi.
///
/// cached_network_image ham keshlaydi, lekin u LRU: joy yetmasa yoki muddati
/// o'tsa o'chirib yuboradi. Bu yerda esa ataylab hech narsa o'chirilmaydi.
class MediaStore {
  MediaStore._(this._dir);

  final Directory _dir;

  /// Media yuklab olishda ham ulanish qayta ishlatiladi: bir suhbatda
  /// o'nlab fayl bo'lishi mumkin, har biriga alohida TLS qo'l siqish qimmat.
  final http.Client _http = http.Client();

  /// Diskda bor fayllar — har safar fayl tizimiga murojaat qilmaslik uchun.
  final Set<String> _present = {};

  /// Ayni paytda yuklanayotganlar; bitta fayl ikki marta so'ralmasin.
  final Map<String, Future<String?>> _inFlight = {};

  static MediaStore? _instance;

  static Future<MediaStore> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/media');
    if (!await dir.exists()) await dir.create(recursive: true);
    final store = MediaStore._(dir);
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          store._present.add(entity.uri.pathSegments.last);
        }
      }
    } catch (e) {
      debugPrint('MEDIA_STORE ro\'yxatlashda xato: $e');
    }
    _instance = store;
    return store;
  }

  /// Chizish paytida ishlatiladigan sinxron yordamchi: do'kon hali
  /// ochilmagan bo'lsa null qaytaradi va tarmoqdan ko'rsatiladi.
  static String? localFor(String? serverPath) =>
      _instance?.localPath(serverPath);

  /// Akkaunt o'chirilganda qurilmadagi barcha media nusxalari ketadi.
  static Future<void> clearAll() async {
    final store = _instance;
    _instance = null;
    if (store == null) return;
    try {
      if (await store._dir.exists()) await store._dir.delete(recursive: true);
    } catch (e) {
      debugPrint('MEDIA_STORE clearAll xatosi: $e');
    }
  }

  static String _nameFor(String serverPath) {
    final cleaned = serverPath.split('?').first.replaceAll('\\', '/');
    final base = cleaned.split('/').where((s) => s.isNotEmpty).toList();
    return base.isEmpty ? cleaned : base.last;
  }

  /// Fayl allaqachon yuklab olinganmi? Sinxron — chizish paytida ishlatiladi.
  String? localPath(String? serverPath) {
    if (serverPath == null || serverPath.trim().isEmpty) return null;
    final name = _nameFor(serverPath);
    if (!_present.contains(name)) return null;
    return '${_dir.path}/$name';
  }

  /// Faylni bir marta yuklab oladi va mahalliy yo'lini qaytaradi.
  Future<String?> ensureLocal(String? serverPath, String url) {
    if (serverPath == null || serverPath.trim().isEmpty || url.isEmpty) {
      return Future.value(null);
    }
    final existing = localPath(serverPath);
    if (existing != null) return Future.value(existing);

    final name = _nameFor(serverPath);
    final running = _inFlight[name];
    if (running != null) return running;

    final future = _download(name, url).whenComplete(() {
      _inFlight.remove(name);
    });
    _inFlight[name] = future;
    return future;
  }

  Future<String?> _download(String name, String url) async {
    try {
      final response = await _http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        // Fayl serverda yo'q (muddati o'tgan) — qayta urinmaymiz.
        return null;
      }
      final target = File('${_dir.path}/$name');
      final temp = File('${target.path}.tmp');
      await temp.writeAsBytes(response.bodyBytes, flush: true);
      await temp.rename(target.path);
      _present.add(name);
      return target.path;
    } catch (e) {
      debugPrint('MEDIA_STORE yuklashda xato ($name): $e');
      return null;
    }
  }
}
