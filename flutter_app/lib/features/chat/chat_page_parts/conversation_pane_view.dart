part of '../chat_page.dart';

extension _ConversationPaneView on _ConversationPaneState {
  Widget _buildConversationPane(BuildContext context) {
    final chat = widget.chat;
    final activeChat = chat.activeChat;
    String t(String key) => AppStrings.text(widget.settings.localeCode, key);
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
        // Telegram pufakchalarni ekran chetidan ~8dp da ushlaydi — 18dp
        // gorizontal padding matn uchun joyni keraksiz yeb qo'yardi.
        final messagePadding = compactHeight
            ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
            : const EdgeInsets.fromLTRB(8, 10, 8, 8);

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
              showBack: _chatSearchActive ? true : widget.showBack,
              onBack: _chatSearchActive ? _closeChatSearch : widget.onBack,
              // Qidiruv panelning o'zida ochiladi: ism, qo'ng'iroq va menyu
              // tugmalari o'rnini egallaydi (Telegramdagidek).
              searchField: _chatSearchActive
                  ? AppSearchField(
                      controller: _chatSearchController,
                      hintText: t('search_hint'),
                      onChanged: (value) =>
                          applyState(() => _chatSearchQuery = value),
                      onClose: _closeChatSearch,
                    )
                  : null,
              compact: compactHeight,
              onAvatarTap: selectionMode ? null : () {
                final url = AppConfig.resolveMediaUrl(
                    activeChat.avatar, widget.settings.baseUrl);
                if (url.isEmpty) return;
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ImageViewerPage(
                    imageUrl: url,
                    heroTag: 'avatar_${activeChat.username}',
                  ),
                ));
              },
              onTitleTap: selectionMode ? null : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ContactProfilePage(
                  username: activeChat.username,
                  displayName: activeChat.fullName,
                  lastSeenStatus: headerSubtitle,
                )),
              ),
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
          : chat.messagesLoadFailed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(t('messages_load_error'),
                          style: const TextStyle(color: Colors.grey)),
                      if (chat.messagesErrorDetail != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 8),
                          child: Text(
                            chat.messagesErrorDetail!,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.redAccent),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () =>
                            unawaited(widget.chat.reloadActiveChat()),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(t('retry')),
                      ),
                    ],
                  ),
                )
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
    // Qidiruv yoqilgan bo'lsa faqat mos xabarlar ko'rsatiladi.
    final query = _chatSearchQuery.trim().toLowerCase();
    final messages = query.isEmpty
        ? chat.messages
        : chat.messages
            .where((m) => m.content.toLowerCase().contains(query))
            .toList();
    return Stack(
      children: [
        // Ro'yxat teskari, shuning uchun "tepaga yetish" = oxiriga yetish.
        // Foydalanuvchi eski xabarlarga qarab borganda keyingi bo'lak
        // oldindan so'raladi — ro'yxat tugab, to'xtab qolishini kutmaymiz.
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (query.isEmpty &&
                notification.metrics.extentAfter < 600 &&
                chat.hasMoreOlder &&
                !chat.loadingOlder) {
              unawaited(chat.loadOlderMessages());
            }
            return false;
          },
          child: ListView.builder(
      reverse: true,
      controller: _messagesScrollController,
      padding: messagePadding,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        // reverse tartibda: index 0 = so'nggi xabar, index N-1 = birinchi xabar
        final msgIndex = messages.length - 1 - index;
        final message = messages[msgIndex];
        final mine = message.senderUsername == currentUser?.username;
        final isPinned =
            message.id != null && _pinnedMessageIds.contains(message.id);

        // Sana separator: bu xabardan oldingi (katta) xabar boshqa kun bo'lsa ko'rsat
        final showDateSep = message.createdAt != null && (
          msgIndex == 0 ||
          messages[msgIndex - 1].createdAt == null ||
          !_isSameDay(messages[msgIndex - 1].createdAt!, message.createdAt!)
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
              // Pastdagi xabar ham shu odamniki bo'lsa — zich joylashtiramiz.
              tightBelow: msgIndex + 1 < messages.length &&
                  messages[msgIndex + 1].senderUsername ==
                      message.senderUsername,
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
        ),
        ),
        if (_showScrollToBottom)
          Positioned(
            right: 12,
            bottom: 12,
            child: GestureDetector(
              onTap: () => _messagesScrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              ),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2535),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(100),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

