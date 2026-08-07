part of '../chat_page.dart';

extension _ChatPageStateBuild on _ChatPageState {
  Widget _buildChatPageScaffold(
    BuildContext context,
    SettingsController settings,
    AuthController auth,
    ChatController chat,
  ) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Conversation ochiq bo'lsa — yopamiz, chiqmaymiz
        if (_hasConversation(chat)) {
          _closeConversation(chat);
          return;
        }
        // Chat ro'yxatida — ikki marta bosish kerak
        final now = DateTime.now();
        final last = _lastBackPress;
        if (last != null && now.difference(last) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _lastBackPress = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.text(
                context.read<SettingsController>().localeCode,
                'exit_press_again')),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
      key: _scaffoldKey,
      drawerScrimColor: Colors.black.withAlpha(120),
      drawer: _AppDrawer(
        settings: settings,
        user: auth.user,
        onOpenProfile: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          );
        },
        onOpenNewGroup: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  const CommunityPage(initialTab: 0, openComposer: true),
            ),
          );
        },
        onOpenNewChannel: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  const CommunityPage(initialTab: 1, openComposer: true),
            ),
          );
        },
        onOpenContacts: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const FriendsPage(titleKey: 'contacts'),
            ),
          );
        },
        onOpenCalls: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CallsPage()),
          );
        },
        onOpenSavedMessages: () => _openSavedMessages(chat),
        onOpenSettings: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          );
        },
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          final inboxPanel = _UsersPanel(
            settings: settings,
            chat: chat,
            currentUser: auth.user,
            searchController: _searchController,
            showArchived: _showArchived,
            archivedChats: _archivedChats,
            pinnedChats: _pinnedChats,
            mutedChats: _mutedChats,
            showSavedMessages: _showSavedMessages,
            globalResults: _globalResults,
            loadingGlobalSearch: _loadingGlobalSearch,
            onOpenSidebar: () => _scaffoldKey.currentState?.openDrawer(),
            onSearchChanged: (value) => _handleSearchChanged(chat, value),
            onShowArchived: () => setState(() => _showArchived = true),
            onHideArchived: () => setState(() => _showArchived = false),
            onOpenSavedMessages: () => _openSavedMessages(chat),
            onOpenChat: (item) => _openInboxChat(chat, item),
            onOpenSearchResult: (user) => _openChatFromSearch(chat, user),
            onShowChatActions: (item) =>
                _showChatActions(context, chat, item, settings),
            onOpenNewChat: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FriendsPage(titleKey: 'search_users'),
                ),
              );
            },
            onOpenCamera: () => _openQuickCamera(settings),
            onOpenContacts: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FriendsPage(titleKey: 'contacts'),
                ),
              );
            },
            onOpenSettings: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
            onOpenProfile: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          );

          final conversation = _ConversationPane(
            settings: settings,
            chat: chat,
            showBack: !wide,
            showSavedMessages: _showSavedMessages,
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
    ),
    );
  }
}

