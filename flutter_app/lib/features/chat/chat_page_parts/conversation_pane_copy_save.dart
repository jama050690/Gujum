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
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
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
                          backgroundImage: item.avatar == null ||
                                  item.avatar!.trim().isEmpty
                              ? null
                              : avatarImage(avatarUrl),
                          child: item.avatar == null ||
                                  item.avatar!.trim().isEmpty
                              ? Text(item.fullName.trim().isEmpty
                                  ? '?'
                                  : item.fullName.trim()[0].toUpperCase())
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

    if (target == null || !mounted) return;
    await _forwardMessagesToChat(chat, target, messages, t);
  }
}
