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
        'reason': ?reason,
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

  /// Raqamni saqlaydi va akkauntlar bog'langan bo'lsa `true` qaytaradi.
  ///
  /// Raqam boshqa akkauntga tegishli bo'lsa server o'sha akkauntga
  /// ulaydi va yangi sessiya beradi — bunday holatda klientdagi
  /// foydalanuvchi eskirgan bo'ladi va qaytadan olinishi kerak.
  Future<bool> savePhone(String phone, {bool? fromSim}) async {
    final response = await _apiClient.multipartPut(
      '/api/users/profile',
      authenticated: true,
      fields: {
        'phone': phone,
        if (fromSim != null) 'phone_from_sim': fromSim.toString(),
      },
    );
    return response is Map && response['linked'] == true;
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


  Future<void> unblockUser(String username) async {
    await _apiClient.deleteJson('/api/block/$username', authenticated: true);
  }

}
