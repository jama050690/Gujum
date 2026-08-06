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

  Future<List<CommunityItem>> fetchGroups(String username) async {
    final response = await _apiClient.getJson('/api/groups', query: {'username': username});
    return (response as List<dynamic>)
        .map((item) => CommunityItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<CommunityItem>> fetchChannels(String username) async {
    final response = await _apiClient.getJson('/api/channels', query: {'username': username});
    return (response as List<dynamic>)
        .map((item) => CommunityItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CommunityItem> createGroup({
    required String username,
    required String name,
    required bool allowDownload,
  }) async {
    final response = await _apiClient.postJson(
      '/api/groups',
      body: {
        'username': username,
        'name': name,
        'allow_download': allowDownload,
      },
    );
    final group = (response as Map<String, dynamic>)['group'] as Map<String, dynamic>;
    return CommunityItem.fromJson(group);
  }

  Future<CommunityItem> createChannel({
    required String username,
    required String name,
    required String description,
    required bool allowDownload,
  }) async {
    final response = await _apiClient.postJson(
      '/api/channels',
      body: {
        'username': username,
        'name': name,
        'description': description,
        'allow_download': allowDownload,
      },
    );
    final channel = (response as Map<String, dynamic>)['channel'] as Map<String, dynamic>;
    return CommunityItem.fromJson(channel);
  }

  Future<List<CommunityMessage>> fetchGroupMessages(int groupId) async {
    final response = await _apiClient.getJson('/api/groups/$groupId/messages');
    return (response as List<dynamic>)
        .map((item) => CommunityMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<CommunityMessage>> fetchChannelMessages(int channelId) async {
    final response = await _apiClient.getJson('/api/channels/$channelId/messages');
    return (response as List<dynamic>)
        .map((item) => CommunityMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<SimpleUser>> fetchGroupMembers(int groupId) async {
    final response = await _apiClient.getJson('/api/groups/$groupId/members');
    return (response as List<dynamic>)
        .map((item) => SimpleUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<SimpleUser>> fetchChannelSubscribers(int channelId) async {
    final response = await _apiClient.getJson('/api/channels/$channelId/subscribers');
    return (response as List<dynamic>)
        .map((item) => SimpleUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
