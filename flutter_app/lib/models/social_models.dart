enum CommunityType { group, channel }

class ProfileDetails {
  const ProfileDetails({
    required this.username,
    required this.fullName,
    required this.phone,
    required this.bio,
    required this.avatar,
    required this.birthday,
  });

  final String username;
  final String fullName;
  final String phone;
  final String bio;
  final String? avatar;
  final String birthday;

  factory ProfileDetails.fromJson(Map<String, dynamic> json) {
    return ProfileDetails(
      username: (json['username'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['fullName'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      bio: (json['bio'] ?? '').toString(),
      avatar: json['avatar']?.toString(),
      birthday: (json['birthday'] ?? '').toString(),
    );
  }
}

class SimpleUser {
  const SimpleUser({
    this.id,
    required this.username,
    required this.fullName,
    this.avatar,
  });

  final int? id;
  final String username;
  final String fullName;
  final String? avatar;

  factory SimpleUser.fromJson(Map<String, dynamic> json) {
    final username = (json['username'] ?? '').toString();
    return SimpleUser(
      id: int.tryParse('${json['id'] ?? ''}'),
      username: username,
      fullName: (json['full_name'] ?? json['fullName'] ?? username).toString(),
      avatar: json['avatar']?.toString(),
    );
  }
}

class FriendStatus {
  const FriendStatus({
    required this.status,
    this.requestId,
  });

  final String status;
  final int? requestId;

  bool get isFriend => status == 'friends';
  bool get isSent => status == 'sent';
  bool get isReceived => status == 'received';
  bool get isNone => status == 'none';

  factory FriendStatus.fromJson(Map<String, dynamic> json) {
    return FriendStatus(
      status: (json['status'] ?? 'none').toString(),
      requestId: int.tryParse('${json['requestId'] ?? ''}'),
    );
  }
}

class FriendRequestItem {
  const FriendRequestItem({
    required this.id,
    required this.username,
    this.avatar,
    this.createdAt,
  });

  final int id;
  final String username;
  final String? avatar;
  final DateTime? createdAt;

  factory FriendRequestItem.fromJson(Map<String, dynamic> json) {
    return FriendRequestItem(
      id: int.tryParse('${json['id'] ?? ''}') ?? 0,
      username: (json['username'] ?? '').toString(),
      avatar: json['avatar']?.toString(),
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
    );
  }
}

class CommunityItem {
  const CommunityItem({
    required this.id,
    required this.type,
    required this.name,
    this.description,
    this.avatar,
    this.allowDownload = false,
    this.peopleCount = 0,
    this.createdAt,
  });

  final int id;
  final CommunityType type;
  final String name;
  final String? description;
  final String? avatar;
  final bool allowDownload;
  final int peopleCount;
  final DateTime? createdAt;

  String get typeLabel => type == CommunityType.group ? 'group' : 'channel';

  factory CommunityItem.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? 'group').toString();
    final type = rawType == 'channel' ? CommunityType.channel : CommunityType.group;
    return CommunityItem(
      id: int.tryParse('${json['id'] ?? ''}') ?? 0,
      type: type,
      name: (json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      avatar: json['avatar']?.toString(),
      allowDownload: json['allow_download'] == true,
      peopleCount: int.tryParse(
            '${json['memberCount'] ?? json['subscriberCount'] ?? json['member_count'] ?? json['subscriber_count'] ?? 0}',
          ) ??
          0,
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
    );
  }
}

class CommunityMessage {
  const CommunityMessage({
    required this.id,
    required this.username,
    required this.content,
    this.avatar,
    this.image,
    this.audio,
    this.createdAt,
  });

  final int id;
  final String username;
  final String content;
  final String? avatar;
  final String? image;
  final String? audio;
  final DateTime? createdAt;

  factory CommunityMessage.fromJson(Map<String, dynamic> json) {
    return CommunityMessage(
      id: int.tryParse('${json['id'] ?? ''}') ?? 0,
      username: (json['username'] ?? '').toString(),
      content: (json['content'] ?? json['message'] ?? '').toString(),
      avatar: json['avatar']?.toString(),
      image: json['image']?.toString(),
      audio: json['audio']?.toString(),
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
    );
  }
}
