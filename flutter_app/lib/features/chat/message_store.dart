import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/chat_models.dart';

/// Xabarlarning qurilmadagi doimiy nusxasi.
///
/// Server xabarlarni faqat 24 soat saqlaydi — undan keyin yagona nusxa shu
/// yerda qoladi. Har bir suhbat alohida JSON faylda: bitta suhbatni yozish
/// boshqalariga tegmaydi va fayl buzilsa ham faqat o'sha suhbat yo'qoladi.
///
/// shared_preferences ataylab ishlatilmadi — u har saqlashda butun blobni
/// qaytadan yozadi, xabarlar esa to'planib boradi.
class MessageStore {
  MessageStore._(this._dir, this._owner);

  final Directory _dir;
  final String _owner;

  /// Bir vaqtda bitta suhbat yozilsin — tez ketma-ket kelgan xabarlar
  /// bir-birining ustiga yozib yubormasin.
  final Map<String, Future<void>> _writes = {};

  /// [owner] — joriy foydalanuvchi. Bitta qurilmada bir necha akkaunt
  /// ishlatilsa, ularning tarixi aralashmasligi kerak.
  static Future<MessageStore> create(String owner) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/messages/${_safe(owner)}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return MessageStore._(dir, owner);
  }

  String get owner => _owner;

  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  File _fileFor(String peer) => File('${_dir.path}/${_safe(peer)}.json');

  Future<List<ChatMessage>> load(String peer) async {
    try {
      final file = _fileFor(peer);
      if (!await file.exists()) return const [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ChatMessage.fromApi(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('MESSAGE_STORE load($peer) xatosi: $e');
      return const [];
    }
  }

  Future<void> save(String peer, List<ChatMessage> messages) {
    // Oldingi yozuv tugagandan keyin navbatdagisi boshlanadi.
    final previous = _writes[peer] ?? Future<void>.value();
    final next = previous.then((_) => _write(peer, messages));
    _writes[peer] = next;
    return next;
  }

  /// Diskda saqlanadigan eng ko'p xabar soni.
  ///
  /// Har bir yozuv butun suhbatni qaytadan JSON ga o'giradi — cheklovsiz
  /// uzun suhbatda bu har yuborilgan xabarda megabaytlab ish demakdi.
  /// Eskiroq xabarlar kerak bo'lsa serverdan sahifalab yuklanadi.
  static const _maxStoredMessages = 500;

  Future<void> _write(String peer, List<ChatMessage> messages) async {
    try {
      final trimmed = messages.length > _maxStoredMessages
          ? messages.sublist(messages.length - _maxStoredMessages)
          : messages;
      final encoded = jsonEncode(trimmed.map(_toStorage).toList());
      // Avval vaqtinchalik faylga, keyin o'rniga qo'yamiz — yozish yarmida
      // ilova yopilsa, eski nusxa buzilmay qoladi.
      final target = _fileFor(peer);
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(target.path);
    } catch (e) {
      debugPrint('MESSAGE_STORE save($peer) xatosi: $e');
    }
  }

  Future<void> deleteConversation(String peer) async {
    try {
      final file = _fileFor(peer);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('MESSAGE_STORE delete($peer) xatosi: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      if (await _dir.exists()) await _dir.delete(recursive: true);
    } catch (e) {
      debugPrint('MESSAGE_STORE clearAll xatosi: $e');
    }
  }

  /// ChatMessage.fromApi tushunadigan ko'rinish — o'qishda o'sha parser
  /// ishlatiladi, shuning uchun kalitlar server formatiga mos.
  Map<String, dynamic> _toStorage(ChatMessage m) => {
        'id': m.id,
        'username': m.senderUsername,
        'full_name': m.senderName,
        'content': m.content,
        'avatar': m.senderAvatar,
        'image': m.image,
        'audio': m.audio,
        'video': m.video,
        'reply_to_username': m.replyToUsername,
        'reply_to_content': m.replyToContent,
        'created_at': m.createdAt?.toIso8601String(),
        'is_read': m.isRead,
      };

  /// Qurilmadagi va serverdan kelgan ro'yxatni birlashtiradi.
  ///
  /// Server faqat oxirgi 24 soatni qaytaradi, qurilmada esa undan oldingisi
  /// ham bor — shuning uchun ikkalasi qo'shiladi. Takrorlanishlar id bo'yicha
  /// olib tashlanadi; id yo'q bo'lsa (hali serverga yetmagan xabar) vaqt va
  /// matn bo'yicha solishtiriladi. Serverdagi nusxa ustun: o'qilgan belgisi
  /// unda yangiroq bo'lishi mumkin.
  static List<ChatMessage> merge(
    List<ChatMessage> local,
    List<ChatMessage> remote,
  ) {
    final byKey = <String, ChatMessage>{};
    String keyOf(ChatMessage m) => m.id != null
        ? 'id:${m.id}'
        : 'tmp:${m.senderUsername}|${m.createdAt?.toIso8601String()}|${m.content}';

    for (final m in local) {
      byKey[keyOf(m)] = m;
    }
    for (final m in remote) {
      byKey[keyOf(m)] = m;
    }

    final merged = byKey.values.toList()
      ..sort((a, b) {
        final at = a.createdAt;
        final bt = b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return -1;
        if (bt == null) return 1;
        return at.compareTo(bt);
      });
    return merged;
  }
}
