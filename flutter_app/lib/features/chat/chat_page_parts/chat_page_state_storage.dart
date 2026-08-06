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

  setState(() {
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

Future<void> _openQuickCamera(SettingsController settings) async {
  final t = (String key) => AppStrings.text(settings.localeCode, key);
  try {
    await _quickCameraPicker.pickImage(source: ImageSource.camera);
  } on PlatformException {
    if (!mounted) {
      return;
    }
    _showInfoSnackBar(t('call_permission_denied'));
  } catch (_) {
    if (!mounted) {
      return;
    }
    _showInfoSnackBar(t('chat_action_failed'));
  }
}

void _handleSearchChanged(ChatController chat, String value) {
  _searchDebounce?.cancel();

  final query = value.trim();
  if (query.length < 2) {
    setState(() {
      _loadingGlobalSearch = false;
      _globalResults = const [];
    });
    return;
  }

  setState(() => _loadingGlobalSearch = true);
  _searchDebounce = Timer(const Duration(milliseconds: 320), () async {
    try {
      final results = await chat.searchUsers(query);
      if (!mounted || _searchController.text.trim() != query) {
        return;
      }
      setState(() {
        _loadingGlobalSearch = false;
        _globalResults = results;
      });
    } catch (_) {
      if (!mounted || _searchController.text.trim() != query) {
        return;
      }
      setState(() {
        _loadingGlobalSearch = false;
        _globalResults = const [];
      });
    }
  });
}

Future<void> _openInboxChat(ChatController chat, InboxItem item) async {
  if (_showSavedMessages) {
    setState(() => _showSavedMessages = false);
  }
  await chat.openChat(item);
}

Future<void> _openChatFromSearch(ChatController chat, SearchUser user) async {
  if (_showSavedMessages) {
    setState(() => _showSavedMessages = false);
  }
  await chat.startChatWith(user);
}

void _openSavedMessages(ChatController chat) {
  chat.closeChat();
  setState(() => _showSavedMessages = true);
}

void _closeConversation(ChatController chat) {
  if (_showSavedMessages) {
    setState(() => _showSavedMessages = false);
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

  setState(() => _archivedChats = next);
  await _persistArchivedChats();
}

Future<void> _togglePin(InboxItem item) async {
  final next = <String>{..._pinnedChats};
  if (next.contains(item.username)) {
    next.remove(item.username);
  } else {
    next.add(item.username);
  }
  setState(() => _pinnedChats = next);
  await _persistPinnedChats();
}

Future<void> _toggleMute(InboxItem item) async {
  final next = <String>{..._mutedChats};
  if (next.contains(item.username)) {
    next.remove(item.username);
  } else {
    next.add(item.username);
  }
  setState(() => _mutedChats = next);
  await _persistMutedChats();
}

Future<void> _removeChatPreferences(String username) async {
  setState(() {
    _archivedChats.remove(username);
    _pinnedChats.remove(username);
    _mutedChats.remove(username);
  });
  await _persistArchivedChats();
  await _persistPinnedChats();
  await _persistMutedChats();
}
}
