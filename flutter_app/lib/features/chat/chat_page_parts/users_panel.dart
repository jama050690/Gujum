part of '../chat_page.dart';

/// Ro'yxatdagi suhbatlar shu belgi turgan joyga qo'yiladi.
///
/// Sarlavha, banner va qidiruv bo'limlari oldindan quriladi (ular kam va
/// arzon), suhbat qatorlari esa faqat ekranga tushganda.
const Widget _rowsMarker = SizedBox.shrink(key: ValueKey('inbox-rows'));

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
    required this.onSearchChanged,
    required this.onShowArchived,
    required this.onHideArchived,
    required this.onOpenSavedMessages,
    required this.onOpenChat,
    required this.onOpenSearchResult,
    required this.onShowChatActions,
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
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onShowArchived;
  final VoidCallback onHideArchived;
  final VoidCallback onOpenSavedMessages;
  final Future<void> Function(InboxItem item) onOpenChat;
  final Future<void> Function(SearchUser user) onOpenSearchResult;
  final ValueChanged<InboxItem> onShowChatActions;

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(settings.localeCode, key);
    final query = searchController.text.trim().toLowerCase();
    final connectionText =
        chat.connectionLabel == null ? null : t(chat.connectionLabel!);
    final panelBackground =
        settings.isDarkMode ? const Color(0xFF17212B) : Colors.white;
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
                child: NotificationListener<ScrollNotification>(
                  // Ro'yxat oxiriga yaqinlashganda keyingi bo'lak
                  // so'raladi — tugab qolishini kutmaymiz.
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 600 && chat.hasMoreChats) {
                      unawaited(chat.loadMoreChats());
                    }
                    return false;
                  },
                  child: Builder(builder: (context) {
                    // Dangasa ro'yxat: ListView(children: [...]) barcha
                    // suhbatlarni birdan quradi.
                    final items = <Widget>[
                    _UsersHeader(
                      settings: settings,
                      currentUser: currentUser,
                      title: showArchived ? t('archive_title') : null,
                      searchController: searchController,
                      showArchived: showArchived,
                      onBack: onHideArchived,
                      onChanged: onSearchChanged,
                    ),
                    // Arxivga kirish yo'li. onShowArchived hech qayerdan
                    // chaqirilmasdi: arxivlangan suhbat ro'yxatdan
                    // yo'qolar va uni qaytarib ko'rishning iloji yo'q edi.
                    // Faqat arxivda biror narsa bo'lsa ko'rsatiladi —
                    // Telegramda ham shunday.
                    if (!showArchived && query.isEmpty && archivedChats.isNotEmpty)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.archive_outlined,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(t('archive_title')),
                        trailing: Text(
                          '${archivedChats.length}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        onTap: onShowArchived,
                      ),
                    // "Saqlangan xabarlar" ilgari faqat yon menyuda edi.
                    // Menyu olib tashlangach, u Telegramdagi kabi
                    // ro'yxatning tepasida turadi.
                    if (!showArchived && query.isEmpty)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          child: const Icon(Icons.bookmark_rounded,
                              color: Colors.white),
                        ),
                        title: Text(t('chat_saved_messages')),
                        onTap: onOpenSavedMessages,
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
                        // Qatorlar bu yerda emas, quyida indeks bo'yicha
                        // quriladi — izohi ListView.builder yonida.
                        _rowsMarker,
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
                        // Qatorlar bu yerda emas, quyida indeks bo'yicha
                        // quriladi — izohi ListView.builder yonida.
                        _rowsMarker,
                      // Ko'rsatish chegarasi so'rov chegarasi bilan bir xil
                      // bo'lishi kerak: aks holda so'rov yuborilib,
                      // natijasi ko'rsatilmay qolardi.
                      if (query.length >= AppConfig.minGlobalSearchChars) ...[
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
                  ];
                    // Qatorlar dangasa quriladi. Ilgari `items` ichiga
                    // barcha suhbatlar birdan solinardi va ListView.builder
                    // ga tayyor ro'yxat berilardi — ya'ni builder hech
                    // narsa yutmasdi: har bir qator (tarmoqdan rasm
                    // oladigan avatar bilan) har qayta chizishda qurilardi.
                    // Endi belgi turgan joyga suhbatlar indeks bo'yicha
                    // qo'yiladi.
                    final markerAt = items.indexOf(_rowsMarker);
                    final rows =
                        markerAt == -1 ? const <InboxItem>[] : filteredItems;
                    final extra = rows.isEmpty ? 0 : rows.length - 1;
                    return ListView.builder(
                      itemCount: items.length + extra,
                      itemBuilder: (context, index) {
                        if (markerAt == -1 || index < markerAt) {
                          return items[index];
                        }
                        final rowIndex = index - markerAt;
                        if (rowIndex < rows.length) {
                          final item = rows[rowIndex];
                          return _InboxTile(
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
                          );
                        }
                        return items[index - extra];
                      },
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
