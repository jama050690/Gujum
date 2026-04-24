import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../../models/social_models.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_controller.dart';
import '../settings/settings_controller.dart';
import 'social_repository.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({
    super.key,
    this.titleKey,
  });

  final String? titleKey;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _searchController = TextEditingController();

  List<SimpleUser> _searchResults = const [];
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
      });
      return;
    }

    final repository = context.read<SocialRepository>();
    final currentUser = context.read<AuthController>().user;
    setState(() => _searching = true);
    try {
      final found = await repository.searchUsers(query);
      final filtered = found.where((item) => item.username != currentUser?.username).toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _searchResults = filtered;
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
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

    return Scaffold(
      appBar: AppBar(
        title: Text(t(widget.titleKey ?? 'search_users')),
      ),
      body: _SearchTab(
        controller: _searchController,
        searching: _searching,
        results: _searchResults,
        settings: settings,
        onSearch: _runSearch,
        onOpenChat: _openChat,
      ),
    );
  }
}

class _SearchTab extends StatelessWidget {
  const _SearchTab({
    required this.controller,
    required this.searching,
    required this.results,
    required this.settings,
    required this.onSearch,
    required this.onOpenChat,
  });

  final TextEditingController controller;
  final bool searching;
  final List<SimpleUser> results;
  final SettingsController settings;
  final Future<void> Function() onSearch;
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
                        final imageUrl = AppConfig.resolveMediaUrl(user.avatar, settings.baseUrl);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                            child: imageUrl.isEmpty ? Text(user.fullName.substring(0, 1).toUpperCase()) : null,
                          ),
                          title: Text(user.fullName),
                          subtitle: Text('@${user.username}'),
                          trailing: FilledButton.tonal(
                            onPressed: () => onOpenChat(user),
                            child: Text(t('open_chat')),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
