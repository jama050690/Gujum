part of '../chat_page.dart';

extension _ConversationPaneActions on _ConversationPaneState {
Future<void> _deleteMessages(
  ChatController chat,
  String Function(String) t,
  List<ChatMessage> messages,
) async {
  final ids =
      messages.map((message) => message.id).whereType<int>().toList();
  if (ids.isEmpty) {
    return;
  }

  final confirmed = await _confirmChatAction(
    title: t('message_delete'),
    message: t('message_delete_confirm'),
    confirmLabel: t('message_delete'),
    destructive: true,
  );
  if (!confirmed) {
    return;
  }

  try {
    for (final id in ids) {
      await chat.deleteActiveMessage(id);
    }
    await _pruneDeletedMessageState(ids.toSet());
  } on ApiException catch (error) {
    _showInfoSnackBar(error.message);
  } catch (_) {
    _showInfoSnackBar(t('message_action_failed'));
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
      if (mounted) {
        _showInfoSnackBar(t('message_send_failed'));
      }
      return;
    }
  }

  if (!mounted) {
    return;
  }
  setState(() => _selectedMessageIds = <int>{});
  _showInfoSnackBar(t('done'));
}

Future<void> _showForwardPicker(
  ChatController chat,
  String Function(String) t,
  List<ChatMessage> messages,
) async {
  final candidates = [...chat.inbox]
    ..sort((left, right) {
      final leftTime = left.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      final rightTime = right.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      return rightTime.compareTo(leftTime);
    });
  if (candidates.isEmpty) {
    _showInfoSnackBar(t('empty_inbox'));
    return;
  }

  final target = await showModalBottomSheet<InboxItem>(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    builder: (sheetContext) {
      return SafeArea(
        child: SizedBox(
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Text(
                  t('message_forward_to'),
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final item = candidates[index];
                    final avatarUrl = AppConfig.resolveMediaUrl(
                      item.avatar,
                      widget.settings.baseUrl,
                    );
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            item.avatar == null || item.avatar!.trim().isEmpty
                                ? null
                                : NetworkImage(avatarUrl),
                        child: item.avatar == null || item.avatar!.trim().isEmpty
                            ? Text(
                                item.fullName.trim().isEmpty
                                    ? '?'
                                    : item.fullName.trim()[0].toUpperCase(),
                              )
                            : null,
                      ),
                      title: Text(item.fullName),
                      subtitle: item.lastMessage.trim().isEmpty
                          ? null
                          : Text(
                              item.lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => Navigator.of(sheetContext).pop(item),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (target == null || !mounted) {
    return;
  }
  await _forwardMessagesToChat(chat, target, messages, t);
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
              onTap: () => Navigator.of(sheetContext).pop(_MessageAction.reply),
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
                isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              ),
              title: Text(isPinned ? t('message_unpin') : t('message_pin')),
              onTap: () => Navigator.of(sheetContext).pop(_MessageAction.pin),
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

  if (!mounted || action == null) {
    return;
  }

  switch (action) {
    case _MessageAction.reply:
      _startReply(message);
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
