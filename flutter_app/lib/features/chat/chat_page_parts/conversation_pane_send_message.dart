part of '../chat_page.dart';

extension _ConversationPaneSendMessage on _ConversationPaneState {
Future<void> _sendCurrentMessage(
  ChatController chat,
  String Function(String) t,
) async {
  final text = _messageController.text.trim();
  if (_editingMessage != null) {
    final editing = _editingMessage!;
    if (text.isEmpty || editing.id == null) {
      return;
    }

    try {
      final updated = await chat.updateActiveMessage(
        id: editing.id!,
        message: text,
      );
      if (updated != null) {
        _messageController.clear();
        if (!mounted) return;
        applyState(() => _editingMessage = null);
        _requestScrollToNewest();
        return;
      }
    } on ApiException catch (error) {
      _showInfoSnackBar(error.message);
      return;
    } catch (_) {
      if (mounted) {
        _showInfoSnackBar(t('message_action_failed'));
      }
      return;
    }
  }

  if (text.isEmpty) {
    return;
  }

  final sent = await chat.sendMessage(
    message: text,
    replyTo: _replyPayloadForMessage(_replyingTo, t),
  );
  if (sent) {
    _messageController.clear();
    if (_replyingTo != null) {
      applyState(() => _replyingTo = null);
    }
    _requestScrollToNewest();
    return;
  }
  if (!mounted) {
    return;
  }
  _showInfoSnackBar(t('message_send_failed'));
}

Future<void> _showAttachmentPicker(
  ChatController chat,
  String Function(String) t,
) async {
  if (_uploadingAttachment) {
    return;
  }
  if (_editingMessage != null) {
    _showInfoSnackBar(t('message_edit_attachment_unavailable'));
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      return _AttachmentPickerSheet(
        settings: widget.settings,
        t: t,
        onSelectAction: (type) {
          Navigator.of(sheetContext).pop();
          _pickAndSendAttachment(chat, t, type);
        },
      );
    },
  );
}
}
