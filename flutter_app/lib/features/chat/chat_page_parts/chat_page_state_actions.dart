part of '../chat_page.dart';

extension _ChatPageStateActions on _ChatPageState {
Future<void> _showChatActions(
  BuildContext context,
  ChatController chat,
  InboxItem item,
  SettingsController settings,
) async {
  final t = (String key) => AppStrings.text(settings.localeCode, key);
  final isArchived = _archivedChats.contains(item.username);
  final isPinned = _pinnedChats.contains(item.username);
  final isMuted = _mutedChats.contains(item.username);

  final action = await showModalBottomSheet<_InboxAction>(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    builder: (context) {
      return SafeArea(
        child: Wrap(
          children: [
            // "Yangi oynada ochish" faqat vebda ma'noga ega. Telefonda u
            // shunchaki chatni ochadi — va menyu chatning o'zidan ochilgan
            // bo'lsa, umuman hech narsa qilmaydi. Shuning uchun matn
            // platformaga qarab tanlanadi va chat allaqachon ochiq bo'lsa
            // band ko'rsatilmaydi.
            if (chat.activeChat?.username != item.username)
              ListTile(
                leading: Icon(
                  kIsWeb ? Icons.open_in_new_rounded : Icons.chat_bubble_outline,
                ),
                title: Text(
                  kIsWeb ? t('chat_open_in_new_window') : t('open_chat'),
                ),
                onTap: () => Navigator.of(context).pop(_InboxAction.open),
              ),
            ListTile(
              leading: Icon(
                isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              title:
                  Text(isArchived ? t('chat_unarchive') : t('chat_archive')),
              onTap: () => Navigator.of(context).pop(_InboxAction.archive),
            ),
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              ),
              title: Text(isPinned ? t('chat_unpin') : t('chat_pin')),
              onTap: () => Navigator.of(context).pop(_InboxAction.pin),
            ),
            ListTile(
              leading: Icon(
                isMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              ),
              title: Text(isMuted ? t('chat_unmute') : t('chat_mute')),
              onTap: () => Navigator.of(context).pop(_InboxAction.mute),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(t('chat_clear_history')),
              onTap: () =>
                  Navigator.of(context).pop(_InboxAction.clearHistory),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: Text(
                t('chat_delete'),
                style: const TextStyle(color: Colors.redAccent),
              ),
              onTap: () => Navigator.of(context).pop(_InboxAction.deleteChat),
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded, color: Colors.redAccent),
              title: Text(
                t('chat_block'),
                style: const TextStyle(color: Colors.redAccent),
              ),
              onTap: () => Navigator.of(context).pop(_InboxAction.block),
            ),
          ],
        ),
      );
    },
  );

  if (!mounted || action == null) {
    return;
  }

  try {
    switch (action) {
      case _InboxAction.open:
        await _openInboxChat(chat, item);
        break;
      case _InboxAction.archive:
        await _toggleArchive(chat, item);
        break;
      case _InboxAction.pin:
        await _togglePin(item);
        break;
      case _InboxAction.mute:
        await _toggleMute(item);
        break;
      case _InboxAction.markUnread:
        if (chat.activeChat?.username == item.username && !_showSavedMessages) {
          chat.closeChat();
        }
        chat.markChatUnread(item.username);
        break;
      case _InboxAction.clearHistory:
        if (!await _confirmChatAction(
          title: t('chat_clear_history'),
          message: t('chat_clear_history_confirm'),
          confirmLabel: t('chat_clear_history'),
        )) {
          return;
        }
        await chat.clearChatHistory(item.username);
        break;
      case _InboxAction.deleteChat:
        if (!await _confirmChatAction(
          title: t('chat_delete'),
          message: t('chat_delete_confirm'),
          confirmLabel: t('chat_delete'),
          destructive: true,
        )) {
          return;
        }
        await chat.deleteChat(item.username);
        await _removeChatPreferences(item.username);
        break;
      case _InboxAction.block:
        if (!await _confirmChatAction(
          title: t('chat_block'),
          message: t('chat_block_confirm'),
          confirmLabel: t('chat_block'),
          destructive: true,
        )) {
          return;
        }
        if (!mounted) return;
        await context.read<SocialRepository>().blockUser(item.username);
        chat.removeChat(item.username);
        await _removeChatPreferences(item.username);
        break;
    }
  } on ApiException catch (error) {
    _showInfoSnackBar(error.message);
  } catch (_) {
    _showInfoSnackBar(t('chat_action_failed'));
  }
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

bool _hasConversation(ChatController chat) =>
    _showSavedMessages || chat.activeChat != null;
}
