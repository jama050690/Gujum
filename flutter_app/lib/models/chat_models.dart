class InboxItem {
  const InboxItem({
    required this.username,
    required this.fullName,
    required this.avatar,
    required this.lastActive,
    required this.lastMessage,
    required this.lastMessageAt,
    this.lastSender,
    required this.unreadCount,
  });

  final String username;
  final String fullName;
  final String? avatar;
  final DateTime? lastActive;
  final String lastMessage;
  /// Oxirgi xabarni kim yozgan — ro'yxatda "Siz:" prefiksi uchun.
  final String? lastSender;
  final DateTime? lastMessageAt;
  final int unreadCount;

  InboxItem copyWith({
    String? username,
    String? fullName,
    String? avatar,
    DateTime? lastActive,
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
  }) {
    return InboxItem(
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      avatar: avatar ?? this.avatar,
      lastActive: lastActive ?? this.lastActive,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastSender: lastSender,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  factory InboxItem.fromJson(Map<String, dynamic> json) {
    final preview = (json['lastContent'] ?? '').toString().trim();
    final image = _normalizedAttachment(json['lastImage']);
    final audio = _normalizedAttachment(json['lastAudio']);
    final video = _normalizedAttachment(json['lastVideo']) ??
        (isVideoAttachmentPath(image) ? image : null);
    final resolvedImage = video == image ? null : image;
    final isImage = isImageAttachmentPath(resolvedImage);
    final isFile = resolvedImage != null && !isImage && video == null;
    final isLocation = isLocationMessage(preview);
    return InboxItem(
      username: (json['sender'] ?? json['username'] ?? '').toString(),
      fullName: (json['senderFullName'] ?? json['full_name'] ?? json['username'] ?? '').toString(),
      avatar: json['avatar']?.toString(),
      lastActive: _parseDate(json['lastActive']),
      lastMessage: preview.isNotEmpty
          ? (isLocation ? '[location]' : preview)
          : (video != null
              ? '[video]'
              : isImage
                  ? '[image]'
                  : audio != null
                      ? '[audio]'
                      : isFile
                          ? '[file]'
                          : ''),
      lastMessageAt: _parseDate(json['lastMessageTime']),
      lastSender: json['lastSender']?.toString(),
      unreadCount: int.tryParse('${json['unreadCount'] ?? 0}') ?? 0,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUsername,
    required this.senderName,
    required this.content,
    this.senderAvatar,
    this.image,
    this.audio,
    this.video,
    this.replyToUsername,
    this.replyToContent,
    this.createdAt,
    this.isRead = false,
  });

  final int? id;
  final String senderUsername;
  final String senderName;
  final String content;
  final String? senderAvatar;
  final String? image;
  final String? audio;
  final String? video;
  final String? replyToUsername;
  final String? replyToContent;
  final DateTime? createdAt;
  final bool isRead;

  ChatMessage copyWith({
    int? id,
    String? senderUsername,
    String? senderName,
    String? content,
    String? senderAvatar,
    String? image,
    String? audio,
    String? video,
    String? replyToUsername,
    String? replyToContent,
    DateTime? createdAt,
    bool? isRead,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderUsername: senderUsername ?? this.senderUsername,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      image: image ?? this.image,
      audio: audio ?? this.audio,
      video: video ?? this.video,
      replyToUsername: replyToUsername ?? this.replyToUsername,
      replyToContent: replyToContent ?? this.replyToContent,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
    );
  }

  factory ChatMessage.fromApi(Map<String, dynamic> json) {
    final sender = (json['username'] ?? json['user'] ?? '').toString();
    final rawContent = (json['content'] ?? json['message'] ?? '').toString();
    final image = _normalizedAttachment(json['image']);
    final video = _normalizedAttachment(json['video']) ??
        (isVideoAttachmentPath(image) ? image : null);
    final resolvedImage = video == image ? null : image;
    return ChatMessage(
      id: int.tryParse('${json['id'] ?? ''}'),
      senderUsername: sender,
      senderName: (json['full_name'] ?? json['senderFullName'] ?? sender).toString(),
      content: rawContent,
      senderAvatar: json['avatar']?.toString(),
      image: resolvedImage,
      audio: _normalizedAttachment(json['audio']),
      video: video,
      replyToUsername: json['reply_to_username']?.toString() ?? json['replyTo']?['username']?.toString(),
      replyToContent: json['reply_to_content']?.toString() ?? json['replyTo']?['content']?.toString(),
      createdAt: _parseDate(json['created_at']),
      isRead: json['is_read'] == true || json['read'] == true,
    );
  }
}

class SearchUser {
  const SearchUser({
    required this.username,
    required this.fullName,
    this.avatar,
  });

  final String username;
  final String fullName;
  final String? avatar;

  factory SearchUser.fromJson(Map<String, dynamic> json) {
    final username = (json['username'] ?? '').toString();
    return SearchUser(
      username: username,
      fullName: (json['full_name'] ?? username).toString(),
      avatar: json['avatar']?.toString(),
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString())?.toLocal();
}

String? _normalizedAttachment(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') {
    return null;
  }
  return text;
}

bool isVideoAttachmentPath(String? value) {
  if (value == null || value.trim().isEmpty) {
    return false;
  }

  final sanitized = value.toLowerCase().split('?').first;
  for (final extension in const [
    '.mp4',
    '.mov',
    '.avi',
    '.webm',
    '.mkv',
    '.3gp',
    '.m4v',
  ]) {
    if (sanitized.endsWith(extension)) {
      return true;
    }
  }
  return false;
}

bool isImageAttachmentPath(String? value) {
  if (value == null || value.trim().isEmpty) {
    return false;
  }

  final sanitized = value.toLowerCase().split('?').first;
  for (final extension in const [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.heic',
    '.heif',
    '.bmp',
  ]) {
    if (sanitized.endsWith(extension)) {
      return true;
    }
  }
  return false;
}

const String _locationMessagePrefix = '__LOCATION__:';

bool isLocationMessage(String? value) {
  if (value == null || value.trim().isEmpty) {
    return false;
  }
  return value.trim().startsWith(_locationMessagePrefix);
}
