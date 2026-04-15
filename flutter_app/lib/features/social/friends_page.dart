import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/socket_service.dart';
import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../../models/social_models.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_controller.dart';
import '../settings/settings_controller.dart';
import 'social_repository.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _searchController = TextEditingController();

  List<SimpleUser> _friends = const [];
  List<FriendRequestItem> _requests = const [];
  List<SimpleUser> _searchResults = const [];
  Map<String, FriendStatus> _statuses = const <String, FriendStatus>{};
  bool _loading = true;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final repository = context.read<SocialRepository>();
      final results = await Future.wait([
        repository.fetchFriends(),
        repository.fetchFriendRequests(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _friends = results[0] as List<SimpleUser>;
        _requests = results[1] as List<FriendRequestItem>;
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _statuses = const <String, FriendStatus>{};
      });
      return;
    }

    final repository = context.read<SocialRepository>();
    final currentUser = context.read<AuthController>().user;
    setState(() => _searching = true);
    try {
      final found = await repository.searchUsers(query);
      final filtered = found.where((item) => item.username != currentUser?.username).toList();
      final statusEntries = await Future.wait(
        filtered.map((item) async {
          final status = await repository.fetchFriendStatus(item.username);
          return MapEntry(item.username, status);
        }),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _searchResults = filtered;
        _statuses = Map.fromEntries(statusEntries);
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _sendRequest(SimpleUser user) async {
    try {
      final repository = context.read<SocialRepository>();
      final auth = context.read<AuthController>();
      final socket = context.read<SocketService>();
      await repository.sendFriendRequest(user.username);
      socket.emit('FRIEND_REQUEST', {
        'targetUsername': user.username,
        'senderUsername': auth.user?.username,
        'senderAvatar': auth.user?.avatar,
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _statuses = {
          ..._statuses,
          user.username: const FriendStatus(status: 'sent'),
        };
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _acceptRequest(FriendRequestItem request) async {
    try {
      final repository = context.read<SocialRepository>();
      final auth = context.read<AuthController>();
      final socket = context.read<SocketService>();
      await repository.acceptFriendRequest(request.id);
      socket.emit('FRIEND_ACCEPTED', {
        'targetUsername': request.username,
        'accepterUsername': auth.user?.username,
        'accepterAvatar': auth.user?.avatar,
      });
      await _loadInitial();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _rejectRequest(FriendRequestItem request) async {
    try {
      await context.read<SocialRepository>().rejectFriendRequest(request.id);
      await _loadInitial();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _openChat(SimpleUser user) async {
    await context.read<ChatController>().startChatWith(
          SearchUser(
            username: user.username,
            fullName: user.fullName,
            avatar: user.avatar,
          ),
        );
    if (!mounted) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final t = (String key) => AppStrings.text(settings.localeCode, key);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('friends')),
          bottom: TabBar(
            tabs: [
              Tab(text: t('friends')),
              Tab(text: t('requests')),
              Tab(text: t('search_users')),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _loadInitial,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _FriendsList(
                    friends: _friends,
                    settings: settings,
                    emptyText: t('no_friends'),
                    onOpenChat: _openChat,
                  ),
                  _RequestsList(
                    requests: _requests,
                    settings: settings,
                    onAccept: _acceptRequest,
                    onReject: _rejectRequest,
                  ),
                  _SearchTab(
                    controller: _searchController,
                    searching: _searching,
                    results: _searchResults,
                    statuses: _statuses,
                    settings: settings,
                    onSearch: _runSearch,
                    onSendRequest: _sendRequest,
                    onOpenChat: _openChat,
                  ),
                ],
              ),
      ),
    );
  }
}

class _FriendsList extends StatelessWidget {
  const _FriendsList({
    required this.friends,
    required this.settings,
    required this.emptyText,
    required this.onOpenChat,
  });

  final List<SimpleUser> friends;
  final SettingsController settings;
  final String emptyText;
  final ValueChanged<SimpleUser> onOpenChat;

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) {
      return Center(child: Text(emptyText));
    }

    return ListView.separated(
      itemCount: friends.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = friends[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: AppConfig.resolveMediaUrl(user.avatar, settings.baseUrl).isNotEmpty
                ? NetworkImage(AppConfig.resolveMediaUrl(user.avatar, settings.baseUrl))
                : null,
            child: AppConfig.resolveMediaUrl(user.avatar, settings.baseUrl).isEmpty
                ? Text(user.fullName.substring(0, 1).toUpperCase())
                : null,
          ),
          title: Text(user.fullName),
          subtitle: Text('@${user.username}'),
          trailing: FilledButton.tonal(
            onPressed: () => onOpenChat(user),
            child: Text(AppStrings.text(settings.localeCode, 'open_chat')),
          ),
        );
      },
    );
  }
}

class _RequestsList extends StatelessWidget {
  const _RequestsList({
    required this.requests,
    required this.settings,
    required this.onAccept,
    required this.onReject,
  });

  final List<FriendRequestItem> requests;
  final SettingsController settings;
  final ValueChanged<FriendRequestItem> onAccept;
  final ValueChanged<FriendRequestItem> onReject;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    if (requests.isEmpty) {
      return Center(child: Text(t('no_requests')));
    }

    return ListView.separated(
      itemCount: requests.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final request = requests[index];
        final imageUrl = AppConfig.resolveMediaUrl(request.avatar, settings.baseUrl);
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
            child: imageUrl.isEmpty ? Text(request.username.substring(0, 1).toUpperCase()) : null,
          ),
          title: Text(request.username),
          subtitle: Text(t('friend_wants_be_friend')),
          trailing: Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () => onAccept(request),
                child: Text(t('friend_accept')),
              ),
              OutlinedButton(
                onPressed: () => onReject(request),
                child: Text(t('friend_reject')),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchTab extends StatelessWidget {
  const _SearchTab({
    required this.controller,
    required this.searching,
    required this.results,
    required this.statuses,
    required this.settings,
    required this.onSearch,
    required this.onSendRequest,
    required this.onOpenChat,
  });

  final TextEditingController controller;
  final bool searching;
  final List<SimpleUser> results;
  final Map<String, FriendStatus> statuses;
  final SettingsController settings;
  final Future<void> Function() onSearch;
  final ValueChanged<SimpleUser> onSendRequest;
  final ValueChanged<SimpleUser> onOpenChat;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: t('search_hint'),
                    suffixIcon: IconButton(
                      onPressed: onSearch,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => onSearch(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onSearch,
                child: Text(t('chat_search_button')),
              ),
            ],
          ),
        ),
        Expanded(
          child: searching
              ? const Center(child: CircularProgressIndicator())
              : results.isEmpty
                  ? Center(child: Text(t('friend_search_hint')))
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final user = results[index];
                        final status = statuses[user.username] ?? const FriendStatus(status: 'none');
                        final imageUrl = AppConfig.resolveMediaUrl(user.avatar, settings.baseUrl);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                            child: imageUrl.isEmpty ? Text(user.fullName.substring(0, 1).toUpperCase()) : null,
                          ),
                          title: Text(user.fullName),
                          subtitle: Text('@${user.username}'),
                          trailing: _StatusButton(
                            status: status,
                            settings: settings,
                            onAdd: () => onSendRequest(user),
                            onOpenChat: () => onOpenChat(user),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.status,
    required this.settings,
    required this.onAdd,
    required this.onOpenChat,
  });

  final FriendStatus status;
  final SettingsController settings;
  final VoidCallback onAdd;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    if (status.isFriend) {
      return FilledButton.tonal(
        onPressed: onOpenChat,
        child: Text(t('open_chat')),
      );
    }
    if (status.isSent) {
      return Text(t('friend_status_sent'));
    }
    if (status.isReceived) {
      return Text(t('friend_status_received'));
    }
    return FilledButton(
      onPressed: onAdd,
      child: Text(t('friend_add_button')),
    );
  }
}
