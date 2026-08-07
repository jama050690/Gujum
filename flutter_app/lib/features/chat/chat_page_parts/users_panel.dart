part of '../chat_page.dart';

class _UsersPanel extends StatelessWidget {
  const _UsersPanel({
    required this.settings,
    required this.chat,
    required this.currentUser,
    required this.searchController,
    required this.showArchived,
    required this.archivedChats,
    required this.pinnedChats,
    required this.mutedChats,
    required this.showSavedMessages,
    required this.globalResults,
    required this.loadingGlobalSearch,
    required this.onOpenSidebar,
    required this.onSearchChanged,
    required this.onShowArchived,
    required this.onHideArchived,
    required this.onOpenSavedMessages,
    required this.onOpenChat,
    required this.onOpenSearchResult,
    required this.onShowChatActions,
    required this.onOpenNewChat,
    required this.onOpenCamera,
    required this.onOpenContacts,
    required this.onOpenSettings,
    required this.onOpenProfile,
  });

  final SettingsController settings;
  final ChatController chat;
  final SessionUser? currentUser;
  final TextEditingController searchController;
  final bool showArchived;
  final Set<String> archivedChats;
  final Set<String> pinnedChats;
  final Set<String> mutedChats;
  final bool showSavedMessages;
  final List<SearchUser> globalResults;
  final bool loadingGlobalSearch;
  final VoidCallback onOpenSidebar;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onShowArchived;
  final VoidCallback onHideArchived;
  final VoidCallback onOpenSavedMessages;
  final Future<void> Function(InboxItem item) onOpenChat;
  final Future<void> Function(SearchUser user) onOpenSearchResult;
  final ValueChanged<InboxItem> onShowChatActions;
  final VoidCallback onOpenNewChat;
  final VoidCallback onOpenCamera;
  final VoidCallback onOpenContacts;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(settings.localeCode, key);
    final query = searchController.text.trim().toLowerCase();
    final connectionText =
        chat.connectionLabel == null ? null : t(chat.connectionLabel!);
    final panelBackground =
        settings.isDarkMode ? const Color(0xFF17212B) : Colors.white;
    final activeColor =
        settings.isDarkMode ? const Color(0xFF253444) : const Color(0xFFE7F1FB);
    final iconColor =
        settings.isDarkMode ? Colors.white70 : const Color(0xFF506070);
    final bodyColor =
        settings.isDarkMode ? Colors.white : const Color(0xFF17212B);
    final dividerColor =
        settings.isDarkMode ? const Color(0xFF223140) : const Color(0xFFE3EAF2);
    final infoChipColor =
        settings.isDarkMode ? const Color(0xFF203244) : const Color(0xFFE7EFF8);
    final infoTextColor =
        settings.isDarkMode ? const Color(0xFF9EB1C2) : const Color(0xFF5E7388);
    final emptyTextColor =
        settings.isDarkMode ? const Color(0xFF8EA3B7) : const Color(0xFF667B90);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final panelTheme = Theme.of(context).copyWith(
      iconTheme: IconThemeData(color: iconColor),
      dividerColor: dividerColor,
      textTheme: Theme.of(context).textTheme.apply(
            bodyColor: bodyColor,
            displayColor: bodyColor,
          ),
    );

    final currentUsername = currentUser?.username;
    final items = chat.inbox
        .where((item) => item.username != currentUsername)
        .toList(growable: false)
      ..sort((a, b) {
        final aPinned = pinnedChats.contains(a.username);
        final bPinned = pinnedChats.contains(b.username);
        if (aPinned != bPinned) {
          return aPinned ? -1 : 1;
        }

        final at = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

    final visibleItems = items.where((item) {
      final archived = archivedChats.contains(item.username);
      return showArchived ? archived : !archived;
    }).toList(growable: false);

    final filteredItems = visibleItems.where((item) {
      if (query.isEmpty) {
        return true;
      }

      final source =
          '${item.fullName} ${item.username} ${item.lastMessage}'.toLowerCase();
      return source.contains(query);
    }).toList(growable: false);

    final seenUsernames = filteredItems.map((item) => item.username).toSet();
    final extraResults = globalResults
        .where((item) =>
            item.username != currentUsername &&
            !seenUsernames.contains(item.username))
        .toList(growable: false);

    return Theme(
      data: panelTheme,
      child: ColoredBox(
        color: panelBackground,
        child: Stack(
          children: [
            Positioned.fill(
              child: RefreshIndicator(
                onRefresh: chat.loadInbox,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(bottom: safeBottom + 118),
                  children: [
                    _UsersHeader(
                      settings: settings,
                      currentUser: currentUser,
                      title: showArchived ? t('archive_title') : null,
                      searchController: searchController,
                      showArchived: showArchived,
                      onOpenSidebar: onOpenSidebar,
                      onBack: onHideArchived,
                      onChanged: onSearchChanged,
                    ),
                    // connectionText ulanish yaxshi bo'lganda null bo'ladi,
                    // shuning uchun alohida 'connected' tekshiruvi kerak emas
                    // (u hech qachon bunday qiymat qaytarmasdi ham).
                    if (connectionText != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: infoChipColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Text(
                              connectionText,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: infoTextColor,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    if (showArchived) ...[
                      if (filteredItems.isEmpty)
                        _ArchiveEmptyState(
                          settings: settings,
                          title: t('archive_title'),
                        )
                      else
                        ...filteredItems.map(
                          (item) => _InboxTile(
                            currentUsername: currentUsername,
                            settings: settings,
                            item: item,
                            isOnline: chat.onlineUsers.contains(item.username),
                            lastActive: chat.lastActiveFor(item.username),
                            isPinned: pinnedChats.contains(item.username),
                            isMuted: mutedChats.contains(item.username),
                            isActive:
                                chat.activeChat?.username == item.username,
                            onTap: () => onOpenChat(item),
                            onLongPress: () => onShowChatActions(item),
                          ),
                        ),
                    ] else ...[
                      if (filteredItems.isEmpty &&
                          chat.inbox.isEmpty &&
                          query.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                          child: Center(
                            child: Text(
                              t('empty_inbox'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: emptyTextColor,
                                  ),
                            ),
                          ),
                        )
                      else
                        ...filteredItems.map(
                          (item) => _InboxTile(
                            currentUsername: currentUsername,
                            settings: settings,
                            item: item,
                            isOnline: chat.onlineUsers.contains(item.username),
                            lastActive: chat.lastActiveFor(item.username),
                            isPinned: pinnedChats.contains(item.username),
                            isMuted: mutedChats.contains(item.username),
                            isActive:
                                chat.activeChat?.username == item.username,
                            onTap: () => onOpenChat(item),
                            onLongPress: () => onShowChatActions(item),
                          ),
                        ),
                      if (query.length >= 2) ...[
                        if (loadingGlobalSearch)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        if (!loadingGlobalSearch && extraResults.isNotEmpty)
                          _SearchResultsSection(
                            settings: settings,
                            title: t('search_global_results'),
                            subtitle: t('search_tap_to_chat'),
                            results: extraResults,
                            onlineUsers: chat.onlineUsers,
                            lastActiveFor: chat.lastActiveFor,
                            onTap: onOpenSearchResult,
                          ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            if (!showArchived)
              Positioned(
                right: 20,
                bottom: safeBottom + 156,
                child: FloatingActionButton.small(
                  heroTag: 'camera_fab',
                  onPressed: onOpenCamera,
                  backgroundColor: settings.isDarkMode
                      ? Colors.white
                      : const Color(0xFFE4EDF6),
                  foregroundColor: const Color(0xFF1C2B3A),
                  elevation: 8,
                  child: const Icon(Icons.photo_camera_rounded, size: 20),
                ),
              ),
            if (!showArchived)
              Positioned(
                right: 20,
                bottom: safeBottom + 92,
                child: FloatingActionButton(
                  heroTag: 'new_chat_fab',
                  onPressed: onOpenNewChat,
                  backgroundColor: const Color(0xFF2EA6FF),
                  foregroundColor: Colors.white,
                  elevation: 10,
                  child: const Icon(Icons.add_rounded, size: 32),
                ),
              ),
            if (!showArchived)
              Positioned(
                left: 18,
                right: 18,
                bottom: safeBottom + 14,
                child: _UsersBottomNav(
                  settings: settings,
                  activeColor: activeColor,
                  onOpenContacts: onOpenContacts,
                  onOpenSettings: onOpenSettings,
                  onOpenProfile: onOpenProfile,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
