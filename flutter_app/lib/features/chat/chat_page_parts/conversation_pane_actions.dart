part of '../chat_page.dart';

extension _ConversationPaneActions on _ConversationPaneState {
  Future<void> _deleteMessages(
    ChatController chat,
    String Function(String) t,
    List<ChatMessage> messages,
  ) async {
    final ids =
        messages.map((message) => message.id).whereType<int>().toList();
    if (ids.isEmpty) return;

    // Shaxsiy chatda ikkala tomonning xabarlarini ham hamma uchun o'chirish
    // mumkin — yozishma ikkovimizniki. Shuning uchun "Hamma uchun" har doim
    // taklif qilinadi, faqat o'z xabarlaringda emas.
    final peerName = widget.activeChat?.fullName ?? '';

    final forEveryone = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('message_delete')),
        content: Text(t('message_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('delete_for_me')),
          ),
          TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('${t('delete_for_everyone')}'
                  '${peerName.isEmpty ? '' : ' ($peerName)'}'),
            ),
        ],
      ),
    );
    if (forEveryone == null) return;

    try {
      await chat.deleteMessages(ids, forEveryone: forEveryone);
      await _pruneDeletedMessageState(ids.toSet());
    } on ApiException catch (error) {
      _showInfoSnackBar(error.message);
    } catch (_) {
      _showInfoSnackBar(t('message_action_failed'));
    }
  }

  Future<void> _showMessageActions(
    ChatController chat,
    ChatMessage message,
    bool mine,
    String Function(String) t,
  ) async {
    final isPinned =
        message.id != null && _pinnedMessageIds.contains(message.id);
    final canEdit = _canEditMessage(message, mine);
    final canDelete = _canDeleteMessage(message, mine);
    final canSelect = message.id != null;
    final canForward = _canForwardMessage(message);
    final canCopy = _canCopyMessage(message);
    final canSave = _canSaveMedia(message);

    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(t('message_reply')),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_MessageAction.reply),
              ),
              if (canCopy)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(t('message_copy')),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_MessageAction.copy),
                ),
              if (canSave)
                ListTile(
                  leading: const Icon(Icons.save_alt_rounded),
                  title: Text(t('message_save')),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_MessageAction.save),
                ),
              if (canEdit)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(t('message_edit')),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_MessageAction.edit),
                ),
              ListTile(
                leading: Icon(
                  isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                ),
                title: Text(
                    isPinned ? t('message_unpin') : t('message_pin')),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_MessageAction.pin),
              ),
              if (canForward)
                ListTile(
                  leading: const Icon(Icons.forward_rounded),
                  title: Text(t('message_forward')),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_MessageAction.forward),
                ),
              const Divider(height: 1),
              if (canDelete)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                  ),
                  title: Text(
                    t('message_delete'),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_MessageAction.delete),
                ),
              if (canSelect)
                ListTile(
                  leading: const Icon(Icons.check_circle_outline_rounded),
                  title: Text(t('message_select')),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_MessageAction.select),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _MessageAction.reply:
        _startReply(message);
        break;
      case _MessageAction.copy:
        await _copyMessage(message);
        break;
      case _MessageAction.save:
        await _saveMedia(message, t);
        break;
      case _MessageAction.edit:
        _startEdit(message, t);
        break;
      case _MessageAction.pin:
        await _togglePinnedMessage(message);
        break;
      case _MessageAction.forward:
        await _showForwardPicker(chat, t, <ChatMessage>[message]);
        break;
      case _MessageAction.delete:
        await _deleteMessages(chat, t, <ChatMessage>[message]);
        break;
      case _MessageAction.select:
        _toggleSelectedMessage(message);
        break;
    }
  }
}
