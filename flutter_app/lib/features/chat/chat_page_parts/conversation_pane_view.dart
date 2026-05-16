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
          onPressed: () => widget.onMoreActions?.call(),
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
    final messages = chat.messages;
    return ListView.builder(
      controller: _messagesScrollController,
      padding: messagePadding,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final mine = message.senderUsername == currentUser?.username;
        final isPinned =
            message.id != null && _pinnedMessageIds.contains(message.id);

        // Sana separator: oldingi xabar boshqa kun bo'lsa ko'rsat
        final showDateSep = message.createdAt != null && (
          index == 0 ||
          messages[index - 1].createdAt == null ||
          !_isSameDay(messages[index - 1].createdAt!, message.createdAt!)
        );

        return Column(
          children: [
            if (showDateSep && message.createdAt != null)
              _DateSeparator(
                date: message.createdAt!,
                localeCode: widget.settings.localeCode,
                isDark: widget.settings.isDarkMode,
              ),
            _buildMessageBubble(
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
            ),
          ],
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({
    required this.date,
    required this.localeCode,
    required this.isDark,
  });

  final DateTime date;
  final String localeCode;
  final bool isDark;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    if (target == today) {
      return switch (localeCode) { 'ru' => 'Сегодня', 'en' => 'Today', _ => 'Bugun' };
    }
    if (target == today.subtract(const Duration(days: 1))) {
      return switch (localeCode) { 'ru' => 'Вчера', 'en' => 'Yesterday', _ => 'Kecha' };
    }
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d.$m.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E2C3A)
                : const Color(0xFFDCEAF5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _label(),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF8EA3B7) : const Color(0xFF5B7A9A),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}