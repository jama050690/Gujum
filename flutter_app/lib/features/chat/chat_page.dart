import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import 'media_saver.dart';
import 'media_store.dart';
import '../../models/session_user.dart';
import '../auth/auth_controller.dart';
import '../call/call_controller.dart';
import '../settings/settings_controller.dart';
import '../social/calls_page.dart';
import '../social/community_page.dart';
import '../social/friends_page.dart';
import '../social/contact_profile_page.dart';
import '../social/profile_page.dart';
import '../social/settings_page.dart';
import '../social/social_repository.dart';
import 'chat_controller.dart';
import 'media_viewer_page.dart';
import 'recording_file_support.dart';

part 'chat_page_parts/chat_page_enums.dart';
part 'chat_page_parts/chat_page_state_storage.dart';
part 'chat_page_parts/chat_page_state_actions.dart';
part 'chat_page_parts/chat_page_build.dart';
part 'chat_page_parts/users_panel.dart';
part 'chat_page_parts/users_header.dart';
part 'chat_page_parts/users_navigation.dart';
part 'chat_page_parts/inbox_tiles.dart';
part 'chat_page_parts/search_states.dart';
part 'chat_page_parts/conversation_pane_preferences.dart';
part 'chat_page_parts/conversation_pane_selection.dart';
part 'chat_page_parts/conversation_pane_actions.dart';
part 'chat_page_parts/conversation_pane_copy_save.dart';
part 'chat_page_parts/conversation_pane_send_message.dart';
part 'chat_page_parts/conversation_pane_recent_media.dart';
part 'chat_page_parts/conversation_pane_upload_location.dart';
part 'chat_page_parts/conversation_pane_recording.dart';
part 'chat_page_parts/conversation_pane_media_helpers.dart';
part 'chat_page_parts/conversation_pane_header_actions.dart';
part 'chat_page_parts/conversation_pane_view.dart';
part 'chat_page_parts/conversation_pane_widgets.dart';
part 'chat_page_parts/conversation_pane_message_bubble.dart';
part 'chat_page_parts/conversation_pane_composer.dart';
part 'chat_page_parts/conversation_parsers.dart';
part 'chat_page_parts/composer_widgets.dart';
part 'chat_page_parts/saved_messages_header.dart';
part 'chat_page_parts/backdrop_empty_state.dart';
part 'chat_page_parts/app_drawer.dart';
part 'chat_page_parts/attachment_picker_sheet.dart';
part 'chat_page_parts/inline_audio.dart';
part 'chat_page_parts/inline_video.dart';
part 'chat_page_parts/avatar_time.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _quickCameraPicker = ImagePicker();

  Timer? _searchDebounce;
  Set<String> _archivedChats = <String>{};
  Set<String> _pinnedChats = <String>{};
  Set<String> _mutedChats = <String>{};
  List<SearchUser> _globalResults = const [];
  bool _loadingGlobalSearch = false;
  bool _showArchived = false;
  bool _showSavedMessages = false;
  String? _archiveOwner;
  DateTime? _lastBackPress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restoreChatPreferences();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final auth = context.watch<AuthController>();
    final chat = context.watch<ChatController>();
    return _buildChatPageScaffold(context, settings, auth, chat);
  }
}

class _ConversationPane extends StatefulWidget {
  const _ConversationPane({
    required this.settings,
    required this.chat,
    required this.showBack,
    required this.showSavedMessages,
    required this.onBack,
    this.onMoreActions,
  });

  final SettingsController settings;
  final ChatController chat;
  final bool showBack;
  final bool showSavedMessages;
  final VoidCallback onBack;
  final VoidCallback? onMoreActions;

  @override
  State<_ConversationPane> createState() => _ConversationPaneState();
}

enum _AttachmentType {
  image,
  video,
  audio,
  file,
  location,
}

class _ConversationPaneState extends State<_ConversationPane>
    with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final FocusNode _composerFocusNode;
  final ImagePicker _imagePicker = ImagePicker();

  // Suhbat ichidagi qidiruv. Xabarlar endi qurilmada saqlangani uchun
  // qidirish uchun serverga murojaat kerak emas — ochiq suhbatning o'zi
  // filtrlanadi.
  final TextEditingController _chatSearchController = TextEditingController();
  bool _chatSearchActive = false;
  String _chatSearchQuery = '';

  static const Set<String> _imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
    'bmp',
  };
  static const Set<String> _videoExtensions = <String>{
    'mp4',
    'mov',
    'm4v',
    'avi',
    'mkv',
    'webm',
    '3gp',
  };
  static const Set<String> _audioExtensions = <String>{
    'mp3',
    'm4a',
    'aac',
    'wav',
    'ogg',
    'opus',
    'amr',
    'flac',
    'webm',
  };
  static const List<String> _quickEmojis = <String>[
    '😀',
    '😁',
    '😂',
    '😍',
    '😎',
    '🥳',
    '🤝',
    '👏',
    '🙏',
    '🔥',
    '❤️',
    '👍',
  ];

  bool _uploadingAttachment = false;
  bool _locatingLocation = false;
  bool _isRecordingVoice = false;
  int _recordingSeconds = 0;
  bool _stickToBottom = true;
  bool _showScrollToBottom = false;
  bool _scrollAfterNextMessage = false;
  bool _scrollWhenLoadCompletes = false;
  int _lastMessageCount = 0;
  bool _lastLoadingMessages = false;
  String? _lastActiveChatUsername;
  String? _messagePreferenceOwnerKey;
  Set<int> _pinnedMessageIds = <int>{};
  Set<int> _selectedMessageIds = <int>{};
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composerFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          String t(String key) =>
              AppStrings.text(widget.settings.localeCode, key);
          unawaited(_sendCurrentMessage(widget.chat, t));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _lastMessageCount = widget.chat.messages.length;
    _lastLoadingMessages = widget.chat.loadingMessages;
    _lastActiveChatUsername = widget.chat.activeChat?.username;
    _messagesScrollController.addListener(_handleScrollChanged);
    if (_lastActiveChatUsername != null) {
      _scrollWhenLoadCompletes = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.chat.reloadActiveChat());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_restoreMessagePreferencesForActiveChat());
  }

  @override
  void didUpdateWidget(covariant _ConversationPane oldWidget) {
    super.didUpdateWidget(oldWidget);

    final activeChatUsername = widget.chat.activeChat?.username;
    final messageCount = widget.chat.messages.length;
    final loadingMessages = widget.chat.loadingMessages;
    final activeChatChanged = activeChatUsername != _lastActiveChatUsername;
    final messagesAppended = messageCount > _lastMessageCount;
    final loadCompleted = _lastLoadingMessages && !loadingMessages;

    if (activeChatChanged) {
      // Chat o'zgarganda scroll holatini to'liq reset qilamiz
      _scrollAfterNextMessage = activeChatUsername != null;
      _scrollWhenLoadCompletes = activeChatUsername != null;
      if (activeChatUsername != null && !loadingMessages && messageCount > 0) {
        _scheduleScrollToBottom(animated: false);
        _scrollWhenLoadCompletes = false;
      }
      if (activeChatUsername == null) {
        _scrollAfterNextMessage = false;
      }
      _replyingTo = null;
      _selectedMessageIds = <int>{};
      if (_editingMessage != null) {
        _editingMessage = null;
        _messageController.clear();
      }
      if (activeChatUsername == null) {
        _messagePreferenceOwnerKey = null;
        _pinnedMessageIds = <int>{};
      }
      unawaited(_restoreMessagePreferencesForActiveChat());
    }

    if (loadCompleted &&
        _scrollWhenLoadCompletes &&
        activeChatUsername != null &&
        messageCount > 0) {
      _scheduleScrollToBottom(animated: false);
      _scrollWhenLoadCompletes = false;
    } else if (messagesAppended &&
        activeChatUsername != null &&
        (_scrollAfterNextMessage || _stickToBottom)) {
      _scheduleScrollToBottom(animated: true);
      _scrollAfterNextMessage = false;
    }

    _lastActiveChatUsername = activeChatUsername;
    _lastMessageCount = messageCount;
    _lastLoadingMessages = loadingMessages;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _composerFocusNode.dispose();
    _messagesScrollController
      ..removeListener(_handleScrollChanged)
      ..dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _handleScrollChanged() {
    if (!_messagesScrollController.hasClients) return;
    final px = _messagesScrollController.position.pixels;
    _stickToBottom = px <= 80;
    final show = px > 200;
    if (show != _showScrollToBottom) setState(() => _showScrollToBottom = show);
  }

  @override
  Widget build(BuildContext context) => _buildConversationPane(context);
}
