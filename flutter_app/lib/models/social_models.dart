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
      birthday: (json['birthday'] ?? '').toString().split('T').first,
    );
  }
}

class SimpleUser {
  const SimpleUser({
    this.id,
    required this.username,
    required this.fullName,
    this.avatar,
    this.matchedPhone,
  });

  final int? id;
  final String username;
  final String fullName;
  final String? avatar;
  final String? matchedPhone;

  factory SimpleUser.fromJson(Map<String, dynamic> json) {
    final username = (json['username'] ?? '').toString();
    return SimpleUser(
      id: int.tryParse('${json['id'] ?? ''}'),
      username: username,
      fullName: (json['full_name'] ?? json['fullName'] ?? username).toString(),
      avatar: json['avatar']?.toString(),
      matchedPhone: json['matched_phone']?.toString(),
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

