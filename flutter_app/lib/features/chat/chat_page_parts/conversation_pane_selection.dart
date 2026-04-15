part of '../chat_page.dart';

extension _ConversationPaneSelection on _ConversationPaneState {
String _messagePreviewText(
  ChatMessage message,
  String Function(String) t,
) {
  final text = message.content.trim();
  if (text.isNotEmpty) {
    final location = _parseLocationMessage(text);
    if (location != null) {
      return t('chat_location');
    }
    return text;
  }
  if (message.video != null && message.video!.isNotEmpty) {
    return t('chat_video');
  }
  if (message.image != null && message.image!.isNotEmpty) {
    return t('chat_photo');
  }
  if (message.audio != null && message.audio!.isNotEmpty) {
    return t('chat_voice_message');
  }
  return '';
}

Map<String, String?>? _replyPayloadForMessage(
  ChatMessage? message,
  String Function(String) t,
) {
  if (message == null) {
    return null;
  }
  return {
    'username': message.senderUsername,
    'content': _messagePreviewText(message, t),
  };
}

bool _messageHasAttachment(ChatMessage message) {
  return (message.image?.trim().isNotEmpty ?? false) ||
      (message.audio?.trim().isNotEmpty ?? false) ||
      (message.video?.trim().isNotEmpty ?? false);
}

bool _canEditMessage(ChatMessage message, bool mine) {
  return mine &&
      message.id != null &&
      message.content.trim().isNotEmpty &&
      _parseCallMessage(message.content) == null &&
      _parseLocationMessage(message.content) == null;
}

bool _canDeleteMessage(ChatMessage message, bool mine) {
  return mine && message.id != null;
}

bool _canForwardMessage(ChatMessage message) {
  return message.content.trim().isNotEmpty || _messageHasAttachment(message);
}

List<ChatMessage> _selectedMessages(List<ChatMessage> messages) {
  return messages
      .where(
        (message) =>
            message.id != null && _selectedMessageIds.contains(message.id),
      )
      .toList(growable: false);
}

void _clearSelection() {
  if (_selectedMessageIds.isEmpty) {
    return;
  }
  setState(() => _selectedMessageIds = <int>{});
}

void _clearReply() {
  if (_replyingTo == null) {
    return;
  }
  setState(() => _replyingTo = null);
}

void _clearEdit({bool clearText = true}) {
  if (_editingMessage == null) {
    return;
  }
  setState(() {
    _editingMessage = null;
    if (clearText) {
      _messageController.clear();
    }
  });
}

void _startReply(ChatMessage message) {
  setState(() {
    _replyingTo = message;
    _selectedMessageIds = <int>{};
    if (_editingMessage != null) {
      _editingMessage = null;
      _messageController.clear();
    }
  });
}

void _startEdit(
  ChatMessage message,
  String Function(String) t,
) {
  if (message.content.trim().isEmpty) {
    _showInfoSnackBar(t('message_edit_attachment_unavailable'));
    return;
  }

  setState(() {
    _editingMessage = message;
    _replyingTo = null;
    _selectedMessageIds = <int>{};
  });
  _messageController.value = TextEditingValue(
    text: message.content,
    selection: TextSelection.collapsed(offset: message.content.length),
  );
}

void _toggleSelectedMessage(ChatMessage message) {
  final messageId = message.id;
  if (messageId == null) {
    return;
  }

  final next = <int>{..._selectedMessageIds};
  if (next.contains(messageId)) {
    next.remove(messageId);
  } else {
    next.add(messageId);
  }

  setState(() {
    _selectedMessageIds = next;
    _replyingTo = null;
    if (_editingMessage != null) {
      _editingMessage = null;
      _messageController.clear();
    }
  });
}

Future<void> _togglePinnedMessage(ChatMessage message) async {
  final messageId = message.id;
  if (messageId == null) {
    return;
  }

  final next = <int>{..._pinnedMessageIds};
  if (next.contains(messageId)) {
    next.remove(messageId);
  } else {
    next.add(messageId);
  }
  setState(() => _pinnedMessageIds = next);
  await _persistPinnedMessages();
}

Future<void> _pruneDeletedMessageState(Set<int> ids) async {
  if (ids.isEmpty) {
    return;
  }

  var pinnedChanged = false;
  setState(() {
    _selectedMessageIds.removeAll(ids);
    final previousPinnedCount = _pinnedMessageIds.length;
    _pinnedMessageIds.removeAll(ids);
    pinnedChanged = previousPinnedCount != _pinnedMessageIds.length;

    if (_replyingTo?.id != null && ids.contains(_replyingTo!.id)) {
      _replyingTo = null;
    }

    if (_editingMessage?.id != null && ids.contains(_editingMessage!.id)) {
      _editingMessage = null;
      _messageController.clear();
    }
  });

  if (pinnedChanged) {
    await _persistPinnedMessages();
  }
}
}
