part of '../chat_page.dart';

extension _ConversationPaneCopySave on _ConversationPaneState {
  bool _canCopyMessage(ChatMessage message) {
    return message.content.isNotEmpty &&
        _parseCallMessage(message.content) == null &&
        _parseLocationMessage(message.content) == null;
  }

  bool _canSaveMedia(ChatMessage message) {
    final hasImage = message.image != null &&
        message.image!.isNotEmpty &&
        isImageAttachmentPath(message.image);
    final hasVideo = message.video != null && message.video!.isNotEmpty;
    final hasAudio = message.audio != null && message.audio!.isNotEmpty;
    return hasImage || hasVideo || hasAudio;
  }

  Future<void> _copyMessage(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (mounted) {
      _showInfoSnackBar(
        AppStrings.text(widget.settings.localeCode, 'message_copied'),
      );
    }
  }

  Future<void> _saveMedia(
    ChatMessage message,
    String Function(String) t,
  ) async {
    String? mediaPath;
    if (message.image != null &&
        message.image!.isNotEmpty &&
        isImageAttachmentPath(message.image)) {
      mediaPath = message.image;
    } else if (message.video != null && message.video!.isNotEmpty) {
      mediaPath = message.video;
    } else if (message.audio != null && message.audio!.isNotEmpty) {
      mediaPath = message.audio;
    }
    if (mediaPath == null) return;

    final fileName = _fileNameFromPath(mediaPath);
    final mimeType = MediaSaver.mimeFor(fileName);

    try {
      // Avval qurilmadagi nusxa: server fayli 24 soatdan keyin o'chishi
      // mumkin, mahalliy nusxa esa qoladi.
      var sourcePath = MediaStore.localFor(mediaPath);
      if (sourcePath == null) {
        final url = AppConfig.resolveMediaUrl(mediaPath, widget.settings.baseUrl);
        final store = await MediaStore.instance();
        sourcePath = await store.ensureLocal(mediaPath, url);
      }
      if (sourcePath == null) {
        if (mounted) _showInfoSnackBar(t('message_save_failed'));
        return;
      }

      // Telegram singari: rasm/video galereyaga, qolgani Downloads ga.
      final saved = MediaSaver.goesToGallery(mimeType)
          ? await MediaSaver.saveToGallery(
              path: sourcePath, fileName: fileName, mimeType: mimeType)
          : await MediaSaver.saveToDownloads(
              path: sourcePath, fileName: fileName, mimeType: mimeType);

      if (!mounted) return;
      _showInfoSnackBar(
        saved ? '$fileName ${t('message_saved')}' : t('message_save_failed'),
      );
    } catch (_) {
      if (mounted) _showInfoSnackBar(t('message_save_failed'));
    }
  }

  Future<void> _forwardMessagesToChat(
    ChatController chat,
    InboxItem target,
    List<ChatMessage> messages,
    String Function(String) t,
  ) async {
    for (final message in messages) {
      final sent = await chat.sendMessage(
        receiver: target.username,
        message: message.content,
        image: message.image,
        audio: message.audio,
        video: message.video,
      );
      if (!sent) {
        if (mounted) _showInfoSnackBar(t('message_send_failed'));
        return;
      }
    }
    if (!mounted) return;
    applyState(() => _selectedMessageIds = <int>{});
    _showInfoSnackBar(t('done'));
  }

  Future<void> _showForwardPicker(
    ChatController chat,
    String Function(String) t,
    List<ChatMessage> messages,
  ) async {
    final me = context.read<AuthController>().user;
    // O'zi bilan suhbat ro'yxatda o'z ismi bilan turmasligi kerak — u
    // yuqorida alohida "Saqlangan xabarlar" qatori sifatida ko'rsatiladi.
    final candidates = [...chat.inbox]
        .where((item) => item.username != me?.username)
        .toList()
      ..sort((left, right) {
        final leftTime = left.lastMessageAt?.millisecondsSinceEpoch ?? 0;
        final rightTime = right.lastMessageAt?.millisecondsSinceEpoch ?? 0;
        return rightTime.compareTo(leftTime);
      });

    final target = await showModalBottomSheet<InboxItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      builder: (sheetContext) => _ForwardPicker(
        settings: widget.settings,
        chat: chat,
        me: me,
        candidates: candidates,
        t: t,
      ),
    );

    if (target == null || !mounted) return;
    await _forwardMessagesToChat(chat, target, messages, t);
  }
}

/// Xabarni kimga uzatish — qidiruv bilan.
///
/// Ilgari bu yerda faqat mavjud suhbatlar ro'yxati turardi: hali yozishmagan
/// odamga xabar uzatib bo'lmasdi. Telegramda esa istalgan suhbat yoki
/// kontaktni qidirib topish mumkin, shuning uchun bu yerda ham qidiruv bor.
class _ForwardPicker extends StatefulWidget {
  const _ForwardPicker({
    required this.settings,
    required this.chat,
    required this.me,
    required this.candidates,
    required this.t,
  });

  final SettingsController settings;
  final ChatController chat;
  final SessionUser? me;
  final List<InboxItem> candidates;
  final String Function(String) t;

  @override
  State<_ForwardPicker> createState() => _ForwardPickerState();
}

class _ForwardPickerState extends State<_ForwardPicker> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchUser> _found = const [];
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    setState(() => _query = query);
    if (query.isEmpty) {
      setState(() {
        _found = const [];
        _searching = false;
      });
      return;
    }
    // Har harf uchun so'rov yubormaymiz — suhbatlar qidiruvidagi kabi.
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final result = await widget.chat.searchUsers(query);
        if (!mounted) return;
        setState(() {
          _found = result
              .where((user) => user.username != widget.me?.username)
              .toList(growable: false);
          _searching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _searching = false);
      }
    });
  }

  InboxItem _itemFor(SearchUser user) => InboxItem(
        username: user.username,
        fullName: user.fullName,
        avatar: user.avatar,
        lastActive: null,
        lastMessage: '',
        lastMessageAt: DateTime.now(),
        unreadCount: 0,
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final me = widget.me;
    final query = _query.toLowerCase();

    // Mavjud suhbatlar ham qidiruvga bo'ysunadi.
    final chats = query.isEmpty
        ? widget.candidates
        : widget.candidates
            .where((item) =>
                '${item.fullName} ${item.username}'
                    .toLowerCase()
                    .contains(query))
            .toList(growable: false);

    // Suhbatlarda bor odam qidiruv natijalarida takrorlanmasin.
    final known = chats.map((item) => item.username).toSet();
    final extra =
        _found.where((user) => !known.contains(user.username)).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Text(
                  t('message_forward_to'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: t('search_hint'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    // Telegramdagi kabi: xabarni o'zingizga saqlash uchun
                    // birinchi qator. Qidiruvda ham qoladi.
                    if (me != null && (query.isEmpty ||
                        t('chat_saved_messages').toLowerCase().contains(query)))
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: const Icon(Icons.bookmark_rounded,
                              color: Colors.white),
                        ),
                        title: Text(t('chat_saved_messages')),
                        onTap: () => Navigator.of(context).pop(
                          InboxItem(
                            username: me.username,
                            fullName: t('chat_saved_messages'),
                            avatar: me.avatar,
                            lastActive: null,
                            lastMessage: '',
                            lastMessageAt: DateTime.now(),
                            unreadCount: 0,
                          ),
                        ),
                      ),
                    for (final item in chats)
                      _ForwardTile(
                        settings: widget.settings,
                        avatar: item.avatar,
                        title: item.fullName,
                        subtitle: item.lastMessage,
                        onTap: () => Navigator.of(context).pop(item),
                      ),
                    if (_searching)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    // Hali yozishmagan odamlar — server qidiruvidan.
                    for (final user in extra)
                      _ForwardTile(
                        settings: widget.settings,
                        avatar: user.avatar,
                        title: user.fullName,
                        subtitle: '@${user.username}',
                        onTap: () =>
                            Navigator.of(context).pop(_itemFor(user)),
                      ),
                    if (!_searching &&
                        chats.isEmpty &&
                        extra.isEmpty &&
                        query.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(t('friend_search_hint'))),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForwardTile extends StatelessWidget {
  const _ForwardTile({
    required this.settings,
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final SettingsController settings;
  final String? avatar;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = AppConfig.resolveMediaUrl(avatar, settings.baseUrl);
    final hasAvatar = url.isNotEmpty;
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: hasAvatar ? avatarImage(url) : null,
        child: hasAvatar
            ? null
            : Text(title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase()),
      ),
      title: Text(title),
      subtitle: subtitle.trim().isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
