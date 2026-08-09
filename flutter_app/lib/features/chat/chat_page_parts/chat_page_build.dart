part of '../chat_page.dart';

extension _ChatPageStateBuild on _ChatPageState {
  Widget _buildChatPageScaffold(
    BuildContext context,
    SettingsController settings,
    AuthController auth,
    ChatController chat,
  ) {
    return Scaffold(

      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          final inboxPanel = _UsersPanel(
            settings: settings,
            chat: chat,
            currentUser: auth.user,
            searchController: _searchController,
            showArchived: chat.showArchived,
            archivedChats: _archivedChats,
            pinnedChats: _pinnedChats,
            mutedChats: _mutedChats,
            showSavedMessages: chat.showSavedMessages,
            globalResults: _globalResults,
            loadingGlobalSearch: _loadingGlobalSearch,
            onSearchChanged: (value) => _handleSearchChanged(chat, value),
            onShowArchived: chat.openArchive,
            onHideArchived: chat.closeArchive,
            onOpenSavedMessages: () => _openSavedMessages(chat),
            onOpenChat: (item) => _openInboxChat(chat, item),
            onOpenSearchResult: (user) => _openChatFromSearch(chat, user),
            onShowChatActions: (item) =>
                _showChatActions(context, chat, item, settings),
          );

          final conversation = _ConversationPane(
            settings: settings,
            chat: chat,
            showBack: !wide,
            showSavedMessages: chat.showSavedMessages,
            onBack: () => _closeConversation(chat),
            onMoreActions: () {
              final item = chat.activeChat;
              if (item != null) {
                _showChatActions(context, chat, item, settings);
              }
            },
          );

          if (wide) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: settings.isDarkMode
                    ? const Color(0xFF101921)
                    : const Color(0xFFD7EAF6),
              ),
              child: Row(
                children: [
                  SizedBox(width: 400, child: inboxPanel),
                  const VerticalDivider(width: 1),
                  Expanded(child: conversation),
                ],
              ),
            );
          }

          if (_hasConversation(chat)) {
            return conversation;
          }

          return inboxPanel;
        },
      ),
    );
  }
}

