part of '../chat_page.dart';

extension _ConversationPanePreferences on _ConversationPaneState {
void _showInfoSnackBar(String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> _confirmChatAction({
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final localeCode = context.read<SettingsController>().localeCode;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppStrings.text(localeCode, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: destructive ? Colors.redAccent : null,
              ),
            ),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

String? _activeConversationKey() {
  final owner = context.read<AuthController>().user?.username;
  final peer = widget.chat.activeChat?.username;
  if (owner == null || peer == null || peer.isEmpty) {
    return null;
  }
  return '$owner::$peer';
}

String _pinnedMessagesStorageKey(String conversationKey) =>
    'bootchat.pinned_messages.$conversationKey';

Future<void> _restoreMessagePreferencesForActiveChat() async {
  final conversationKey = _activeConversationKey();
  if (conversationKey == null) {
    if (!mounted) {
      return;
    }
    setState(() {
      _messagePreferenceOwnerKey = null;
      _pinnedMessageIds = <int>{};
    });
    return;
  }

  if (_messagePreferenceOwnerKey == conversationKey) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final stored =
      prefs.getStringList(_pinnedMessagesStorageKey(conversationKey)) ??
          const <String>[];
  final ids = stored
      .map((value) => int.tryParse(value))
      .whereType<int>()
      .toSet();
  if (!mounted) {
    return;
  }

  setState(() {
    _messagePreferenceOwnerKey = conversationKey;
    _pinnedMessageIds = ids;
  });
}

Future<void> _persistPinnedMessages() async {
  final conversationKey = _messagePreferenceOwnerKey;
  if (conversationKey == null) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final ids = _pinnedMessageIds.toList()..sort();
  await prefs.setStringList(
    _pinnedMessagesStorageKey(conversationKey),
    ids.map((value) => '$value').toList(growable: false),
  );
}

void _requestScrollToNewest() {
  _scrollAfterNextMessage = true;
  _scheduleScrollToBottom(animated: true);
}

void _scheduleScrollToBottom({required bool animated}) {
  void doJump() {
    if (!mounted || !_messagesScrollController.hasClients) return;
    _messagesScrollController.jumpTo(
      _messagesScrollController.position.maxScrollExtent,
    );
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !_messagesScrollController.hasClients) return;
    final target = _messagesScrollController.position.maxScrollExtent;
    if (animated) {
      _messagesScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    // ListView.builder lazy — 3 frame davomida scroll qilamiz.
    doJump();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      doJump();
      WidgetsBinding.instance.addPostFrameCallback((_) => doJump());
    });
  });
}

void _insertEmoji(String emoji) {
  final selection = _messageController.selection;
  final text = _messageController.text;
  final start =
      selection.start >= 0 ? selection.start : _messageController.text.length;
  final end = selection.end >= 0 ? selection.end : start;
  final nextText = text.replaceRange(start, end, emoji);

  _messageController.value = TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: start + emoji.length),
  );
}

Future<void> _showEmojiPicker(String Function(String) t) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('chat_pick_emoji'),
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final emoji in _ConversationPaneState._quickEmojis)
                    InkWell(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _insertEmoji(emoji);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Ink(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: widget.settings.isDarkMode
                              ? Colors.white.withAlpha(18)
                              : const Color(0xFFF3F6FA),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
}
