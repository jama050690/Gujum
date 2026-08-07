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
      _HeaderActionButton(
        icon: Icons.more_vert_rounded,
        onPressed: () => _showHeaderMenu(t),
      ),
    ],
  );
}

/// Uch nuqta menyusi: video qo'ng'iroq, ovozli qo'ng'iroq (sarlavhadagining
/// takrori) va qidiruv. Oxirida chat amallari — arxiv, tozalash va boshqalar.
Future<void> _showHeaderMenu(String Function(String) t) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: Text(t('call_video')),
            onTap: () => Navigator.of(sheetContext).pop('video'),
          ),
          ListTile(
            leading: const Icon(Icons.call_outlined),
            title: Text(t('call_audio')),
            onTap: () => Navigator.of(sheetContext).pop('audio'),
          ),
          ListTile(
            leading: const Icon(Icons.search_rounded),
            title: Text(t('search')),
            onTap: () => Navigator.of(sheetContext).pop('search'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.more_horiz_rounded),
            title: Text(t('chat_more_actions')),
            onTap: () => Navigator.of(sheetContext).pop('more'),
          ),
        ],
      ),
    ),
  );

  if (!mounted || action == null) return;
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

/// Suhbat ichidagi qidiruv paneli.
///
/// Xabarlar qurilmada saqlanadi, shuning uchun qidiruv butunlay mahalliy:
/// tarmoqqa chiqilmaydi, kutish yo'q — har bosilgan harfda ro'yxat darhol
/// filtrlanadi.
Widget _buildChatSearchBar(String Function(String) t) {
  return Material(
    color: Theme.of(context).cardColor,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatSearchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t('search_hint'),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _chatSearchQuery = value),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              _chatSearchController.clear();
              setState(() {
                _chatSearchQuery = '';
                _chatSearchActive = false;
              });
            },
          ),
        ],
      ),
    ),
  );
}
}
