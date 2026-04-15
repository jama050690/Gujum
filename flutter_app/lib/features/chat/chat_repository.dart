import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../../core/network/api_client.dart';
import '../../models/chat_models.dart';

class ChatRepository {
  ChatRepository({
    required ApiClient apiClient,
  }) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<InboxItem>> fetchInbox(String username) async {
    final response = await _apiClient.getJson(
      '/api/inbox',
      query: {'username': username},
      authenticated: true,
    );

    return (response as List<dynamic>)
        .map((item) => InboxItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatMessage>> fetchMessages({
    required String user1,
    required String user2,
  }) async {
    final response = await _apiClient.getJson(
      '/api/messages',
      query: {
        'user1': user1,
        'user2': user2,
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

  Future<void> clearChatHistory(String username) async {
    await _apiClient.deleteJson(
      '/api/users/chat/$username/history',
      authenticated: true,
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

  Future<void> deleteMessage(int id) async {
    await _apiClient.deleteJson(
      '/api/messages/$id',
      authenticated: true,
    );
  }

  Future<ChatMessage> sendDirectMessage({
    required String receiver,
    String message = '',
    String? image,
    String? audio,
    String? video,
    Map<String, String?>? replyTo,
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
        message: 'Upload failed',
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
        message: 'Upload failed',
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
        message: 'Upload failed',
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
        message: 'Upload failed',
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
        message: 'Upload failed',
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
        message: 'Upload failed',
        statusCode: 0,
        payload: response,
      );
    }
    return path;
  }

  Future<http.MultipartFile> _multipartFileFromPlatformFile(
    String field,
    PlatformFile file,
  ) async {
    final path = file.path;
    if (path != null &&
        path.isNotEmpty &&
        !path.toLowerCase().startsWith('content://')) {
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
      message: 'Selected file is not readable',
      statusCode: 0,
      payload: file.name,
    );
  }
}
