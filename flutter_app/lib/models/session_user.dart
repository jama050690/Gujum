class SessionUser {
  const SessionUser({
    required this.username,
    this.fullName,
    this.phone,
    this.birthday,
    this.bio,
    this.avatar,
  });

  final String username;
  final String? fullName;
  final String? phone;
  final String? birthday;
  final String? bio;
  final String? avatar;

  String get displayName => (fullName != null && fullName!.trim().isNotEmpty) ? fullName! : username;

  Map<String, dynamic> toJson() => {
        'username': username,
        'fullName': fullName,
        'phone': phone,
        'birthday': birthday,
        'bio': bio,
        'avatar': avatar,
      };

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    return SessionUser(
      username: (json['username'] ?? '').toString(),
      fullName: json['fullName']?.toString() ?? json['full_name']?.toString(),
      phone: json['phone']?.toString(),
      birthday: json['birthday']?.toString(),
      bio: json['bio']?.toString(),
      avatar: json['avatar']?.toString(),
    );
  }
}
