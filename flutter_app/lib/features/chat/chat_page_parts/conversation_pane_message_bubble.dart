part of '../chat_page.dart';

extension _ConversationPaneMessageBubble on _ConversationPaneState {
  Widget _buildMessageBubble(
    BuildContext context, {
    required ChatMessage message,
    required bool isMine,
    required bool isPinned,
    required bool selectionMode,
    required String Function(String) t,
    required VoidCallback onLongPress,
  }) {
    final callInfo = _parseCallMessage(message.content);
    final locationInfo = _parseLocationMessage(message.content);
    final hasVideo = message.video != null && message.video!.isNotEmpty;
    final hasImage = message.image != null && message.image!.isNotEmpty;
    final imageIsMedia = hasImage && isImageAttachmentPath(message.image);
    final hasAudio = message.audio != null && message.audio!.isNotEmpty;
    final hasTextContent =
        message.content.isNotEmpty && callInfo == null && locationInfo == null;
    final showMediaOverlay = !hasTextContent &&
        callInfo == null &&
        locationInfo == null &&
        !hasAudio &&
        (hasVideo || imageIsMedia);
    final timeLabel = _formatClock(message.createdAt);
    final isSelected =
        message.id != null && _selectedMessageIds.contains(message.id);
    final bubbleColor = isMine
        ? (widget.settings.isDarkMode
            ? const Color(0xFF1D3A52)
            : const Color(0xFFD9EFFD))
        : (widget.settings.isDarkMode
            ? const Color(0xFF1E2A35)
            : Colors.white.withAlpha(235));

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: selectionMode
            ? () => _toggleSelectedMessage(message)
            : onLongPress,
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 430),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(18),
            border: isSelected
                ? Border.all(
                    color: const Color(0xFF419FD9),
                    width: 1.4,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(
                  widget.settings.isDarkMode ? 14 : 8,
                ),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AbsorbPointer(
            absorbing: selectionMode,
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.senderName,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                if (message.replyToUsername != null &&
                    message.replyToContent != null &&
                    message.replyToContent!.isNotEmpty)
                  _buildReplyPreview(context, message, t),
                if (callInfo != null)
                  _CallMessageTile(
                    info: callInfo,
                    isMine: isMine,
                    settings: widget.settings,
                  )
                else if (locationInfo != null)
                  _buildLocationChip(locationInfo, t)
                else if (message.content.isNotEmpty)
                  Text(message.content),
                if (message.video != null && message.video!.isNotEmpty)
                  _buildVideoAttachment(
                    message.video!,
                    t,
                    showTimeOverlay: showMediaOverlay,
                    timeLabel: timeLabel,
                    isMine: isMine,
                    isRead: message.isRead,
                  ),
                if (message.image != null && message.image!.isNotEmpty)
                  isImageAttachmentPath(message.image)
                      ? _buildImageAttachment(
                          message.image!,
                          showTimeOverlay: showMediaOverlay,
                          timeLabel: timeLabel,
                          isMine: isMine,
                          isRead: message.isRead,
                        )
                      : _buildFileChip(
                          icon: Icons.insert_drive_file_outlined,
                          label: _fileNameFromPath(message.image!),
                          onTap: () => _openRemoteFile(message.image!, t),
                        ),
                if (message.audio != null && message.audio!.isNotEmpty)
                  _buildAudioAttachment(message.audio!, isMine),
                if (!showMediaOverlay) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPinned) ...[
                        Icon(
                          Icons.push_pin_rounded,
                          size: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (isSelected) ...[
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 12,
                          color: Color(0xFF419FD9),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        timeLabel,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyPreview(
    BuildContext context,
    ChatMessage message,
    String Function(String) t,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${message.replyToUsername}: ${_parseLocationMessage(message.replyToContent) != null ? t('chat_location') : message.replyToContent}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
