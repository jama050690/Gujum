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
        // Boshqa bo'lim ochiq — "orqaga" ni qobiq (HomeShell) hal qiladi.
        if (!widget.active) return;
        // Qo'ng'iroq oynasi bosishni o'zi ishlatadi (kichrayadi yoki javob
        // kutadi). Flutter bitta bosishda ro'yxatdagi BARCHA PopScope larni
        // chaqiradi, shuning uchun bu yerda to'xtamasak, qo'ng'iroq
        // kichrayishi bilan birga orqadagi suhbat ham yopilib ketardi.
        if (context.read<CallController?>()?.consumesBackPress == true) return;
        // Suhbat ichida avval qidiruv/tanlash yopiladi, keyingina suhbat.
        if (_hasConversation(chat)) {
          // Har bir "yutilgan" bosish taymerni ham tozalaydi: aks holda
          // bir marta ogohlantirish ko'rsatilgach, oradagi bosishlar
          // hisobga olinmay, ikki soniya ichidagi keyingi bosish ilovani
          // ogohlantirishsiz yopib yuborardi.
          _lastBackPress = null;
          if (conversationBackHandler?.call() == true) return;
          _closeConversation(chat);
          return;
        }
        // Qidiruv ochiq — avval uni tozalaymiz. Ekrandagi "x" allaqachon
        // shunday qilardi, tizim tugmasi esa yo'q.
        // Qidiruv ochiq bo'lsa — avval o'shani yopamiz. Maydon matnsiz
        // ham ochiq turishi mumkin, shuning uchun holatni panelning o'zi
        // aytadi; u matnni ham, maydonni ham yopadi.
        if (closeInboxSearch?.call() == true) {
          _lastBackPress = null;
          return;
        }
        // Arxiv ro'yxati ochiq — oddiy ro'yxatga qaytamiz. Ilgari bu
        // tekshirilmasdi va arxivda "orqaga" to'g'ridan-to'g'ri "chiqish
        // uchun yana bir marta bosing" ga olib borardi.
        if (_showArchived) {
          applyState(() => _showArchived = false);
          _lastBackPress = null;
          return;
        }
        // Boshqa bo'limdan kelingan bo'lsa — o'sha yerga qaytamiz.
        // Masalan Sozlamalar → "Saqlangan xabarlar": suhbat yopilgach
        // ro'yxatda qolib ketmasdan Sozlamalarga qaytadi.
        if (context.read<NavigationController>().popTab()) {
          _lastBackPress = null;
          return;
        }
        // Chat ro'yxatida — ikki marta bosish kerak
        final now = DateTime.now();
        final last = _lastBackPress;
        if (last != null && now.difference(last) < const Duration(seconds: 2)) {
          // Qo'ng'iroq ketayotgan bo'lsa ilovani o'ldirmaymiz. Ilgari shu
          // yerda SystemNavigator.pop() chaqirilardi va u aktivlikni
          // tugatardi: Flutter dvigateli bilan birga WebRTC ham o'lardi,
          // suhbatdoshga CALL_END yuborilmasdi, foreground service
          // bildirishnomasi esa ekranda qolib ketardi — uni bosgan odam
          // ilovani ochardi, lekin qo'ng'iroq allaqachon yo'q edi.
          final call = context.read<CallController?>();
          if (call != null && call.isCallActive) {
            unawaited(call.moveAppToBackground());
            return;
          }
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
            showSavedMessages: chat.showSavedMessages,
            globalResults: _globalResults,
            loadingGlobalSearch: _loadingGlobalSearch,
            onSearchChanged: (value) => _handleSearchChanged(chat, value),
            onShowArchived: () => applyState(() => _showArchived = true),
            onHideArchived: () => applyState(() => _showArchived = false),
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
    ),
    );
  }
}

