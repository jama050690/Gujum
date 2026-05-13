part of '../chat_page.dart';

extension _ConversationPaneHeaderActions on _ConversationPaneState {
Widget _buildHeaderActions(String Function(String) t) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _HeaderActionButton(
        icon: Icons.search_rounded,
        onPressed: () => _showInfoSnackBar(t('chat_action_unavailable')),
      ),
      _HeaderActionButton(
        icon: Icons.call_outlined,
        onPressed: () => _startCall(video: false),
      ),
      _HeaderActionButton(
        icon: Icons.videocam_outlined,
        onPressed: () => _startCall(video: true),
      ),
      _HeaderActionButton(
        icon: Icons.more_vert_rounded,
        onPressed: () => widget.onMoreActions?.call(),
      ),
    ],
  );
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
}
