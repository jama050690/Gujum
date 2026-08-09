part of '../chat_page.dart';

extension _ChatPageStateStorage on _ChatPageState {
String _archiveStorageKey(String username) =>
    'gujum.archived_chats.$username';

String _pinnedStorageKey(String username) => 'gujum.pinned_chats.$username';

String _mutedStorageKey(String username) => 'gujum.muted_chats.$username';

Future<void> _restoreChatPreferences() async {
  final username = context.read<AuthController>().user?.username;
  if (username == null || _archiveOwner == username) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final archived =
      prefs.getStringList(_archiveStorageKey(username)) ?? const <String>[];
  final pinned =
      prefs.getStringList(_pinnedStorageKey(username)) ?? const <String>[];
  final muted =
      prefs.getStringList(_mutedStorageKey(username)) ?? const <String>[];
  if (!mounted) {
    return;
  }

  applyState(() {
    _archiveOwner = username;
    _archivedChats = archived.toSet();
    _pinnedChats = pinned.toSet();
    _mutedChats = muted.toSet();
  });
}

Future<void> _persistStoredSet(String storageKey, Set<String> values) async {
  final owner = _archiveOwner;
  if (owner == null) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final sorted = values.toList()..sort();
  await prefs.setStringList(storageKey, sorted);
}

Future<void> _persistArchivedChats() async {
  final owner = _archiveOwner;
  if (owner == null) {
    return;
  }
  await _persistStoredSet(_archiveStorageKey(owner), _archivedChats);
}

Future<void> _persistPinnedChats() async {
  final owner = _archiveOwner;
  if (owner == null) {
    return;
  }
  await _persistStoredSet(_pinnedStorageKey(owner), _pinnedChats);
}

Future<void> _persistMutedChats() async {
  final owner = _archiveOwner;
  if (owner == null) {
    return;
  }
  await _persistStoredSet(_mutedStorageKey(owner), _mutedChats);
}

void _showInfoSnackBar(String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void _handleSearchChanged(ChatController chat, String value) {
  _searchDebounce?.cancel();

  final query = value.trim();
  if (query.length < AppConfig.minGlobalSearchChars) {
    applyState(() {
      _loadingGlobalSearch = false;
      _globalResults = const [];
    });
    return;
  }

  applyState(() => _loadingGlobalSearch = true);
  _searchDebounce = Timer(AppConfig.searchDebounce, () async {
    try {
      final results = await chat.searchUsers(query);
      if (!mounted || _searchController.text.trim() != query) {
        return;
      }
      applyState(() {
        _loadingGlobalSearch = false;
        _globalResults = results;
      });
    } catch (_) {
      if (!mounted || _searchController.text.trim() != query) {
        return;
      }
      applyState(() {
        _loadingGlobalSearch = false;
        _globalResults = const [];
      });
    }
  });
}

Future<void> _openInboxChat(ChatController chat, InboxItem item) async {
  if (chat.showSavedMessages) {
    chat.closeSavedMessages();
  }
  await chat.openChat(item);
}

Future<void> _openChatFromSearch(ChatController chat, SearchUser user) async {
  if (chat.showSavedMessages) {
    chat.closeSavedMessages();
  }
  await chat.startChatWith(user);
}

void _openSavedMessages(ChatController chat) {
  final t = AppStrings.text(
      context.read<SettingsController>().localeCode, 'chat_saved_messages');
  unawaited(chat.openSavedMessages(title: t));
}

void _closeConversation(ChatController chat) {
  if (chat.showSavedMessages) {
    chat.closeSavedMessages();
    return;
  }
  chat.closeChat();
}

Future<void> _toggleArchive(ChatController chat, InboxItem item) async {
  final next = <String>{..._archivedChats};
  if (next.contains(item.username)) {
    next.remove(item.username);
  } else {
    next.add(item.username);
    if (chat.activeChat?.username == item.username) {
      chat.closeChat();
    }
  }

  applyState(() => _archivedChats = next);
  await _persistArchivedChats();
}

Future<void> _togglePin(InboxItem item) async {
  final next = <String>{..._pinnedChats};
  if (next.contains(item.username)) {
    next.remove(item.username);
  } else {
    next.add(item.username);
  }
  applyState(() => _pinnedChats = next);
  await _persistPinnedChats();
}

Future<void> _toggleMute(InboxItem item) async {
  final next = <String>{..._mutedChats};
  if (next.contains(item.username)) {
    next.remove(item.username);
  } else {
    next.add(item.username);
  }
  applyState(() => _mutedChats = next);
  await _persistMutedChats();
}

Future<void> _removeChatPreferences(String username) async {
  if (!mounted) return;
  applyState(() {
    _archivedChats.remove(username);
    _pinnedChats.remove(username);
    _mutedChats.remove(username);
  });
  await _persistArchivedChats();
  await _persistPinnedChats();
  await _persistMutedChats();
}
}
