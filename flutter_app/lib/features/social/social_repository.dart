import 'package:http/http.dart' as http;

import '../../core/network/api_client.dart';
import '../../models/social_models.dart';

class SocialRepository {
  SocialRepository({
    required ApiClient apiClient,
  }) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<ProfileDetails> fetchProfile(String username) async {
    final response = await _apiClient.getJson('/api/users/profile/$username');
    return ProfileDetails.fromJson(response as Map<String, dynamic>);
  }

  Future<void> updateProfile({
    required String fullName,
    required String phone,
    required String bio,
    required String birthday,
  }) async {
    await _apiClient.multipartPut(
      '/api/users/profile',
      authenticated: true,
      fields: {
        'full_name': fullName,
        'phone': phone,
        'bio': bio,
        'birthday': birthday,
      },
    );
  }

  /// Faqat telefon raqamini saqlaydi — backend yuborilmagan maydonlarga
  /// tegmaydi, shuning uchun profilning qolgan qismi o'zgarmaydi.
  /// Yangi profil rasmini yuklaydi va serverdagi yo'lini qaytaradi.
  Future<String?> uploadAvatar(String filePath) async {
    final response = await _apiClient.multipartPut(
      '/api/users/profile',
      authenticated: true,
      files: [await http.MultipartFile.fromPath('avatar', filePath)],
    );
    if (response is Map) {
      return response['avatar']?.toString();
    }
    return null;
  }

  /// Akkauntni butunlay o'chiradi. Sabab ixtiyoriy va shaxssiz saqlanadi.
  Future<void> deleteAccount({String? reason, String? comment}) async {
    await _apiClient.deleteJson(
      '/api/account',
      authenticated: true,
      body: {
        if (reason != null) 'reason': reason,
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      },
    );
  }

  Future<void> saveFullName(String fullName) async {
    await _apiClient.multipartPut(
      '/api/users/profile',
      authenticated: true,
      fields: {'full_name': fullName},
    );
  }

  Future<void> savePhone(String phone, {bool? fromSim}) async {
    await _apiClient.multipartPut(
      '/api/users/profile',
      authenticated: true,
      fields: {
        'phone': phone,
        if (fromSim != null) 'phone_from_sim': fromSim.toString(),
      },
    );
  }

  Future<List<SimpleUser>> searchUsers(String query) async {
    final response = await _apiClient.getJson(
      '/api/users/search',
      query: {'q': query},
      authenticated: true,
    );
    return (response as List<dynamic>)
        .map((item) => SimpleUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<SimpleUser>> fetchPhoneContacts(List<String> phones) async {
    final response = await _apiClient.postJson(
      '/api/users/phone-contacts',
      authenticated: true,
      body: {'phones': phones},
    );
    return (response as List<dynamic>)
        .map((item) => SimpleUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<SimpleUser>> fetchFriends() async {
    final response = await _apiClient.getJson('/api/friends', authenticated: true);
    return (response as List<dynamic>)
        .map((item) => SimpleUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<FriendRequestItem>> fetchFriendRequests() async {
    final response = await _apiClient.getJson('/api/friends/requests', authenticated: true);
    return (response as List<dynamic>)
        .map((item) => FriendRequestItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<FriendStatus> fetchFriendStatus(String username) async {
    final response = await _apiClient.getJson(
      '/api/friends/status/$username',
      authenticated: true,
    );
    return FriendStatus.fromJson(response as Map<String, dynamic>);
  }

  Future<void> sendFriendRequest(String targetUsername) async {
    await _apiClient.postJson(
      '/api/friends/request',
      authenticated: true,
      body: {'targetUsername': targetUsername},
    );
  }

  Future<void> acceptFriendRequest(int requestId) async {
    await _apiClient.postJson(
      '/api/friends/accept',
      authenticated: true,
      body: {'requestId': requestId},
    );
  }

  Future<void> rejectFriendRequest(int requestId) async {
    await _apiClient.postJson(
      '/api/friends/reject',
      authenticated: true,
      body: {'requestId': requestId},
    );
  }

  Future<List<SimpleUser>> fetchBlockedUsers() async {
    final response = await _apiClient.getJson('/api/block', authenticated: true);
    return (response as List<dynamic>)
        .map((item) => SimpleUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> blockUser(String username) async {
    await _apiClient.postJson(
      '/api/block',
      authenticated: true,
      body: {'targetUsername': username},
    );
  }

  Future<void> reportSpam(String username, {String? reason}) async {
    await _apiClient.postJson(
      '/api/spam/report',
      authenticated: true,
      body: {
        'targetUsername': username,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  Future<void> unblockUser(String username) async {
    await _apiClient.deleteJson('/api/block/$username', authenticated: true);
  }

}
