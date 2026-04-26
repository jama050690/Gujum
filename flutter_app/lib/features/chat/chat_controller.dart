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

  // --- QO'NG'IROQ VA OVOZ METODLARI (Loglarga moslandi) ---
  Future<void> startCall({bool video = false}) async {
    final currentUser = _authController.user;
    final targetUser = _activeChat;
    if (currentUser == null || targetUser == null) return;

    try {
      // Gudoq (Dialing tone)
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('sounds/dialing.mp3'));
    } catch (e) {
      debugPrint("Gudoq xatosi: $e");
    }

    // Logingizda CALL_OFFER ishlatilyapti
    _socketService.emit('CALL_OFFER', {
      'caller': currentUser.username,
      'receiver': targetUser.username,
      'isVideo': video,
      'callerName': currentUser.fullName,
    });
    notifyListeners();
  }

  Future<void> stopRingtone() async {
    await _audioPlayer.stop();
    notifyListeners();
  }

  // --- SOCKET PACKETLARINI TAYYORLASH (Server Loglariga Mos) ---
  void _handleSocketPacket(SocketPacket packet) {
    debugPrint("SERVERDAN KELGAN EVENT: ${packet.event}");

    switch (packet.event) {
      // 1. Qo'ng'iroq kelganda (Ringtone)
      case 'CALL_OFFER':
      case 'INCOMING_CALL':
        debugPrint("Qo'ng'iroq keldi, ringtone qo'yilmoqda...");
        _audioPlayer.setReleaseMode(ReleaseMode.loop);
        _audioPlayer.play(AssetSource('sounds/ringtone.mp3'));
        break;

      // 2. Qo'ng'iroq to'xtaganda
      case 'CALL_ACCEPTED':
      case 'CALL_ANSWERED':
      case 'CALL_REJECTED':
      case 'CALL_ENDED':
        debugPrint("Qo'ng'iroq yakunlandi/javob berildi, ovoz o'chmoqda.");
        stopRingtone();
        break;

      case 'NEW_MESSAGE':
        final payload = Map<String, dynamic>.from(packet.payload as Map);
        final message = ChatMessage.fromApi(payload);
        _consumeIncomingMessage(message, payload);
        _audioPlayer.play(AssetSource('sounds/message.mp3'), mode: PlayerMode.lowLatency);
        break;

      case 'ONLINE_USERS_LIST':
        final users = (packet.payload as List<dynamic>).cast<Map<dynamic, dynamic>>();
        _onlineUsers = users.where((e) => e['online'] == true).map((e) => e['username'].toString()).toSet();
        _lastActiveUsers = {for (var e in users) e['username'].toString(): _parseLastActive(e['lastActive'])};
        break;

      case 'connect':
        _connectionLabel = 'connected';
        break;
      case 'disconnect':
        _connectionLabel = 'disconnected';
        break;
    }
    notifyListeners();
  }

  // --- LOYIHADAGI BOSHQA METODLAR (Xatolarsiz) ---
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

  void closeChat() {
    _activeChat = null;
    _messages = const [];
    notifyListeners();
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

  Future<void> clearChatHistory(String username) async {
    await _chatRepository.clearChatHistory(username);
    if (_activeChat?.username == username) _messages = const [];
    _updateInboxPreview(peer: username, preview: '', at: DateTime.now(), unreadCount: 0);
  }

  Future<void> deleteChat(String username) async {
    await _chatRepository.deleteChat(username);
    _inbox = _inbox.where((e) => e.username != username).toList();
    if (_activeChat?.username == username) closeChat();
    notifyListeners();
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

  // --- UPLOAD METODLARI ---
  Future<String> uploadMedia(String path) => _chatRepository.uploadMedia(path);
  Future<String> uploadPickedMedia(PlatformFile file) => _chatRepository.uploadPickedMedia(file);
  Future<String> uploadXFileMedia(XFile file) => _chatRepository.uploadXFileMedia(file);
  Future<String> uploadAudio(String path) => _chatRepository.uploadAudio(path);
  Future<String> uploadPickedAudio(PlatformFile file) => _chatRepository.uploadPickedAudio(file);
  Future<String> uploadXFileAudio(XFile file) => _chatRepository.uploadXFileAudio(file);
  Future<String> uploadVideo(String path) => _chatRepository.uploadVideo(path);
  Future<String> uploadPickedVideo(PlatformFile file) => _chatRepository.uploadPickedVideo(file);
  Future<String> uploadXFileVideo(XFile file) => _chatRepository.uploadXFileVideo(file);

  // --- INBOX VA OPENCHAT ---
  Future<void> loadInbox() async {
    final user = _authController.user;
    if (user == null) return;
    _loadingInbox = true;
    notifyListeners();
    try {
      _inbox = await _chatRepository.fetchInbox(user.username);
    } finally {
      _loadingInbox = false;
      notifyListeners();
    }
  }

  Future<void> openChat(InboxItem item) async {
    final user = _authController.user;
    if (user == null) return;
    _activeChat = item.copyWith(unreadCount: 0);
    _loadingMessages = true;
    notifyListeners();
    try {
      _messages = await _chatRepository.fetchMessages(user1: user.username, user2: item.username);
      _updateInboxPreview(peer: item.username, unreadCount: 0);
    } finally {
      _loadingMessages = false;
      notifyListeners();
    }
  }

  void _consumeIncomingMessage(ChatMessage message, Map<String, dynamic> raw) {
    final currentUser = _authController.user;
    if (currentUser == null) return;
    final peer = message.senderUsername == currentUser.username ? raw['receiver']?.toString() : message.senderUsername;
    if (peer == null) return;
    _updateInboxPreview(peer: peer, preview: message.content, at: message.createdAt);
    if (_activeChat?.username == peer) _messages = [..._messages, message];
    notifyListeners();
  }

  void _updateInboxPreview({required String peer, String? preview, DateTime? at, int unreadIncrement = 0, int? unreadCount}) {
    final current = List<InboxItem>.from(_inbox);
    final index = current.indexWhere((e) => e.username == peer);
    if (index >= 0) {
      current[index] = current[index].copyWith(
        lastMessage: preview ?? current[index].lastMessage,
        lastMessageAt: at ?? current[index].lastMessageAt,
        unreadCount: unreadCount ?? current[index].unreadCount + unreadIncrement,
      );
      _inbox = current;
    }
  }

  void _handleDependencyChange() => _syncSession();

  Future<void> _syncSession({bool force = false}) async {
    final user = _authController.user;
    if (user == null) return;
    _socketService.connect(
      baseUrl: AppConfig.socketBaseUrl(_settingsController.baseUrl),
      path: AppConfig.socketPath(_settingsController.baseUrl),
      username: user.username,
      cookie: _sessionStore.cookie,
    );
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
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}