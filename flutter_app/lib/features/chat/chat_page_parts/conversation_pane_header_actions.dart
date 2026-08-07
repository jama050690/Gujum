part of '../chat_page.dart';

extension _ConversationPaneHeaderActions on _ConversationPaneState {
Widget _buildHeaderActions(String Function(String) t) {
  // Sarlavhada faqat qo'ng'iroq tugmasi qoladi; qidiruv va video qo'ng'iroq
  // uch nuqta menyusiga ko'chirildi.
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _HeaderActionButton(
        icon: Icons.call_outlined,
        onPressed: () => _startCall(video: false),
      ),
      // Telegram uch nuqta menyusini tugmaning yoniga ochadi — pastdan
      // ko'tariladigan varaq emas. Shu sababli PopupMenuButton.
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded),
        position: PopupMenuPosition.under,
        onSelected: (value) => _onHeaderMenuSelected(value, t),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'video',
            child: Row(children: [
              const Icon(Icons.videocam_outlined),
              const SizedBox(width: 14),
              Text(t('call_video')),
            ]),
          ),
          PopupMenuItem(
            value: 'audio',
            child: Row(children: [
              const Icon(Icons.call_outlined),
              const SizedBox(width: 14),
              Text(t('call_audio')),
            ]),
          ),
          PopupMenuItem(
            value: 'search',
            child: Row(children: [
              const Icon(Icons.search_rounded),
              const SizedBox(width: 14),
              Text(t('search')),
            ]),
          ),
          PopupMenuItem(
            value: 'clear',
            child: Row(children: [
              const Icon(Icons.cleaning_services_outlined),
              const SizedBox(width: 14),
              Text(t('chat_clear_history')),
            ]),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              const Icon(Icons.delete_outline_rounded),
              const SizedBox(width: 14),
              Text(t('chat_delete')),
            ]),
          ),
          PopupMenuItem(
            value: 'more',
            child: Row(children: [
              const Icon(Icons.more_horiz_rounded),
              const SizedBox(width: 14),
              Text(t('chat_more_actions')),
            ]),
          ),
        ],
      ),
    ],
  );
}

/// Uch nuqta menyusidagi tanlov.
Future<void> _onHeaderMenuSelected(String action, String Function(String) t) async {
  final chat = widget.chat;
  final peer = chat.activeChat?.username;
  switch (action) {
    case 'video':
      _startCall(video: true);
      break;
    case 'audio':
      _startCall(video: false);
      break;
    case 'search':
      setState(() => _chatSearchActive = true);
      break;
    case 'clear':
      if (peer == null) return;
      if (!await _confirmChatAction(
        title: t('chat_clear_history'),
        message: t('chat_clear_history_confirm'),
        confirmLabel: t('chat_clear_history'),
        destructive: true,
      )) {
        return;
      }
      await chat.clearChatHistory(peer);
      break;
    case 'delete':
      if (peer == null) return;
      if (!await _confirmChatAction(
        title: t('chat_delete'),
        message: t('chat_delete_confirm'),
        confirmLabel: t('chat_delete'),
        destructive: true,
      )) {
        return;
      }
      await chat.deleteChat(peer);
      break;
    case 'more':
      widget.onMoreActions?.call();
      break;
  }
}

Widget _buildSelectionHeaderActions(
  String Function(String) t,
  ChatController chat,
  List<ChatMessage> selectedMessages,
) {
  final currentUsername = context.read<AuthController>().user?.username;
  final canDelete = selectedMessages.isNotEmpty &&
      selectedMessages.every(
        (message) =>
            _canDeleteMessage(message, message.senderUsername == currentUsername),
      );

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _HeaderActionButton(
        icon: Icons.forward_rounded,
        onPressed: () => _showForwardPicker(chat, t, selectedMessages),
      ),
      if (canDelete)
        _HeaderActionButton(
          icon: Icons.delete_outline_rounded,
          onPressed: () => _deleteMessages(chat, t, selectedMessages),
        ),
      _HeaderActionButton(
        icon: Icons.close_rounded,
        onPressed: _clearSelection,
      ),
    ],
  );
}

void _startCall({required bool video}) {
  final activeChat = widget.chat.activeChat;
  if (activeChat == null) {
    return;
  }

  final controller = context.read<CallController>();
  final peer = CallPeer(
    username: activeChat.username,
    displayName: activeChat.fullName,
    avatar: activeChat.avatar,
  );
  unawaited(controller.startCall(peer, video: video));
}

/// Suhbat ichidagi qidiruvni yopadi.
///
/// Xabarlar qurilmada saqlanadi, shuning uchun qidiruv butunlay mahalliy:
/// tarmoqqa chiqilmaydi, kutish yo'q — har bosilgan harfda ro'yxat darhol
/// filtrlanadi.
void _closeChatSearch() {
  _chatSearchController.clear();
  setState(() {
    _chatSearchQuery = '';
    _chatSearchActive = false;
  });
}
}
