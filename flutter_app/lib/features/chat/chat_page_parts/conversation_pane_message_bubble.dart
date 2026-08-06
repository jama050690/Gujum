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
    bool tightBelow = false,
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

    // Faqat matn bo'lsa vaqt/belgilar matn yoniga qo'yiladi; ilova bor
    // xabarlarda esa avvalgidek pastki qatorda qoladi.
    final inlineMeta = hasTextContent && !hasVideo && !hasImage && !hasAudio;

    final metaRow = Row(
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
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        // Faqat o'z xabarlarimizda: ✓ jo'natildi, ✓✓ o'qildi.
        if (isMine) ...[
          const SizedBox(width: 3),
          Icon(
            message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
            size: 14,
            // Media badge bilan bir xil rang — Telegram'dagi kabi farq
            // faqat bir yoki ikki belgida, rangda emas.
            color: const Color(0xFF6DB870),
          ),
        ],
      ],
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: selectionMode
            ? () => _toggleSelectedMessage(message)
            : onLongPress,
        onLongPress: onLongPress,
        child: Container(
          // Telegram pufakchani ekran kengligining ~78% i bilan cheklaydi.
          // Oldingi qat'iy 430dp telefon ekranidan kengroq edi — shuning uchun
          // pufakchalar deyarli butun qatorni egallab turardi.
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          // Ketma-ket bir odamning xabarlari orasida 2dp, muallif
          // almashganda 8dp — Telegram'dagi kabi.
          margin: EdgeInsets.only(bottom: tightBelow ? 2 : 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: bubbleColor,
            // "Dum" burchak: o'z tomonidagi pastki burchak kichikroq radiusda.
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 6),
              bottomRight: Radius.circular(isMine ? 6 : 16),
            ),
            border: isSelected
                ? Border.all(
                    color: const Color(0xFF419FD9),
                    width: 1.4,
                  )
                : null,
          ),
          child: AbsorbPointer(
            absorbing: selectionMode,
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Shaxsiy chatda jo'natuvchi ismi ko'rsatilmaydi — Telegram ham
                // uni faqat guruhlarda chiqaradi, bu esa 1:1 pane.
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
                  // Telegram vaqt va belgilarni matnning oxirgi qatoriga
                  // yondosh qo'yadi, alohida qatorga tushirmaydi.
                  inlineMeta
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                message.content,
                                style: const TextStyle(fontSize: 16, height: 1.25),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 1),
                              child: metaRow,
                            ),
                          ],
                        )
                      : Text(
                          message.content,
                          style: const TextStyle(fontSize: 16, height: 1.25),
                        ),
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
                if (!showMediaOverlay && !inlineMeta) ...[
                  const SizedBox(height: 4),
                  metaRow,
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
