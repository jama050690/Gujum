import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../models/chat_models.dart';
import '../../l10n/app_strings.dart';

class ChatRepository {
  ChatRepository({
    required ApiClient apiClient,
  }) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Qo'ng'iroqlar tarixi — hammasi, faqat oxirgisi emas.
  ///
  /// Ilgari Flutter tomonda bu so'rov umuman ishlatilmasdi: "Qo'ng'iroqlar"
  /// sahifasi inbox ro'yxatini filtrlardi, ya'ni qo'ng'iroq faqat suhbatdagi
  /// eng oxirgi xabar bo'lsagina ko'rinardi.
  Future<List<CallHistoryEntry>> fetchCallHistory(String username) async {
    final response = await _apiClient.getJson(
      '/api/calls/history',
      query: {'username': username},
      authenticated: true,
    );
    return (response as List<dynamic>)
        .map((item) =>
            CallHistoryEntry.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<InboxItem>> fetchInbox(
    String username, {
    DateTime? before,
    int? limit,
  }) async {
    final response = await _apiClient.getJson(
      '/api/inbox',
      query: {
        'username': username,
        if (before != null) 'before': before.toIso8601String(),
        if (limit != null) 'limit': '$limit',
      },
      authenticated: true,
    );
    return (response as List<dynamic>)
        .map((item) => InboxItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatMessage>> fetchMessages({
    required String user1,
    required String user2,
    DateTime? before,
    int? limit,
  }) async {
    final response = await _apiClient.getJson(
      '/api/messages',
      query: {
        'user1': user1,
        'user2': user2,
        // Kursor: shu vaqtdan oldingi xabarlar. OFFSET emas — chuqurlashgan
        // sari sekinlashmaydi va yangi xabar kelganda qatorlar siljib
        // takrorlanmaydi.
        if (before != null) 'before': before.toIso8601String(),
        if (limit != null) 'limit': '$limit',
      },
      authenticated: true,
    );
    return (response as List<dynamic>)
        .map((item) => ChatMessage.fromApi(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> markRead({
    required String username,
    required String chatWith,
  }) async {
    await _apiClient.postJson(
      '/api/messages/mark-read',
      body: {
        'username': username,
        'chatWith': chatWith,
      },
      authenticated: true,
    );
  }

  /// [forEveryone] false bo'lsa tarix faqat shu foydalanuvchidan yashiriladi.
  Future<void> clearChatHistory(String username,
      {bool forEveryone = false}) async {
    await _apiClient.deleteJson(
      '/api/users/chat/$username/history',
      authenticated: true,
      body: {'forEveryone': forEveryone},
    );
  }

  Future<void> deleteChat(String username) async {
    await _apiClient.deleteJson(
      '/api/users/chat/$username',
      authenticated: true,
    );
  }

  Future<List<SearchUser>> searchUsers(String query) async {
    final response = await _apiClient.getJson(
      '/api/users/search',
      query: {'q': query},
      authenticated: true,
    );

    return (response as List<dynamic>)
        .map((item) => SearchUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }


  Future<ChatMessage> updateMessage({
    required int id,
    required String message,
  }) async {
    final response = await _apiClient.putJson(
      '/api/messages/$id',
      body: {'message': message},
      authenticated: true,
    );

    return ChatMessage.fromApi(response as Map<String, dynamic>);
  }

  /// Xabarlarni o'chirish. [forEveryone] true bo'lsa suhbatdoshda ham
  /// yo'qoladi (faqat o'z xabarlaringiz uchun ishlaydi).
  Future<List<int>> deleteMessages(List<int> ids,
      {required bool forEveryone}) async {
    final response = await _apiClient.postJson(
      '/api/messages/delete',
      authenticated: true,
      body: {'ids': ids, 'forEveryone': forEveryone},
    );
    final deleted = (response as Map<String, dynamic>?)?['deleted'] as List?;
    return deleted?.map((e) => int.parse('$e')).toList() ?? const [];
  }

  Future<ChatMessage> sendDirectMessage({
    required String receiver,
    String message = '',
    String? image,
    String? audio,
    String? video,
    Map<String, String?>? replyTo,
    String? clientMsgId,
  }) async {
    final response = await _apiClient.postJson(
      '/api/messages',
      body: {
        'receiver': receiver,
        'message': message,
        'image': image,
        'audio': audio,
        'video': video,
        if (replyTo != null)
          'replyTo': {
            'username': replyTo['username'],
            'content': replyTo['content'],
          },
        'clientMsgId': ?clientMsgId,
      },
      authenticated: true,
    );

    return ChatMessage.fromApi(response as Map<String, dynamic>);
  }

  Future<String> uploadMedia(String filePath) async {
    final response = await _apiClient.multipartPost(
      '/api/upload',
      files: [
        await http.MultipartFile.fromPath('image', filePath),
      ],
      authenticated: true,
    );
    final path = (response as Map<String, dynamic>)['path']?.toString();
    if (path == null || path.isEmpty) {
      throw ApiException(
        message: AppStrings.t('upload_failed'),
        statusCode: 0,
        payload: response,
      );
    }
    return path;
  }

  Future<String> uploadPickedMedia(PlatformFile file) async {
    final response = await _apiClient.multipartPost(
      '/api/upload',
      files: [
        await _multipartFileFromPlatformFile('image', file),
      ],
      authenticated: true,
    );
    final path = (response as Map<String, dynamic>)['path']?.toString();
    if (path == null || path.isEmpty) {
      throw ApiException(
        message: AppStrings.t('upload_failed'),
        statusCode: 0,
        payload: response,
      );
    }
    return path;
  }

  Future<String> uploadXFileMedia(XFile file) async {
    final response = await _apiClient.multipartPost(
      '/api/upload',
      files: [
        await _multipartFileFromXFile('image', file),
      ],
      authenticated: true,
    );
    final path = (response as Map<String, dynamic>)['path']?.toString();
    if (path == null || path.isEmpty) {
      throw ApiException(
        message: AppStrings.t('upload_failed'),
        statusCode: 0,
        payload: response,
      );
    }
    return path;
  }

  Future<String> uploadAudio(String filePath) async {
    final response = await _apiClient.multipartPost(
      '/api/upload-audio',
      files: [
        await http.MultipartFile.fromPath('audio', filePath),
      ],
      authenticated: true,
    );
    final path = (response as Map<String, dynamic>)['path']?.toString();
    if (path == null || path.isEmpty) {
      throw ApiException(
        message: AppStrings.t('upload_failed'),
        statusCode: 0,
        payload: response,
      );
    }
    return path;
  }

  Future<String> uploadPickedAudio(PlatformFile file) async {
    final response = await _apiClient.multipartPost(
      '/api/upload-audio',
      files: [
        await _multipartFileFromPlatformFile('audio', file),
      ],
      authenticated: true,
    );
    final path = (response as Map<String, dynamic>)['path']?.toString();
    if (path == null || path.isEmpty) {
      throw ApiException(
        message: AppStrings.t('upload_failed'),
        statusCode: 0,
        payload: response,
      );
    }
    return path;
  }

  Future<String> uploadXFileAudio(XFile file) async {
    final response = await _apiClient.multipartPost(
      '/api/upload-audio',
      files: [
        await _multipartFileFromXFile('audio', file),
      ],
      authenticated: true,
    );
    final path = (response as Map<String, dynamic>)['path']?.toString();
    if (path == null || path.isEmpty) {
      throw ApiException(
        message: AppStrings.t('upload_failed'),
        statusCode: 0,
        payload: response,
      );
    }
    return path;
  }

  Future<String> uploadVideo(String filePath) async {
    final response = await _apiClient.multipartPost(
      '/api/upload-video',
      files: [
        await http.MultipartFile.fromPath('video', filePath),
      ],
      authenticated: true,
    );
    final path = (response as Map<String, dynamic>)['path']?.toString();
    if (path == null || path.isEmpty) {
      throw ApiException(
        message: AppStrings.t('upload_failed'),
        statusCode: 0,
        payload: response,
      );
    }
    return path;
  }

  Future<String> uploadPickedVideo(PlatformFile file) async {
    final response = await _apiClient.multipartPost(
      '/api/upload-video',
      files: [
        await _multipartFileFromPlatformFile('video', file),
      ],
      authenticated: true,
    );
    final path = (response as Map<String, dynamic>)['path']?.toString();
    if (path == null || path.isEmpty) {
      throw ApiException(
        message: AppStrings.t('upload_failed'),
        statusCode: 0,
        payload: response,
      );
    }
    return path;
  }

  Future<String> uploadXFileVideo(XFile file) async {
    final response = await _apiClient.multipartPost(
      '/api/upload-video',
      files: [
        await _multipartFileFromXFile('video', file),
      ],
      authenticated: true,
    );
    final path = (response as Map<String, dynamic>)['path']?.toString();
    if (path == null || path.isEmpty) {
      throw ApiException(
        message: AppStrings.t('upload_failed'),
        statusCode: 0,
        payload: response,
      );
    }
    return path;
  }

  Future<http.MultipartFile> _multipartFileFromXFile(
    String field,
    XFile file,
  ) async {
    final name = file.name.trim().isNotEmpty ? file.name : 'upload.bin';
    final path = file.path.trim();

    if (kIsWeb || path.isEmpty || path.toLowerCase().startsWith('blob:')) {
      final bytes = await file.readAsBytes();
      return http.MultipartFile.fromBytes(field, bytes, filename: name);
    }

    // Stream content:// URIs to avoid loading large files into memory
    if (path.toLowerCase().startsWith('content://')) {
      final length = await file.length();
      return http.MultipartFile(field, file.openRead(), length, filename: name);
    }

    return http.MultipartFile.fromPath(field, path, filename: name);
  }

  Future<http.MultipartFile> _multipartFileFromPlatformFile(
    String field,
    PlatformFile file,
  ) async {
    final path = file.path;
    if (!kIsWeb &&
        path != null &&
        path.isNotEmpty &&
        !path.toLowerCase().startsWith('content://') &&
        !path.toLowerCase().startsWith('blob:')) {
      return http.MultipartFile.fromPath(
        field,
        path,
        filename: file.name,
      );
    }

    if (file.bytes != null) {
      return http.MultipartFile.fromBytes(
        field,
        file.bytes!,
        filename: file.name,
      );
    }

    final stream = file.readStream;
    if (stream != null && file.size > 0) {
      return http.MultipartFile(
        field,
        stream,
        file.size,
        filename: file.name,
      );
    }

    throw ApiException(
      message: AppStrings.t('file_not_readable'),
      statusCode: 0,
      payload: file.name,
    );
  }
}
