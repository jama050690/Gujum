import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/network/session_store.dart';
import '../../core/network/socket_service.dart';
import '../../models/chat_models.dart';
import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';
import 'chat_repository.dart';

class ChatController extends ChangeNotifier {
  ChatController({
    required ChatRepository chatRepository,
    required SocketService socketService,
    required AuthController authController,
    required SettingsController settingsController,
    required SessionStore sessionStore,
  })  : _chatRepository = chatRepository,
        _socketService = socketService,
        _authController = authController,
        _settingsController = settingsController,
        _sessionStore = sessionStore {
    _authController.addListener(_handleDependencyChange);
    _settingsController.addListener(_handleDependencyChange);
    _socketSub = _socketService.packets.listen(_handleSocketPacket);
  }

  final ChatRepository _chatRepository;
  final SocketService _socketService;
  final AuthController _authController;
  final SettingsController _settingsController;
  final SessionStore _sessionStore;

  late final StreamSubscription<SocketPacket> _socketSub;

  List<InboxItem> _inbox = const [];
  List<ChatMessage> _messages = const [];
  InboxItem? _activeChat;
  Set<String> _onlineUsers = <String>{};
  Map<String, DateTime?> _lastActiveUsers = const <String, DateTime?>{};
  bool _loadingInbox = false;
  bool _loadingMessages = false;
  bool _searching = false;
  String? _connectionLabel;
  String? _boundUsername;
  String? _boundBaseUrl;
  String? _boundCookie;

  List<InboxItem> get inbox => _inbox;
  List<ChatMessage> get messages => _messages;
  InboxItem? get activeChat => _activeChat;
  Set<String> get onlineUsers => _onlineUsers;
  DateTime? lastActiveFor(String username) => _lastActiveUsers[username];
  bool get loadingInbox => _loadingInbox;
  bool get loadingMessages => _loadingMessages;
  bool get searching => _searching;
  String? get connectionLabel => _connectionLabel;
  bool get isConnected => _socketService.isConnected;

  Future<void> bootstrap() => _syncSession(force: true);

  Future<List<SearchUser>> searchUsers(String query) async {
    if (query.trim().isEmpty) {
      return const [];
    }
    _searching = true;
    notifyListeners();
    try {
      final currentUsername = _authController.user?.username;
      final results = await _chatRepository.searchUsers(query.trim());
      if (currentUsername == null || currentUsername.isEmpty) {
        return results;
      }
      return results
          .where((item) => item.username != currentUsername)
          .toList(growable: false);
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  Future<void> loadInbox() async {
    final user = _authController.user;
    if (user == null) {
      return;
    }

    _loadingInbox = true;
    notifyListeners();
    try {
      _inbox = (await _chatRepository.fetchInbox(user.username))
          .where((item) => item.username != user.username)
          .toList(growable: false);
      final seededLastActive = <String, DateTime?>{
        for (final item in _inbox) item.username: item.lastActive,
      };
      _lastActiveUsers = <String, DateTime?>{
        ...seededLastActive,
        ..._lastActiveUsers,
      };
      if (_activeChat != null) {
        final index =
            _inbox.indexWhere((item) => item.username == _activeChat!.username);
        if (index >= 0) {
          _activeChat = _inbox[index];
        }
      }
    } finally {
      _loadingInbox = false;
      notifyListeners();
    }
  }

  Future<void> openChat(InboxItem item) async {
    final user = _authController.user;
    if (user == null) {
      return;
    }

    _activeChat = item.copyWith(unreadCount: 0);
    _loadingMessages = true;
    notifyListeners();

    try {
      _messages = await _chatRepository.fetchMessages(
        user1: user.username,
        user2: item.username,
      );
      await _chatRepository.markRead(
          username: user.username, chatWith: item.username);
      _socketService.emit('MESSAGES_READ', {
        'reader': user.username,
        'sender': item.username,
      });
      _updateInboxPreview(peer: item.username, unreadCount: 0);
    } finally {
      _loadingMessages = false;
      notifyListeners();
    }
  }

  Future<void> clearChatHistory(String username) async {
    await _chatRepository.clearChatHistory(username);

    final current = List<InboxItem>.from(_inbox);
    final index = current.indexWhere((item) => item.username == username);
    if (index < 0) {
      return;
    }

    current[index] = current[index].copyWith(
      lastMessage: '',
      lastMessageAt: null,
      unreadCount: 0,
    );
    _inbox = current;
    if (_activeChat?.username == username) {
      _activeChat = current[index];
      _messages = const [];
    }
    notifyListeners();
  }

  Future<void> deleteChat(String username) async {
    await _chatRepository.deleteChat(username);
    removeChat(username);
  }

  void removeChat(String username) {
    _inbox = _inbox
        .where((item) => item.username != username)
        .toList(growable: false);
    if (_activeChat?.username == username) {
      _activeChat = null;
      _messages = const [];
    }
    notifyListeners();
  }

  void markChatUnread(String username, {int count = 1}) {
    final current = List<InboxItem>.from(_inbox);
    final index = current.indexWhere((item) => item.username == username);
    if (index < 0) {
      return;
    }

    current[index] = current[index].copyWith(
      unreadCount: current[index].unreadCount > 0
          ? current[index].unreadCount
          : (count < 1 ? 1 : (count > 999 ? 999 : count)),
    );
    _inbox = current;
    notifyListeners();
  }

  void closeChat() {
    _activeChat = null;
    _messages = const [];
    notifyListeners();
  }

  Future<void> startChatWith(SearchUser user) async {
    if (user.username == _authController.user?.username) {
      return;
    }
    await openChat(
      InboxItem(
        username: user.username,
        fullName: user.fullName,
        avatar: user.avatar,
        lastMessage: '',
        lastMessageAt: null,
        unreadCount: 0,
      ),
    );
  }

  Future<bool> sendMessage({
    String? receiver,
    String message = '',
    String? image,
    String? audio,
    String? video,
    Map<String, String?>? replyTo,
  }) async {
    final currentUser = _authController.user;
    final targetUsername = receiver ?? _activeChat?.username;
    final text = message.trim();
    final hasMedia = (image?.trim().isNotEmpty ?? false) ||
        (audio?.trim().isNotEmpty ?? false) ||
        (video?.trim().isNotEmpty ?? false);
    if (currentUser == null ||
        targetUsername == null ||
        (text.isEmpty && !hasMedia)) {
      return false;
    }

    if (!_socketService.isConnected) {
      try {
        final sentMessage = await _chatRepository.sendDirectMessage(
          receiver: targetUsername,
          message: text,
          image: image,
          audio: audio,
          video: video,
          replyTo: replyTo,
        );
        _consumeIncomingMessage(
          sentMessage,
          <String, dynamic>{
            'receiver': targetUsername,
          },
        );
        return true;
      } catch (_) {
        _connectionLabel = 'disconnected';
        notifyListeners();
        return false;
      }
    }

    _socketService.emit('NEW_MESSAGE', {
      'user': currentUser.username,
      'receiver': targetUsername,
      'message': text,
      'image': image,
      'audio': audio,
      'video': video,
      'replyTo': replyTo,
      'avatar': currentUser.avatar,
    });
    return true;
  }

  Future<ChatMessage?> updateActiveMessage({
    required int id,
    required String message,
  }) async {
    final updated = await _chatRepository.updateMessage(id: id, message: message);
    _messages = _messages
        .map((item) => item.id == id ? updated : item)
        .toList(growable: false);
    _refreshInboxPreviewFromMessages();
    notifyListeners();
    return updated;
  }

  Future<void> deleteActiveMessage(int id) async {
    await _chatRepository.deleteMessage(id);
    _messages = _messages.where((item) => item.id != id).toList(growable: false);
    _refreshInboxPreviewFromMessages();
    notifyListeners();
  }

  Future<String> uploadMedia(String filePath) {
    return _chatRepository.uploadMedia(filePath);
  }

  Future<String> uploadPickedMedia(PlatformFile file) {
    return _chatRepository.uploadPickedMedia(file);
  }

  Future<String> uploadXFileMedia(XFile file) {
    return _chatRepository.uploadXFileMedia(file);
  }

  Future<String> uploadAudio(String filePath) {
    return _chatRepository.uploadAudio(filePath);
  }

  Future<String> uploadPickedAudio(PlatformFile file) {
    return _chatRepository.uploadPickedAudio(file);
  }

  Future<String> uploadXFileAudio(XFile file) {
    return _chatRepository.uploadXFileAudio(file);
  }

  Future<String> uploadVideo(String filePath) {
    return _chatRepository.uploadVideo(filePath);
  }

  Future<String> uploadPickedVideo(PlatformFile file) {
    return _chatRepository.uploadPickedVideo(file);
  }

  Future<String> uploadXFileVideo(XFile file) {
    return _chatRepository.uploadXFileVideo(file);
  }

  @override
  void dispose() {
    _authController.removeListener(_handleDependencyChange);
    _settingsController.removeListener(_handleDependencyChange);
    _socketSub.cancel();
    _socketService.dispose();
    super.dispose();
  }

  void _handleDependencyChange() {
    _syncSession();
  }

  Future<void> _syncSession({bool force = false}) async {
    final user = _authController.user;
    final baseUrl = _settingsController.baseUrl;
    final cookie = _sessionStore.cookie;

    if (user == null) {
      _socketService.disconnect();
      _boundUsername = null;
      _boundBaseUrl = null;
      _boundCookie = null;
      _inbox = const [];
      _messages = const [];
      _activeChat = null;
      _onlineUsers = <String>{};
      _lastActiveUsers = const <String, DateTime?>{};
      notifyListeners();
      return;
    }

    final needsReconnect = force ||
        _boundUsername != user.username ||
        _boundBaseUrl != baseUrl ||
        _boundCookie != cookie;

    if (needsReconnect) {
      _boundUsername = user.username;
      _boundBaseUrl = baseUrl;
      _boundCookie = cookie;
      _socketService.connect(
        baseUrl: AppConfig.socketBaseUrl(baseUrl),
        path: AppConfig.socketPath(baseUrl),
        username: user.username,
        cookie: cookie,
      );
      await loadInbox();
      if (_activeChat != null) {
        await openChat(_activeChat!);
      }
    }
  }

  void _handleSocketPacket(SocketPacket packet) {
    switch (packet.event) {
      case 'connect':
        _connectionLabel = 'connected';
        notifyListeners();
        break;
      case 'disconnect':
      case 'connect_error':
      case 'error':
        _connectionLabel = 'disconnected';
        notifyListeners();
        break;
      case 'ONLINE_USERS_LIST':
        final users =
            (packet.payload as List<dynamic>).cast<Map<dynamic, dynamic>>();
        _onlineUsers = users
            .where((item) => item['online'] == true)
            .map((item) => item['username'].toString())
            .toSet();
        _lastActiveUsers = <String, DateTime?>{
          for (final item in users)
            item['username'].toString(): _parseLastActive(item['lastActive']),
        };
        notifyListeners();
        break;
      case 'USER_STATUS_CHANGED':
        final payload = Map<String, dynamic>.from(packet.payload as Map);
        final username = payload['username']?.toString();
        if (username == null || username.isEmpty) {
          break;
        }
        final next = <String>{..._onlineUsers};
        if (payload['online'] == true) {
          next.add(username);
        } else {
          next.remove(username);
        }
        _onlineUsers = next;
        _lastActiveUsers = <String, DateTime?>{
          ..._lastActiveUsers,
          username: payload['online'] == true
              ? null
              : _parseLastActive(payload['lastActive']) ?? DateTime.now(),
        };
        notifyListeners();
        break;
      case 'NEW_MESSAGE':
        final payload = Map<String, dynamic>.from(packet.payload as Map);
        final message = ChatMessage.fromApi(payload);
        _consumeIncomingMessage(message, payload);
        break;
      case 'MESSAGE_DELETED':
        final payload = Map<String, dynamic>.from(packet.payload as Map);
        final messageId = int.tryParse('${payload['messageId'] ?? ''}');
        if (messageId == null) {
          break;
        }
        _messages = _messages
            .where((item) => item.id != messageId)
            .toList(growable: false);
        notifyListeners();
        break;
      case 'MESSAGES_READ':
        final payload = Map<String, dynamic>.from(packet.payload as Map);
        final reader = payload['reader']?.toString();
        if (reader == null || reader != _activeChat?.username) {
          break;
        }
        _messages = _messages
            .map(
              (message) =>
                  message.senderUsername == _authController.user?.username
                      ? message.copyWith(isRead: true)
                      : message,
            )
            .toList(growable: false);
        notifyListeners();
        break;
    }
  }

  void _consumeIncomingMessage(ChatMessage message, Map<String, dynamic> raw) {
    final currentUser = _authController.user;
    if (currentUser == null) {
      return;
    }

    final sender = message.senderUsername;
    final receiver = raw['receiver']?.toString();
    final peer = sender == currentUser.username ? receiver : sender;
    if (peer == null || peer.isEmpty || peer == currentUser.username) {
      return;
    }

    final unreadCount =
        (_activeChat?.username == peer || sender == currentUser.username)
            ? 0
            : 1;

    _updateInboxPreview(
      peer: peer,
      fullName: sender == currentUser.username
          ? _activeChat?.fullName
          : message.senderName,
      avatar: sender == currentUser.username
          ? _activeChat?.avatar
          : message.senderAvatar,
      preview: _messagePreview(message),
      at: message.createdAt ?? DateTime.now(),
      unreadIncrement: unreadCount,
    );

    if (_activeChat?.username == peer) {
      if (!_messages.any((item) => item.id != null && item.id == message.id)) {
        _messages = [..._messages, message];
      }
      if (sender != currentUser.username) {
        _chatRepository.markRead(
          username: currentUser.username,
          chatWith: peer,
        );
        _socketService.emit('MESSAGES_READ', {
          'reader': currentUser.username,
          'sender': peer,
        });
      }
    }

    notifyListeners();
  }

  void _updateInboxPreview({
    required String peer,
    String? fullName,
    String? avatar,
    String? preview,
    DateTime? at,
    int unreadIncrement = 0,
    int? unreadCount,
  }) {
    if (peer == _authController.user?.username) {
      return;
    }

    final current = List<InboxItem>.from(_inbox);
    final index = current.indexWhere((item) => item.username == peer);

    if (index >= 0) {
      final item = current[index];
      current[index] = item.copyWith(
        fullName: fullName ?? item.fullName,
        avatar: avatar ?? item.avatar,
        lastMessage: preview ?? item.lastMessage,
        lastMessageAt: at ?? item.lastMessageAt,
        unreadCount: unreadCount ?? item.unreadCount + unreadIncrement,
      );
    } else {
      current.add(
        InboxItem(
          username: peer,
          fullName: fullName ?? peer,
          avatar: avatar,
          lastMessage: preview ?? '',
          lastMessageAt: at,
          unreadCount: unreadCount ?? unreadIncrement,
        ),
      );
    }

    current.sort((a, b) {
      final left = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    _inbox = current;

    if (_activeChat?.username == peer) {
      _activeChat = _inbox.firstWhere((item) => item.username == peer);
    }
  }

  String _messagePreview(ChatMessage message) {
    if (message.content.trim().isNotEmpty) {
      return message.content.trim();
    }
    if (message.video != null && message.video!.isNotEmpty) {
      return '[video]';
    }
    if (message.image != null && message.image!.isNotEmpty) {
      return '[image]';
    }
    if (message.audio != null && message.audio!.isNotEmpty) {
      return '[audio]';
    }
    return '';
  }

  void _refreshInboxPreviewFromMessages() {
    final peer = _activeChat?.username;
    if (peer == null) {
      return;
    }

    final lastMessage = _messages.isEmpty ? null : _messages.last;
    final current = List<InboxItem>.from(_inbox);
    final index = current.indexWhere((item) => item.username == peer);
    if (index < 0) {
      return;
    }

    current[index] = current[index].copyWith(
      lastMessage: lastMessage == null ? '' : _messagePreview(lastMessage),
      lastMessageAt: lastMessage?.createdAt,
      unreadCount: 0,
    );
    current.sort((a, b) {
      final left = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    _inbox = current;
    final refreshedIndex = current.indexWhere((item) => item.username == peer);
    if (refreshedIndex >= 0) {
      _activeChat = current[refreshedIndex];
    }
  }

  DateTime? _parseLastActive(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    }
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
