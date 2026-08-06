import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../../models/social_models.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_controller.dart';
import '../settings/settings_controller.dart';
import 'social_repository.dart';

class _PhoneContactMatch {
  const _PhoneContactMatch({
    required this.user,
    required this.contactName,
  });

  final SimpleUser user;
  final String contactName;
}

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
  List<_PhoneContactMatch> _phoneMatches = const [];
  bool _searching = false;
  bool _loadingContacts = false;
  String? _contactsErrorKey;

  bool get _showPhoneContactsSection => widget.titleKey == 'contacts';

  @override
  void initState() {
    super.initState();
    if (_showPhoneContactsSection) {
      _loadPhoneContactMatches();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizePhone(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 9) {
      return digits;
    }
    return digits.substring(digits.length - 9);
  }

  Future<void> _loadPhoneContactMatches() async {
    setState(() {
      _loadingContacts = true;
      _contactsErrorKey = null;
    });

    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (!mounted) return;
        setState(() {
          _contactsErrorKey = 'contacts_permission_denied';
          _phoneMatches = const [];
        });
        return;
      }

      final deviceContacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      final phoneToName = <String, String>{};
      final phones = <String>[];
      for (final contact in deviceContacts) {
        final displayName = contact.displayName.trim();
        for (final phone in contact.phones) {
          final normalized = _normalizePhone(phone.number);
          if (normalized.length < 7) continue;
          phones.add(phone.number);
          phoneToName.putIfAbsent(
            normalized,
            () => displayName.isNotEmpty ? displayName : normalized,
          );
        }
      }

      if (phones.isEmpty) {
        if (!mounted) return;
        setState(() {
          _phoneMatches = const [];
        });
        return;
      }

      final repository = context.read<SocialRepository>();
      final currentUser = context.read<AuthController>().user;
      final matchedUsers = await repository.fetchPhoneContacts(phones);
      final filteredUsers = matchedUsers
          .where((item) => item.username != currentUser?.username)
          .toList(growable: false);

      final matches = filteredUsers.map((user) {
        final phoneKey = _normalizePhone(user.matchedPhone ?? '');
        final contactName = phoneToName[phoneKey] ?? user.fullName;
        return _PhoneContactMatch(user: user, contactName: contactName);
      }).toList(growable: false);

      if (!mounted) return;
      setState(() {
        _phoneMatches = matches;
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _loadingContacts = false;
        });
      }
    }
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
        phoneMatches: _phoneMatches,
        loadingContacts: _loadingContacts,
        contactsErrorKey: _contactsErrorKey,
        showPhoneContactsSection: _showPhoneContactsSection,
        onSearch: _runSearch,
        onRefreshContacts: _loadPhoneContactMatches,
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
    required this.phoneMatches,
    required this.loadingContacts,
    required this.contactsErrorKey,
    required this.showPhoneContactsSection,
    required this.onSearch,
    required this.onRefreshContacts,
    required this.onOpenChat,
  });

  final TextEditingController controller;
  final bool searching;
  final List<SimpleUser> results;
  final SettingsController settings;
  final List<_PhoneContactMatch> phoneMatches;
  final bool loadingContacts;
  final String? contactsErrorKey;
  final bool showPhoneContactsSection;
  final Future<void> Function() onSearch;
  final Future<void> Function() onRefreshContacts;
  final ValueChanged<SimpleUser> onOpenChat;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    return Column(
      children: [
        if (showPhoneContactsSection)
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefreshContacts,
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            t('contacts_on_gujum'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          onPressed: onRefreshContacts,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  if (loadingContacts)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(t('contacts_syncing')),
                        ],
                      ),
                    )
                  else if (contactsErrorKey != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        t(contactsErrorKey!),
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    )
                  else if (phoneMatches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(t('contacts_empty_gujum')),
                    )
                  else
                    ...phoneMatches.map((match) {
                      final user = match.user;
                      final imageUrl = AppConfig.resolveMediaUrl(user.avatar, settings.baseUrl);
                      final fallbackLetter = (match.contactName.isNotEmpty
                              ? match.contactName
                              : user.fullName)
                          .substring(0, 1)
                          .toUpperCase();
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                          child: imageUrl.isEmpty ? Text(fallbackLetter) : null,
                        ),
                        title: Text(match.contactName),
                        subtitle: Text('@${user.username}'),
                        trailing: FilledButton.tonal(
                          onPressed: () => onOpenChat(user),
                          child: Text(t('open_chat')),
                        ),
                      );
                    }),
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      t('search_users'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _SearchBox(
                      controller: controller,
                      t: t,
                      onSearch: onSearch,
                    ),
                  ),
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(t('friend_search_hint')),
                    )
                  else
                    ...results.map((user) {
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
                    }),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          )
        else ...[
        Padding(
          padding: const EdgeInsets.all(16),
          child: _SearchBox(
            controller: controller,
            t: t,
            onSearch: onSearch,
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
      ],
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.t,
    required this.onSearch,
  });

  final TextEditingController controller;
  final String Function(String key) t;
  final Future<void> Function() onSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}
