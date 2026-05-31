part of '../chat_page.dart';

extension _ConversationPaneComposer on _ConversationPaneState {
  Widget _buildComposerArea(
    BuildContext context,
    bool compactHeight,
    ChatController chat,
    String Function(String) t,
  ) {
    return SafeArea(
      top: false,
      child: Container(
        padding: compactHeight
            ? const EdgeInsets.fromLTRB(8, 6, 8, 8)
            : const EdgeInsets.fromLTRB(10, 10, 10, 12),
        decoration: BoxDecoration(
          color: widget.settings.isDarkMode
              ? const Color(0xFF18222C)
              : const Color(0xFFF5F7FA),
          border: Border(
            top: BorderSide(
              color: widget.settings.isDarkMode
                  ? Colors.white.withAlpha(14)
                  : const Color(0xFFE4E8EE),
            ),
          ),
        ),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _messageController,
          builder: (context, value, _) {
            final hasText = value.text.trim().isNotEmpty && !_isRecordingVoice;
            final showSendButton =
                !_isRecordingVoice && (hasText || _editingMessage != null);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_editingMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ComposerContextBanner(
                      icon: Icons.edit_outlined,
                      title: t('message_editing'),
                      subtitle: _messagePreviewText(_editingMessage!, t),
                      settings: widget.settings,
                      onClose: () => _clearEdit(),
                    ),
                  )
                else if (_replyingTo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ComposerContextBanner(
                      icon: Icons.reply_rounded,
                      title: t('message_replying_to'),
                      subtitle:
                          '${_replyingTo!.senderName}: ${_messagePreviewText(_replyingTo!, t)}',
                      settings: widget.settings,
                      onClose: _clearReply,
                    ),
                  ),
                if (_uploadingAttachment)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          t('loading'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ComposerActionButton(
                      icon: Icons.attach_file_rounded,
                      compact: compactHeight,
                      onPressed: () => _showAttachmentPicker(chat, t),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildComposerInput(context, compactHeight, chat, t),
                    ),
                    const SizedBox(width: 6),
                    _ComposerActionButton(
                      icon: _isRecordingVoice
                          ? Icons.close_rounded
                          : Icons.emoji_emotions_outlined,
                      compact: compactHeight,
                      onPressed: _isRecordingVoice
                          ? _cancelVoiceRecording
                          : () => _showEmojiPicker(t),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: showSendButton
                          ? _ComposerActionButton(
                              key: ValueKey(
                                _editingMessage != null ? 'save-edit' : 'send',
                              ),
                              icon: _editingMessage != null
                                  ? Icons.check_rounded
                                  : Icons.send_rounded,
                              compact: compactHeight,
                              color: const Color(0xFF419FD9),
                              onPressed: () => _sendCurrentMessage(chat, t),
                            )
                          : _ComposerActionButton(
                              key: ValueKey(
                                _isRecordingVoice ? 'record-stop' : 'mic',
                              ),
                              icon: _isRecordingVoice
                                  ? Icons.stop_rounded
                                  : Icons.mic_none_rounded,
                              compact: compactHeight,
                              color: _isRecordingVoice
                                  ? const Color(0xFFE35555)
                                  : null,
                              onPressed: () => _toggleVoiceRecording(chat, t),
                            ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildComposerInput(
    BuildContext context,
    bool compactHeight,
    ChatController chat,
    String Function(String) t,
  ) {
    if (_isRecordingVoice) {
      return Container(
        constraints: BoxConstraints(minHeight: compactHeight ? 40 : 48),
        padding: EdgeInsets.symmetric(
          horizontal: compactHeight ? 14 : 16,
          vertical: compactHeight ? 10 : 13,
        ),
        decoration: BoxDecoration(
          color: widget.settings.isDarkMode
              ? const Color(0xFF24313D)
              : const Color(0xFFF9FAFC),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: widget.settings.isDarkMode
                ? Colors.white.withAlpha(14)
                : const Color(0xFFD9DEE6),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.fiber_manual_record_rounded,
              color: Color(0xFFE35555),
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${t('chat_voice_recording')} ${_formatCallDuration(_recordingSeconds)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(minHeight: compactHeight ? 40 : 48),
      decoration: BoxDecoration(
        color: widget.settings.isDarkMode
            ? const Color(0xFF24313D)
            : const Color(0xFFF9FAFC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.settings.isDarkMode
              ? Colors.white.withAlpha(14)
              : const Color(0xFFD9DEE6),
        ),
      ),
      child: TextField(
        controller: _messageController,
        focusNode: _composerFocusNode,
        minLines: 1,
        maxLines: compactHeight ? 3 : 5,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _sendCurrentMessage(chat, t),
        decoration: InputDecoration(
          hintText: t('type_message'),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: compactHeight ? 14 : 16,
            vertical: compactHeight ? 10 : 13,
          ),
        ),
      ),
    );
  }
}
