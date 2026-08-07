import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../../models/social_models.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_controller.dart';
import '../settings/settings_controller.dart';
import 'social_repository.dart';

/// Telefon kitobidagi, lekin Gujumda yo'q kontakt — taklif qilish uchun.
class _InviteCandidate {
  const _InviteCandidate({required this.name, required this.phone});
  final String name;
  final String phone;
}

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
  final _searchFocusNode = FocusNode();

  List<SimpleUser> _searchResults = const [];
  List<_PhoneContactMatch> _phoneMatches = const [];
  List<_InviteCandidate> _inviteCandidates = const [];
  /// Taklif ro'yxati bir necha ming kontakt bo'lishi mumkin. ListView
  /// bolalarini birdan quradi, shuning uchun hammasini chizish sahifani
  /// ochilmas qilib qo'yardi — bo'lib-bo'lib ko'rsatamiz.
  static const _invitePageSize = 50;
  int _inviteLimit = _invitePageSize;
  bool _searchOpen = false;
  Timer? _searchDebounce;
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
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Telegram singari yozilayotganda qidiradi — alohida tugma bosish shart
  /// emas. 350ms kutamiz: har harf uchun so'rov yubormaslik uchun.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _searchResults = const []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  /// SMS orqali taklif. Ilova do'koni havolasi hali yo'q, shuning uchun
  /// matnda faqat ilova nomi bor — havola paydo bo'lganda shu yerga qo'shiladi.
  Future<void> _invite(_InviteCandidate candidate) async {
    final t = (String key) => AppStrings.text(
        context.read<SettingsController>().localeCode, key);
    final body = Uri.encodeComponent(t('invite_message'));
    final uri = Uri.parse('sms:${candidate.phone}?body=$body');
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('sms');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('invite_failed'))),
      );
    }
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
      // Taklif SMS i uchun raqamning asl ko'rinishi kerak — normallashtirilgan
      // oxirgi 9 raqamga SMS yuborib bo'lmaydi.
      final phoneToOriginal = <String, String>{};
      final phones = <String>[];
      for (final contact in deviceContacts) {
        final displayName = contact.displayName.trim();
        for (final phone in contact.phones) {
          final normalized = _normalizePhone(phone.number);
          if (normalized.length < 7) continue;
          phones.add(phone.number);
          phoneToName.putIfAbsent(
            normalized,
            () => displayName.isNotEmpty ? displayName : phone.number,
          );
          phoneToOriginal.putIfAbsent(normalized, () => phone.number);
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

      // Gujumda bo'lmagan kontaktlar — taklif ro'yxati. Telegram ham
      // ularni yashirmaydi, "Invite Friends" ostida ko'rsatadi.
      final registered = <String>{
        for (final user in filteredUsers) _normalizePhone(user.matchedPhone ?? '')
      };
      final invites = <String, _InviteCandidate>{};
      for (final entry in phoneToName.entries) {
        if (entry.key.isEmpty || registered.contains(entry.key)) continue;
        invites.putIfAbsent(
          entry.key,
          () => _InviteCandidate(
            name: entry.value,
            phone: phoneToOriginal[entry.key] ?? entry.key,
          ),
        );
      }
      final inviteList = invites.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _phoneMatches = matches;
        _inviteCandidates = inviteList;
        _inviteLimit = _invitePageSize;
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
        // Qidiruv sarlavha joyida ochiladi: odatda faqat belgi turadi,
        // bosilganda esa butun sarlavha maydonini egallaydi. Alohida
        // qidiruv bloki ekranning tepasini keraksiz band qilardi.
        title: _searchOpen
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: t('search_hint'),
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : Text(t(widget.titleKey ?? 'search_users')),
        actions: [
          IconButton(
            icon: Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  _searchController.clear();
                  _searchResults = const [];
                } else {
                  _searchFocusNode.requestFocus();
                }
              });
            },
          ),
        ],
      ),
      // Qo'lda qidirib qo'shish: raqami telefon kitobida yo'q odamni
      // username orqali topish uchun. Telegram'da ham shunga o'xshash
      // tugma bor — joyi boshqacha, vazifasi bir xil.
      floatingActionButton: _showPhoneContactsSection
          ? FloatingActionButton(
              onPressed: () => setState(() {
                _searchOpen = true;
                _searchFocusNode.requestFocus();
              }),
              tooltip: t('add_friend'),
              child: const Icon(Icons.person_add_alt_1_rounded),
            )
          : null,
      body: _SearchTab(
        controller: _searchController,
        searching: _searching,
        results: _searchResults,
        settings: settings,
        phoneMatches: _phoneMatches,
        inviteCandidates: _inviteCandidates,
        inviteLimit: _inviteLimit,
        onShowMoreInvites: () => setState(
          () => _inviteLimit += _invitePageSize,
        ),
        loadingContacts: _loadingContacts,
        contactsErrorKey: _contactsErrorKey,
        showPhoneContactsSection: _showPhoneContactsSection,
        onSearch: _runSearch,
        onSearchChanged: _onSearchChanged,
        searchFocusNode: _searchFocusNode,
        onRefreshContacts: _loadPhoneContactMatches,
        onOpenChat: _openChat,
        onInvite: _invite,
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
    required this.onSearchChanged,
    required this.onRefreshContacts,
    required this.onOpenChat,
    required this.onInvite,
    required this.inviteCandidates,
    required this.inviteLimit,
    required this.onShowMoreInvites,
    required this.searchFocusNode,
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
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function() onRefreshContacts;
  final ValueChanged<SimpleUser> onOpenChat;
  final ValueChanged<_InviteCandidate> onInvite;
  final List<_InviteCandidate> inviteCandidates;
  final int inviteLimit;
  final VoidCallback onShowMoreInvites;
  final FocusNode searchFocusNode;

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
                  if (results.isNotEmpty)
                    ...results.map((user) {
                      final imageUrl =
                          AppConfig.resolveMediaUrl(user.avatar, settings.baseUrl);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                          child: imageUrl.isEmpty
                              ? Text(user.fullName.isNotEmpty
                                  ? user.fullName.substring(0, 1).toUpperCase()
                                  : '?')
                              : null,
                        ),
                        title: Text(user.fullName),
                        subtitle: Text('@${user.username}'),
                        onTap: () => onOpenChat(user),
                      );
                    }),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                  // Gujumda bo'lmagan kontaktlar — taklif ro'yxati.
                  if (inviteCandidates.isNotEmpty) ...[
                    const Divider(height: 24),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        t('invite_friends'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    ...inviteCandidates.take(inviteLimit).map(
                      (candidate) => ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            candidate.name.isNotEmpty
                                ? candidate.name.substring(0, 1).toUpperCase()
                                : '#',
                          ),
                        ),
                        title: Text(candidate.name),
                        subtitle: Text(candidate.phone),
                        trailing: TextButton(
                          onPressed: () => onInvite(candidate),
                          child: Text(t('invite')),
                        ),
                      ),
                    ),
                    if (inviteCandidates.length > inviteLimit)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: OutlinedButton(
                          onPressed: onShowMoreInvites,
                          child: Text(
                            '${t('show_more')} '
                            '(${inviteCandidates.length - inviteLimit})',
                          ),
                        ),
                      ),
                  ],
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
    this.onChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final String Function(String key) t;
  final Future<void> Function() onSearch;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    // Alohida "Qidirish" tugmasi yo'q: yozilayotganda izlaydi.
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: t('search_hint'),
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
              ),
      ),
      onChanged: onChanged,
      onSubmitted: (_) => onSearch(),
    );
  }
}
