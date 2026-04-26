part of '../chat_page.dart';

extension _ConversationPaneView on _ConversationPaneState {
  Widget _buildConversationPane(BuildContext context) {
    final chat = widget.chat;
    final activeChat = chat.activeChat;
    final t = (String key) => AppStrings.text(widget.settings.localeCode, key);
    final currentUser = context.read<AuthController>().user;
    final appTitle = t('app_title');

    if (widget.showSavedMessages) {
      return _SavedMessagesPane(
        settings: widget.settings,
        showBack: widget.showBack,
        onBack: widget.onBack,
      );
    }

    if (activeChat == null) {
      return _ChatBackdrop(
        settings: widget.settings,
        child: _BrandEmptyState(
          settings: widget.settings,
          title: appTitle,
          subtitle: t('empty_chat'),
        ),
      );
    }

    final online = chat.onlineUsers.contains(activeChat.username);
    final lastActive = chat.lastActiveFor(activeChat.username);
    final selectedMessages = _selectedMessages(chat.messages);
    final selectionMode = selectedMessages.isNotEmpty;
    final headerTitle = selectionMode
        ? '${selectedMessages.length} ${t('message_selected')}'
        : activeChat.fullName;
    final headerSubtitle = selectionMode
        ? activeChat.fullName
        : online
            ? t('online')
            : _formatLastSeenStatus(lastActive, widget.settings.localeCode);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 220;
        final messagePadding = compactHeight
            ? const EdgeInsets.fromLTRB(12, 10, 12, 6)
            : const EdgeInsets.fromLTRB(18, 18, 18, 8);

        return Column(
          children: [
            _ConversationHeader(
              settings: widget.settings,
              title: headerTitle,
              subtitle: headerSubtitle,
              label: activeChat.fullName,
              imageUrl: AppConfig.resolveMediaUrl(
                activeChat.avatar,
                widget.settings.baseUrl,
              ),
              showBack: widget.showBack,
              onBack: widget.onBack,
              compact: compactHeight,
              trailing: compactHeight
                  ? null
                  : selectionMode
                      ? _buildSelectionHeaderActions(t, chat, selectedMessages)
                      : _buildHeaderActions(t),
            ),
            Expanded(
              child: _buildConversationBody(
                context,
                chat,
                activeChat,
                currentUser,
                t,
                selectionMode,
                messagePadding,
              ),
            ),
            _buildComposerArea(context, compactHeight, chat, t),
          ],
        );
      },
    );
  }

  // --- HEADER ACTIONS (Build xatolarsiz variant) ---
  Widget _buildHeaderActions(String Function(String) t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Audio qo'ng'iroq (video: false)
        IconButton(
          icon: const Icon(Icons.phone_outlined),
          onPressed: () => _startCall(video: false), 
        ),
        // Video qo'ng'iroq (video: true)
        IconButton(
          icon: const Icon(Icons.videocam_outlined),
          onPressed: () => _startCall(video: true), 
        ),
        // Menyu tugmasi
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () {
             // Chat menyusi logikasi
          },
        ),
      ],
    );
  }

  Widget _buildConversationBody(
    BuildContext context,
    ChatController chat,
    InboxItem activeChat,
    SessionUser? currentUser,
    String Function(String) t,
    bool selectionMode,
    EdgeInsets messagePadding,
  ) {
    return _ChatBackdrop(
      settings: widget.settings,
      child: chat.loadingMessages
          ? const Center(child: CircularProgressIndicator())
          : chat.messages.isEmpty
              ? _BrandEmptyState(
                  settings: widget.settings,
                  title: activeChat.fullName,
                  subtitle: t('type_message'),
                )
              : _buildMessagesList(
                  context,
                  chat,
                  currentUser,
                  t,
                  selectionMode,
                  messagePadding,
                ),
    );
  }

  Widget _buildMessagesList(
    BuildContext context,
    ChatController chat,
    SessionUser? currentUser,
    String Function(String) t,
    bool selectionMode,
    EdgeInsets messagePadding,
  ) {
    return ListView.builder(
      controller: _messagesScrollController,
      padding: messagePadding,
      itemCount: chat.messages.length,
      itemBuilder: (context, index) {
        final message = chat.messages[index];
        final mine = message.senderUsername == currentUser?.username;
        final isPinned =
            message.id != null && _pinnedMessageIds.contains(message.id);
        return _buildMessageBubble(
          context,
          message: message,
          isMine: mine,
          isPinned: isPinned,
          selectionMode: selectionMode,
          t: t,
          onLongPress: () {
            if (selectionMode) {
              _toggleSelectedMessage(message);
              return;
            }
            _showMessageActions(chat, message, mine, t);
          },
        );
      },
    );
  }
}