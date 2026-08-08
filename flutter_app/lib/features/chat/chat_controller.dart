import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/network/session_store.dart';
import '../../core/network/socket_service.dart';
import '../../models/chat_models.dart';
import '../auth/auth_controller.dart';
import 'media_store.dart';
import 'message_store.dart';
import '../settings/settings_controller.dart';
import 'chat_repository.dart';

/// Tarmoq holati — yuqoridagi banner shu asosda ko'rsatiladi.
enum ConnectionStatus { connected, connecting, offline }

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
  /// Ochilgan suhbatlarning xotiradagi nusxasi.
  ///
  /// LinkedHashMap tartibi ishlatiladi: eng oxirgi tegilgan suhbat oxirida
  /// turadi, chegaradan oshganda esa eng eskisi chiqarib tashlanadi. Ilgari
  /// bu jadval faqat o'sardi — 50 ta suhbat ochilsa, 50 tasining to'liq
  /// xabarlari ilova yopilguncha xotirada qolardi. Diskdagi nusxa
  /// saqlanadi, shuning uchun chiqarib tashlangan suhbat qayta ochilganda
  /// darhol yuklanadi.
  static const _maxCachedChats = 8;
  final Map<String, List<ChatMessage>> _messageCache = {};

  void _cacheMessages(String peer, List<ChatMessage> messages) {
    _messageCache.remove(peer);
    _messageCache[peer] = List.from(messages);
    while (_messageCache.length > _maxCachedChats) {
      _messageCache.remove(_messageCache.keys.first);
    }
  }
  // Qurilmadagi doimiy nusxa. Server xabarlarni 24 soatdan keyin o'chiradi,
  // shuning uchun bu yerdagi nusxa hech qachon tozalanmaydi.
  MessageStore? _store;
  Set<String> _onlineUsers = <String>{};
  Map<String, DateTime?> _lastActiveUsers = const <String, DateTime?>{};
  bool _loadingInbox = false;
  bool _loadingMessages = false;
  bool _messagesLoadFailed = false;
  bool _loadingOlder = false;
  /// Serverda yana eski xabarlar bormi. Bir marta bo'sh sahifa kelsa
  /// so'ramaymiz — pastga har tekkanda so'rov yuborilmasin.
  bool _hasMoreOlder = true;
  bool _loadingMoreChats = false;
  bool _hasMoreChats = true;
  String? _messagesErrorDetail;
  bool _searching = false;
  ConnectionStatus _connectionStatus = ConnectionStatus.connected;
  bool _syncingSession = false;
  String? _lastSessionKey;

  List<InboxItem> get inbox => _inbox;
  List<ChatMessage> get messages => _messages;
  InboxItem? get activeChat => _activeChat;

  /// "Saqlangan xabarlar" — o'zi bilan suhbat.
  ///
  /// Ilgari bu shunchaki bo'sh ekran edi: sarlavha bor, xabarlar ro'yxati
  /// ham, yozish maydoni ham yo'q. Endi u oddiy suhbat, faqat suhbatdoshi
  /// o'zingiz — shuning uchun yozish, fayl yuborish, tarix va qurilmadagi
  /// nusxa boshqa suhbatlar bilan bir xil kod orqali ishlaydi.
  ///
  /// Server tomonda ham cheklov yo'q: (men, men) juftligi odatdagi chat
  /// qatoriga aylanadi.
  bool get showSavedMessages =>
      _activeChat != null &&
      _activeChat!.username == _authController.user?.username;

  Future<void> openSavedMessages({required String title}) async {
    final me = _authController.user;
    if (me == null) return;
    await openChat(InboxItem(
      username: me.username,
      // Sarlavhada o'z ismingiz emas, "Saqlangan xabarlar" turadi.
      fullName: title,
      avatar: me.avatar,
      lastActive: null,
      lastMessage: '',
      lastMessageAt: DateTime.now(),
      unreadCount: 0,
    ));
  }

  void closeSavedMessages() {
    if (!showSavedMessages) return;
    closeChat();
  }

  Set<String> get onlineUsers => _onlineUsers;
  bool get loadingInbox => _loadingInbox;
  bool get loadingMessages => _loadingMessages;
  bool get messagesLoadFailed => _messagesLoadFailed;
  String? get messagesErrorDetail => _messagesErrorDetail;
  bool get searching => _searching;
  ConnectionStatus get connectionStatus => _connectionStatus;

  /// Tarjima kaliti — ulanish yaxshi bo'lsa null (banner ko'rsatilmaydi).
  String? get connectionLabel => switch (_connectionStatus) {
        ConnectionStatus.connected => null,
        ConnectionStatus.connecting => 'connection_connecting',
        ConnectionStatus.offline => 'connection_offline',
      };
  bool get isConnected => _socketService.isConnected;
  bool get loadingOlder => _loadingOlder;
  bool get hasMoreOlder => _hasMoreOlder;
  bool get hasMoreChats => _hasMoreChats;

  /// Suhbatlar ro'yxatining keyingi bo'lagi. Xabarlar bilan bir xil kursor
  /// yondashuvi — oxirgi xabar vaqtidan oldingilari.
  Future<void> loadMoreChats() async {
    if (_loadingMoreChats || !_hasMoreChats || _inbox.isEmpty) return;
    final user = _authController.user;
    if (user == null) return;
    final oldest = _inbox.last.lastMessageAt;
    if (oldest == null) return;

    _loadingMoreChats = true;
    try {
      final more =
          await _chatRepository.fetchInbox(user.username, before: oldest);
      if (more.isEmpty) {
        _hasMoreChats = false;
      } else {
        final seen = _inbox.map((e) => e.username).toSet();
        _inbox = [..._inbox, ...more.where((e) => !seen.contains(e.username))];
      }
    } catch (e) {
    } finally {
      _loadingMoreChats = false;
      notifyListeners();
    }
  }

  /// Ro'yxat tepasiga yetganda chaqiriladi: eng eski yuklangan xabardan
  /// oldingilarini oladi. Sahifa ochilishida hammasi emas, faqat oxirgi
  /// bo'lak yuklanadi — qolgani kerak bo'lganda kelaveradi.
  Future<void> loadOlderMessages() async {
    if (_loadingOlder || !_hasMoreOlder) return;
    final user = _authController.user;
    final peer = _activeChat?.username;
    if (user == null || peer == null || _messages.isEmpty) return;

    final oldest = _messages.first.createdAt;
    if (oldest == null) return;

    _loadingOlder = true;
    notifyListeners();
    try {
      final older = await _chatRepository.fetchMessages(
        user1: user.username,
        user2: peer,
        before: oldest,
      );
      if (_activeChat?.username != peer) return;
      if (older.isEmpty) {
        _hasMoreOlder = false;
      } else {
        _messages = MessageStore.merge(older, _messages);
        _persist(peer, _messages);
      }
    } catch (e) {
    } finally {
      _loadingOlder = false;
      notifyListeners();
    }
  }

  // --- KOMPILYATSIYA XATOLARINI TUZATUVCHI METODLAR ---
  Future<void> bootstrap() async {
    await _ensureStore();
    await _syncSession(force: true);
  }

  /// Joriy foydalanuvchi uchun local do'kon. Akkaunt almashsa qaytadan
  /// ochiladi — bir qurilmadagi ikki akkaunt tarixi aralashmasin.
  Future<MessageStore?> _ensureStore() async {
    final user = _authController.user;
    if (user == null) return null;
    // Akkaunt id si bo'yicha ajratamiz. Username bo'yicha ajratilganda
    // o'chirilgan akkaunt bilan bir xil pochtadan qayta ro'yxatdan o'tilsa
    // aynan o'sha username qaytadi va yangi akkaunt eski yozishmalarni
    // ko'rib qolardi.
    final owner = user.id != null ? 'u${user.id}' : user.username;
    if (_store?.owner == owner) return _store;
    try {
      _store = await MessageStore.create(owner);
    } catch (e) {
      _store = null;
    }
    return _store;
  }

  /// Suhbatni xotirada ham, diskda ham yangilaydi.
  void _persist(String peer, List<ChatMessage> messages) {
    _cacheMessages(peer, messages);
    unawaited(_ensureStore().then((store) => store?.save(peer, messages)));
    unawaited(_cacheAttachments(messages));
  }

  /// Biriktirilgan fayllarni qurilmaga yuklab qo'yadi.
  ///
  /// Serverdagi nusxa 24 soatdan keyin o'chadi, shuning uchun rasm/video/ovoz
  /// bir marta olinadi va keyin diskdan ko'rsatiladi. Yuklab bo'lingach UI
  /// yangilanadi — endi mahalliy nusxa ishlatiladi.
  Future<void> _cacheAttachments(List<ChatMessage> messages) async {
    final store = await MediaStore.instance();
    final baseUrl = _settingsController.baseUrl;
    var changed = false;
    for (final message in messages) {
      for (final path in [message.image, message.audio, message.video]) {
        if (path == null || path.isEmpty) continue;
        if (MediaStore.localFor(path) != null) continue;
        final url = AppConfig.resolveMediaUrl(path, baseUrl);
        if (url.isEmpty) continue;
        final saved = await store.ensureLocal(path, url);
        if (saved != null) changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Har bir yuborish uchun bir martalik kalit. Foydalanuvchi nomi + vaqt +
  /// tasodifiy son: ikki qurilmadan bir vaqtda yozilsa ham to'qnashmaydi.
  String _newClientMessageId(String username) {
    final rand = Random().nextInt(1 << 32);
    return '$username-${DateTime.now().microsecondsSinceEpoch}-$rand';
  }

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
    if (_activeChat != null) {
      if (_messages.isNotEmpty) {
        _cacheMessages(_activeChat!.username, _messages);
      } else {
        _messageCache.remove(_activeChat!.username);
      }
    }
    _activeChat = null;
    _messages = const [];
    notifyListeners();
  }

  Future<void> clearChatHistory(String username,
      {bool forEveryone = false}) async {
    await _chatRepository.clearChatHistory(username, forEveryone: forEveryone);
    _messageCache.remove(username);
    // Qurilmadagi nusxa faqat shu yerda — foydalanuvchi ataylab tozalaganda
    // o'chiriladi, aks holda tarix qaytib paydo bo'lardi.
    final store = await _ensureStore();
    await store?.deleteConversation(username);
    if (_activeChat?.username == username) _messages = const [];
    _updateInboxPreview(
        peer: username, preview: '', at: DateTime.now(), unreadCount: 0);
    notifyListeners();
  }

  Future<void> deleteChat(String username) async {
    await _chatRepository.deleteChat(username);
    _inbox = _inbox.where((item) => item.username != username).toList();
    _messageCache.remove(username);
    final store = await _ensureStore();
    await store?.deleteConversation(username);
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
  /// Tanlangan xabarlarni o'chiradi. [forEveryone] — suhbatdoshdan ham.
  Future<void> deleteMessages(List<int> ids, {required bool forEveryone}) async {
    if (ids.isEmpty) return;
    final removed = await _chatRepository.deleteMessages(ids, forEveryone: forEveryone);
    final gone = removed.isEmpty ? ids : removed;
    _removeMessagesLocally(_activeChat?.username, gone);
  }

  Future<void> deleteActiveMessage(int id) =>
      deleteMessages([id], forEveryone: false);

  /// Xabarlarni ekrandan ham, qurilmadagi nusxadan ham olib tashlaydi.
  void _removeMessagesLocally(String? peer, List<int> ids) {
    if (peer == null) return;
    final idSet = ids.toSet();
    _messages = _messages.where((m) => !idSet.contains(m.id)).toList();
    final cached = _messageCache[peer];
    if (cached != null) {
      _persist(peer, cached.where((m) => !idSet.contains(m.id)).toList());
    } else {
      _persist(peer, _messages);
    }
    notifyListeners();
  }

  Future<ChatMessage?> updateActiveMessage(
      {required int id, required String message}) async {
    final updated =
        await _chatRepository.updateMessage(id: id, message: message);
    _messages =
        _messages.map((item) => item.id == id ? updated : item).toList();
    final peer = _activeChat?.username;
    if (peer != null) _persist(peer, _messages);
    notifyListeners();
    return updated;
  }

  Future<void> openChat(InboxItem item) async {
    final user = _authController.user;
    if (user == null) return;
    _activeChat = item.copyWith(unreadCount: 0);
    // Avval xotiradagi, keyin diskdagi nusxa — ikkalasi ham bo'lmasa spinner.
    var cached = _messageCache[item.username];
    if (cached == null || cached.isEmpty) {
      // Xotirada yo'q — diskka borishimiz kerak, ya'ni bir necha await.
      // Ilgari birinchi notifyListeners() shulardan KEYIN edi: suhbat
      // bosilgandan so'ng ekranda hech narsa o'zgarmasdi va ilova
      // qotgandek tuyulardi. MessageStore birinchi marta yaratilganda
      // hujjatlar papkasi ham so'raladi (platforma kanali), shuning uchun
      // kechikish sezilarli. Endi ekran darhol ochiladi.
      _messages = const [];
      _loadingMessages = true;
      _messagesLoadFailed = false;
      _messagesErrorDetail = null;
      _hasMoreOlder = true;
      notifyListeners();

      final store = await _ensureStore();
      final stored = await store?.load(item.username) ?? const <ChatMessage>[];
      if (stored.isNotEmpty) {
        cached = stored;
        _cacheMessages(item.username, stored);
      }
      // Fetch davomida boshqa chat ochilgan bo'lishi mumkin.
      if (_activeChat?.username != item.username) return;
    }
    final hasCache = cached != null && cached.isNotEmpty;
    _messages = hasCache ? cached : const [];
    _loadingMessages = !hasCache;
    _messagesLoadFailed = false;
    _messagesErrorDetail = null;
    _hasMoreOlder = true;
    notifyListeners();
    try {
      final fetched = await _chatRepository.fetchMessages(
          user1: user.username, user2: item.username);
      // Race condition: fetch davomida boshqa chat ochilgan bo'lishi mumkin
      if (_activeChat?.username == item.username) {
        // Server faqat oxirgi 24 soatni qaytaradi — eskisi qurilmada qoladi,
        // shuning uchun almashtirmaymiz, birlashtiramiz.
        _messages = MessageStore.merge(_messages, fetched);
        _messagesLoadFailed = false;
        if (_messages.isNotEmpty) {
          _persist(item.username, _messages);
        }
        _updateInboxPreview(peer: item.username, unreadCount: 0);
      }
    } catch (e) {
      if (_activeChat?.username == item.username && _messages.isEmpty) {
        _messagesLoadFailed = true;
        _messagesErrorDetail = e.toString();
      }
    } finally {
      if (_activeChat?.username == item.username) {
        _loadingMessages = false;
        notifyListeners();
      }
    }
    // Fetch muvaffaqiyatli bo'lsa GET /api/messages o'zi read qiladi, lekin
    // cache'dan ko'rsatilgan yoki fetch yiqilgan holatda ham peer ✓✓ ni
    // ko'rishi kerak — shuning uchun bu yerda ham bir marta belgilaymiz.
    if (_activeChat?.username == item.username) _markChatRead(item.username);
    // Xabarlar bo'sh bo'lsa — 2 soniyadan keyin bir marta qayta urinish
    if (_messages.isEmpty && _activeChat?.username == item.username) {
      await Future.delayed(const Duration(seconds: 2));
      if (_activeChat?.username != item.username) return;
      try {
        final retried = await _chatRepository.fetchMessages(
            user1: user.username, user2: item.username);
        if (_activeChat?.username != item.username) return;
        _messages = MessageStore.merge(_messages, retried);
        if (_messages.isNotEmpty) {
          _persist(item.username, _messages);
        }
        _updateInboxPreview(peer: item.username, unreadCount: 0);
        notifyListeners();
      } catch (e) {
      }
    }
  }

  Future<void> reloadActiveChat() async {
    if (_activeChat == null || _loadingMessages) return;
    _messagesLoadFailed = false;
    await openChat(_activeChat!);
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

    // Idempotentlik kaliti: qayta yuborilsa (socket uzilib qayta ulandi,
    // foydalanuvchi ikki marta bosdi) server yangi qator yaratmaydi.
    final clientMsgId = _newClientMessageId(currentUser.username);

    if (_socketService.isConnected) {
      _socketService.emit('NEW_MESSAGE', {
        'user': currentUser.username,
        'receiver': target,
        'message': message.trim(),
        'image': image,
        'audio': audio,
        'video': video,
        'replyTo': replyTo,
        'clientMsgId': clientMsgId,
      });
      return true;
    }

    final sent = await _chatRepository.sendDirectMessage(
      receiver: target,
      message: message.trim(),
      image: image,
      audio: audio,
      video: video,
      replyTo: replyTo,
      clientMsgId: clientMsgId,
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
        _connectionStatus = ConnectionStatus.connected;
        if (_activeChat != null && !_loadingMessages) unawaited(reloadActiveChat());
        break;
      case 'disconnect':
        // socket.io o'zi qayta ulanadi — foydalanuvchiga "ulanmoqda" deymiz.
        _connectionStatus = ConnectionStatus.connecting;
        break;
      case 'connect_error':
      case 'error':
        _connectionStatus = ConnectionStatus.offline;
        break;
      // Qo'ng'iroq audio → CallController o'zi boshqaradi, bu yerda kerak emas

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

      // Suhbatdosh o'z xabarlarini hamma uchun o'chirdi.
      case 'MESSAGES_DELETED':
        final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final by = data['by']?.toString();
        final ids = (data['ids'] as List?)
                ?.map((e) => int.tryParse('$e'))
                .whereType<int>()
                .toList() ??
            const <int>[];
        if (by != null && ids.isNotEmpty) _removeMessagesLocally(by, ids);
        break;

      // Suhbatdosh butun tarixni hamma uchun tozaladi.
      case 'CHAT_CLEARED':
        final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final by = data['by']?.toString();
        if (by != null) {
          if (_activeChat?.username == by) _messages = const [];
          _messageCache.remove(by);
          unawaited(_ensureStore().then((s) => s?.deleteConversation(by)));
        }
        break;

      case 'MESSAGES_READ':
        final data = Map<String, dynamic>.from(packet.payload as Map? ?? {});
        final by = data['by']?.toString();
        if (by != null && by.isNotEmpty) _applyPeerRead(by);
        break;

      case 'ONLINE_USERS_LIST':
        final users =
            (packet.payload as List<dynamic>).cast<Map<dynamic, dynamic>>();
        _onlineUsers = users
            .where((e) => e['online'] == true)
            .map((e) => e['username'].toString())
            .toSet();
        // Merge — don't replace. inbox'dan yig'ilgan offline userlar lastActive yo'qolmasin.
        final merged = Map<String, DateTime?>.from(_lastActiveUsers);
        for (final e in users) {
          final ts = _parseLastActive(e['lastActive']);
          if (ts != null) {
            merged[e['username'].toString()] = ts;
          }
        }
        _lastActiveUsers = merged;
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

  /// Qo'ng'iroqlar tarixi. ChatRepository Provider orqali berilmagan,
  /// shuning uchun sahifa uni shu yerdan oladi.
  Future<List<CallHistoryEntry>> fetchCallHistory() async {
    final user = _authController.user;
    if (user == null) return const [];
    return _chatRepository.fetchCallHistory(user.username);
  }

  // --- INBOX VA SYNC ---
  Future<void> loadInbox() async {
    final user = _authController.user;
    if (user == null) return;
    _loadingInbox = true;
    notifyListeners();
    try {
      _inbox = await _chatRepository.fetchInbox(user.username);
      _hasMoreChats = _inbox.isNotEmpty;
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
    if (_activeChat?.username == peer) {
      _messagesLoadFailed = false;
      _messages = [..._messages, message];
      _persist(peer, _messages);
      // Chat ochiq turganda kelgan xabar — darhol o'qilgan hisoblanadi.
      if (message.senderUsername != currentUser.username) {
        _markChatRead(peer);
      }
    } else {
      // Chat yopiq bo'lsa ham xabar qurilmada qolishi kerak — server uni
      // 24 soatdan keyin o'chiradi.
      unawaited(_appendToStoredConversation(peer, message));
    }
    notifyListeners();
  }

  Future<void> _appendToStoredConversation(
      String peer, ChatMessage message) async {
    final store = await _ensureStore();
    if (store == null) return;
    final existing = _messageCache[peer] ?? await store.load(peer);
    final updated = MessageStore.merge(existing, [message]);
    _cacheMessages(peer, updated);
    await store.save(peer, updated);
  }

  /// Peer'ning bizga yozgan xabarlarini o'qilgan deb belgilaydi va unga
  /// ✓✓ ni jonli yetkazadi. Socket uzilgan bo'lsa REST orqali.
  void _markChatRead(String peer) {
    final currentUser = _authController.user;
    if (currentUser == null) return;
    if (_socketService.isConnected) {
      _socketService.emit('MESSAGES_READ', {'chatWith': peer});
      return;
    }
    unawaited(
      _chatRepository
          .markRead(username: currentUser.username, chatWith: peer)
          .catchError((e) {
      }),
    );
  }

  /// Peer bizning xabarlarimizni o'qidi — barcha o'z xabarlarimizni ✓✓ qilamiz.
  void _applyPeerRead(String peer) {
    final currentUser = _authController.user;
    if (currentUser == null) return;
    List<ChatMessage> mark(List<ChatMessage> list) => list
        .map((m) => m.senderUsername == currentUser.username && !m.isRead
            ? m.copyWith(isRead: true)
            : m)
        .toList();
    if (_activeChat?.username == peer) {
      _messages = mark(_messages);
      _persist(peer, _messages);
      return;
    }
    final cached = _messageCache[peer];
    if (cached != null) _persist(peer, mark(cached));
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
      return;
    }
    final sessionKey = '${user.username}|${_settingsController.baseUrl}';
    if (_syncingSession) {
      return;
    }
    if (!force && _lastSessionKey == sessionKey && _inbox.isNotEmpty) {
      return;
    }

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
