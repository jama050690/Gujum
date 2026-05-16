import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
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
    _audioPlayer = AudioPlayer();
  }

  final ChatRepository _chatRepository;
  final SocketService _socketService;
  final AuthController _authController;
  final SettingsController _settingsController;
  final SessionStore _sessionStore;

  late final StreamSubscription<SocketPacket> _socketSub;
  late final AudioPlayer _audioPlayer;

  List<InboxItem> _inbox = const [];
  List<ChatMessage> _messages = const [];
  InboxItem? _activeChat;
  Set<String> _onlineUsers = <String>{};
  Map<String, DateTime?> _lastActiveUsers = const <String, DateTime?>{};
  bool _loadingInbox = false;
  bool _loadingMessages = false;
  bool _searching = false;
  String? _connectionLabel;
  bool _syncingSession = false;
  String? _lastSessionKey;

  List<InboxItem> get inbox => _inbox;
  List<ChatMessage> get messages => _messages;
  InboxItem? get activeChat => _activeChat;
  Set<String> get onlineUsers => _onlineUsers;
  bool get loadingInbox => _loadingInbox;
  bool get loadingMessages => _loadingMessages;
  bool get searching => _searching;
  String? get connectionLabel => _connectionLabel;
  bool get isConnected => _socketService.isConnected;

  // --- KOMPILYATSIYA XATOLARINI TUZATUVCHI METODLAR ---
  Future<void> bootstrap() => _syncSession(force: true);

  DateTime? lastActiveFor(String username) => _lastActiveUsers[username];

  Future<List<SearchUser>> searchUsers(String query) async {
    if (query.trim().isEmpty) return const [];
    _searching = true;
    notifyListeners();
    try {
      return await _chatRepository.searchUsers(query.trim());
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  Future<void> startChatWith(SearchUser user) async {
    await openChat(InboxItem(
      username: user.username,
      fullName: user.fullName,
      avatar: user.avatar,
      lastActive: null,
      lastMessage: '',
      lastMessageAt: DateTime.now(),
      unreadCount: 0,
    ));
  }

  void closeChat() {
    _activeChat = null;
    _messages = const [];
    notifyListeners();
  }

  Future<void> clearChatHistory(String username) async {
    await _chatRepository.clearChatHistory(username);
    if (_activeChat?.username == username) _messages = const [];
    _updateInboxPreview(
        peer: username, preview: '', at: DateTime.now(), unreadCount: 0);
    notifyListeners();
  }

  Future<void> deleteChat(String username) async {
    await _chatRepository.deleteChat(username);
    _inbox = _inbox.where((item) => item.username != username).toList();
    if (_activeChat?.username == username) closeChat();
    notifyListeners();
  }

  void markChatUnread(String username, {int count = 1}) {
    _updateInboxPreview(peer: username, unreadIncrement: count);
    notifyListeners();
  }

  void removeChat(String username) {
    _inbox = _inbox.where((item) => item.username != username).toList();
    if (_activeChat?.username == username) closeChat();
    notifyListeners();
  }

  // --- XABARLAR VA MEDIA ---
  Future<void> deleteActiveMessage(int id) async {
    await _chatRepository.deleteMessage(id);
    _messages = _messages.where((item) => item.id != id).toList();
    notifyListeners();
  }

  Future<ChatMessage?> updateActiveMessage(
      {required int id, required String message}) async {
    final updated =
        await _chatRepository.updateMessage(id: id, message: message);
    _messages =
        _messages.map((item) => item.id == id ? updated : item).toList();
    notifyListeners();
    return updated;
  }

  Future<void> openChat(InboxItem item) async {
    final user = _authController.user;
    if (user == null) return;
    _activeChat = item.copyWith(unreadCount: 0);
    _loadingMessages = true;
    notifyListeners();
    try {
      _messages = await _chatRepository.fetchMessages(
          user1: user.username, user2: item.username);
      _updateInboxPreview(peer: item.username, unreadCount: 0);
    } finally {
      _loadingMessages = false;
      notifyListeners();
    }
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
    final target = receiver ?? _activeChat?.username;
    if (currentUser == null || target == null) return false;
    debugPrint(
      'CHAT_DEBUG sendMessage() from=${currentUser.username} to=$target socketConnected=${_socketService.isConnected} hasText=${message.trim().isNotEmpty} hasImage=${image != null} hasAudio=${audio != null} hasVideo=${video != null}',
    );

    if (_socketService.isConnected) {
      _socketService.emit('NEW_MESSAGE', {
        'user': currentUser.username,
        'receiver': target,
        'message': message.trim(),
        'image': image,
        'audio': audio,
        'video': video,
        'replyTo': replyTo,
      });
      return true;
    }

    debugPrint('CHAT_DEBUG sendMessage() falling back to REST API');
    final sent = await _chatRepository.sendDirectMessage(
      receiver: target,
      message: message.trim(),
      image: image,
      audio: audio,
      video: video,
      replyTo: replyTo,
    );
    _consumeIncomingMessage(sent, {
      'receiver': target,
      'user': currentUser.username,
    });
    return true;
  }

  // --- UPLOAD METODLARI ---
  Future<String> uploadAudio(String path) => _chatRepository.uploadAudio(path);
  Future<String> uploadPickedAudio(PlatformFile file) =>
      _chatRepository.uploadPickedAudio(file);
  Future<String> uploadXFileAudio(XFile file) =>
      _chatRepository.uploadXFileAudio(file);
  Future<String> uploadMedia(String path) => _chatRepository.uploadMedia(path);
  Future<String> uploadPickedMedia(PlatformFile file) =>
      _chatRepository.uploadPickedMedia(file);
  Future<String> uploadXFileMedia(XFile file) =>
      _chatRepository.uploadXFileMedia(file);
  Future<String> uploadVideo(String path) => _chatRepository.uploadVideo(path);
  Future<String> uploadPickedVideo(PlatformFile file) =>
      _chatRepository.uploadPickedVideo(file);
  Future<String> uploadXFileVideo(XFile file) =>
      _chatRepository.uploadXFileVideo(file);

  // --- SOCKET VA OVOZ ---

  void _handleSocketPacket(SocketPacket packet) {
    switch (packet.event) {
      case 'connect':
        _connectionLabel = null;
        break;
      case 'disconnect':
        _connectionLabel = 'Socket uzildi';
        break;
      case 'connect_error':
      case 'error':
        _connectionLabel = 'Socket ulanmayapti';
        break;
      case 'CALL_OFFER':
      case 'INCOMING_CALL':
        debugPrint("DEBUG: Qo'ng'iroq signali keldi");
        _audioPlayer.setReleaseMode(ReleaseMode.loop);

        // WEB UCHUN AUDIO CONTEXT RESUME (Eng muhim joyi!)
        _audioPlayer.resume().then((_) {
          _audioPlayer.play(AssetSource('sounds/ringtone.wav'));
          debugPrint("DEBUG: Ringtone chalyapti");
        }).catchError((e) {
          debugPrint("DEBUG: Audio uyg'otishda xato: $e");
        });
        break;

      case 'CALL_ACCEPTED':
      case 'CALL_ENDED':
      case 'CALL_REJECT':
      case 'CALL_END':
        _audioPlayer.stop();
        debugPrint("DEBUG: Ovoz to'xtatildi");
        break;

      case 'NEW_MESSAGE':
        final payload = Map<String, dynamic>.from(packet.payload as Map);
        final message = ChatMessage.fromApi(payload);
        _consumeIncomingMessage(message, payload);

        // Xabar kelganda ham audio uyg'otamiz
        _audioPlayer.resume().then((_) {
          _audioPlayer.play(AssetSource('sounds/message.mp3'),
              mode: PlayerMode.lowLatency);
        }).catchError((e) {
          debugPrint("DEBUG: Message sound xatosi: $e");
        });
        break;

      case 'ONLINE_USERS_LIST':
        final users =
            (packet.payload as List<dynamic>).cast<Map<dynamic, dynamic>>();
        _onlineUsers = users
            .where((e) => e['online'] == true)
            .map((e) => e['username'].toString())
            .toSet();
        _lastActiveUsers = {
          for (var e in users)
            e['username'].toString(): _parseLastActive(e['lastActive'])
        };
        break;

      case 'USER_STATUS_CHANGED':
        final statusData =
            Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final changedUser = statusData['username']?.toString();
        final isOnline = statusData['online'] == true;
        if (changedUser != null) {
          final updated = Set<String>.from(_onlineUsers);
          if (isOnline) {
            updated.add(changedUser);
          } else {
            updated.remove(changedUser);
            _lastActiveUsers = Map<String, DateTime?>.from(_lastActiveUsers)
              ..[changedUser] = _parseLastActive(statusData['lastActive']) ?? DateTime.now();
          }
          _onlineUsers = updated;
        }
        break;
    }
    notifyListeners();
  }

  // --- INBOX VA SYNC ---
  Future<void> loadInbox() async {
    final user = _authController.user;
    if (user == null) return;
    _loadingInbox = true;
    notifyListeners();
    try {
      _inbox = await _chatRepository.fetchInbox(user.username);
      // Populate _lastActiveUsers from inbox data (only for offline users)
      final updated = Map<String, DateTime?>.from(_lastActiveUsers);
      for (final item in _inbox) {
        if (item.lastActive != null && !_onlineUsers.contains(item.username)) {
          updated[item.username] = item.lastActive;
        }
      }
      _lastActiveUsers = updated;
    } finally {
      _loadingInbox = false;
      notifyListeners();
    }
  }

  void _consumeIncomingMessage(ChatMessage message, Map<String, dynamic> raw) {
    final currentUser = _authController.user;
    if (currentUser == null) return;
    final peer = message.senderUsername == currentUser.username
        ? raw['receiver']?.toString()
        : message.senderUsername;
    if (peer == null) return;
    _updateInboxPreview(
        peer: peer, preview: message.content, at: message.createdAt);
    if (_activeChat?.username == peer) _messages = [..._messages, message];
    notifyListeners();
  }

  void _updateInboxPreview(
      {required String peer,
      String? preview,
      DateTime? at,
      int unreadIncrement = 0,
      int? unreadCount}) {
    final current = List<InboxItem>.from(_inbox);
    final index = current.indexWhere((item) => item.username == peer);
    if (index >= 0) {
      current[index] = current[index].copyWith(
        lastMessage: preview ?? current[index].lastMessage,
        lastMessageAt: at ?? current[index].lastMessageAt,
        unreadCount:
            unreadCount ?? current[index].unreadCount + unreadIncrement,
      );
      _inbox = current;
    }
  }

  void _handleDependencyChange() => _syncSession();

  Future<void> _syncSession({bool force = false}) async {
    final user = _authController.user;
    if (user == null) {
      debugPrint('CHAT_DEBUG _syncSession() skipped: no authenticated user');
      return;
    }
    final sessionKey = '${user.username}|${_settingsController.baseUrl}';
    if (_syncingSession) {
      debugPrint('CHAT_DEBUG _syncSession() skipped: already syncing');
      return;
    }
    if (!force && _lastSessionKey == sessionKey && _inbox.isNotEmpty) {
      debugPrint('CHAT_DEBUG _syncSession() skipped: session already ready');
      return;
    }

    debugPrint(
      'CHAT_DEBUG _syncSession() start force=$force username=${user.username} baseUrl=${_settingsController.baseUrl} socketBase=${AppConfig.socketBaseUrl(_settingsController.baseUrl)} socketPath=${AppConfig.socketPath(_settingsController.baseUrl)} hasCookie=${_sessionStore.cookie?.isNotEmpty == true}',
    );
    _syncingSession = true;
    _socketService.connect(
      baseUrl: AppConfig.socketBaseUrl(_settingsController.baseUrl),
      path: AppConfig.socketPath(_settingsController.baseUrl),
      username: user.username,
      cookie: _sessionStore.cookie,
    );
    try {
      await loadInbox();
      _lastSessionKey = sessionKey;
      debugPrint('CHAT_DEBUG _syncSession() completed');
    } finally {
      _syncingSession = false;
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _authController.removeListener(_handleDependencyChange);
    _settingsController.removeListener(_handleDependencyChange);
    _socketSub.cancel();
    super.dispose();
  }

  DateTime? _parseLastActive(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    }
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
