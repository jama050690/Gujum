import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/widgets/app_search_field.dart';
import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../../models/social_models.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_controller.dart';
import '../settings/settings_controller.dart';
import 'calls_page.dart';
import 'social_repository.dart';
import '../../core/widgets/avatar_image.dart';

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

      if (!mounted) return;
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

  void _closeSearch() {
    setState(() {
      _searchOpen = false;
      _searchController.clear();
      _searchResults = const [];
    });
  }

  /// Telegram/WhatsApp dagi "Yangi kontakt": ism va raqam kiritiladi, kontakt
  /// telefon kitobiga yoziladi va darhol Gujum bo'yicha tekshiriladi. Raqam
  /// ro'yxatdan o'tgan bo'lsa chat ochiladi, aks holda SMS taklif taklif
  /// qilinadi. Ilgari bu tugma faqat qidiruv maydonini ochardi.
  Future<void> _openNewContactSheet() async {
    final t = (String key) => AppStrings.text(
        context.read<SettingsController>().localeCode, key);
    final firstName = TextEditingController();
    final lastName = TextEditingController();
    final phone = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('new_contact'),
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: firstName,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: t('contact_first_name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lastName,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: t('contact_last_name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: t('contact_phone'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: Text(t('cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: Text(t('contact_save')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final number = phone.text.trim();
    final name = [firstName.text.trim(), lastName.text.trim()]
        .where((part) => part.isNotEmpty)
        .join(' ');
    firstName.dispose();
    lastName.dispose();
    phone.dispose();

    if (saved != true || !mounted) return;
    if (_normalizePhone(number).length < 7) {
      _showMessage(t('contact_invalid_phone'));
      return;
    }
    await _saveNewContact(name: name, phone: number, t: t);
  }

  Future<void> _saveNewContact({
    required String name,
    required String phone,
    required String Function(String key) t,
  }) async {
    // Kontaktni qurilma kitobiga yozamiz — WhatsApp/Telegram ham shunday
    // qiladi, shunda raqam boshqa ilovalarda ham ism bilan ko'rinadi.
    var writtenToDevice = false;
    try {
      if (await FlutterContacts.requestPermission(readonly: false)) {
        final parts = name.split(' ');
        final contact = Contact()
          ..name.first = parts.isNotEmpty && parts.first.isNotEmpty
              ? parts.first
              : phone
          ..name.last = parts.length > 1 ? parts.sublist(1).join(' ') : ''
          ..phones = [Phone(phone)];
        await FlutterContacts.insertContact(contact);
        writtenToDevice = true;
      }
    } catch (error) {
      debugPrint('Kontakt saqlanmadi: $error');
    }
    if (!mounted) return;
    if (!writtenToDevice) {
      _showMessage(t('contact_write_denied'));
    }

    // Raqam Gujumda bormi?
    try {
      final repository = context.read<SocialRepository>();
      final currentUser = context.read<AuthController>().user;
      final matched = (await repository.fetchPhoneContacts([phone]))
          .where((item) => item.username != currentUser?.username)
          .toList();
      if (!mounted) return;
      if (matched.isNotEmpty) {
        _showMessage(t('contact_found'));
        unawaited(_loadPhoneContactMatches());
        await _openChat(matched.first);
        return;
      }
    } catch (error) {
      _showError(error);
      return;
    }

    if (!mounted) return;
    // Ro'yxatdan o'tmagan — taklif taklif qilamiz.
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(t('contact_not_registered')),
        action: SnackBarAction(
          label: t('invite'),
          onPressed: () => unawaited(
            _invite(_InviteCandidate(
              name: name.isNotEmpty ? name : phone,
              phone: phone,
            )),
          ),
        ),
      ),
    );
    unawaited(_loadPhoneContactMatches());
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
            ? AppSearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: t('search_hint'),
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _runSearch(),
                onClose: _closeSearch,
              )
            : Text(t(widget.titleKey ?? 'search_users')),
        actions: [
          if (!_searchOpen)
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => setState(() {
                _searchOpen = true;
                _searchFocusNode.requestFocus();
              }),
            ),
        ],
      ),
      // Qo'lda qidirib qo'shish: raqami telefon kitobida yo'q odamni
      // username orqali topish uchun. Telegram'da ham shunga o'xshash
      // tugma bor — joyi boshqacha, vazifasi bir xil.
      floatingActionButton: _showPhoneContactsSection
          ? FloatingActionButton(
              onPressed: _openNewContactSheet,
              tooltip: t('new_contact'),
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
        loadingContacts: _loadingContacts,
        contactsErrorKey: _contactsErrorKey,
        showPhoneContactsSection: _showPhoneContactsSection,
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
    required this.onRefreshContacts,
    required this.onOpenChat,
    required this.onInvite,
    required this.inviteCandidates,
  });

  final TextEditingController controller;
  final bool searching;
  final List<SimpleUser> results;
  final SettingsController settings;
  final List<_PhoneContactMatch> phoneMatches;
  final bool loadingContacts;
  final String? contactsErrorKey;
  final bool showPhoneContactsSection;
  final Future<void> Function() onRefreshContacts;
  final ValueChanged<SimpleUser> onOpenChat;
  final ValueChanged<_InviteCandidate> onInvite;
  final List<_InviteCandidate> inviteCandidates;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    return Column(
      children: [
        if (showPhoneContactsSection)
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefreshContacts,
              child: Builder(builder: (context) {
                // Ro'yxat dangasa bo'lishi shart: ListView(children: [...])
                // barcha qatorlarni birdan quradi va bir necha ming
                // kontaktda sahifa ochilmay qolardi. ListView.builder
                // faqat ekranga tushganini quradi — 'ko'proq ko'rsatish'
                // tugmasi ham keraksiz bo'ladi, Telegram'da ham yo'q.
                final items = <Widget>[
                  // Telegramdagidek qisqa yorliqlar: taklif ro'yxati va
                  // qo'ng'iroqlar tarixi asosiy ro'yxatni to'ldirmasin.
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2492E8),
                      child: Icon(Icons.person_add_alt_1_rounded,
                          color: Colors.white),
                    ),
                    title: Text(t('invite_friends')),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _InviteFriendsPage(
                          candidates: inviteCandidates,
                          onInvite: onInvite,
                          settings: settings,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2A9D5C),
                      child: Icon(Icons.call_rounded, color: Colors.white),
                    ),
                    title: Text(t('recent_calls')),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CallsPage()),
                    ),
                  ),
                  const Divider(height: 24),
                  // Qidiruv natijalari shu yerda — maydonning o'zi sarlavha
                  // panelida (bitta global qidiruv komponenti).
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (results.isEmpty && controller.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Text(t('friend_search_hint')),
                    )
                  else
                    ...results.map((user) {
                      final imageUrl =
                          AppConfig.resolveMediaUrl(user.avatar, settings.baseUrl);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              imageUrl.isNotEmpty ? avatarImage(imageUrl) : null,
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
                  // Yangilash tugmasi olib tashlandi: ro'yxat sahifa
                  // ochilganda o'zi yuklanadi, qo'lda yangilash esa
                  // yuqoridan pastga tortish bilan (RefreshIndicator).
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      t('contacts_on_gujum'),
                      style: Theme.of(context).textTheme.titleMedium,
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
                          backgroundImage: imageUrl.isNotEmpty ? avatarImage(imageUrl) : null,
                          child: imageUrl.isEmpty ? Text(fallbackLetter) : null,
                        ),
                        title: Text(match.contactName),
                        subtitle: Text('@${user.username}'),
                        // Alohida "Chatni ochish" tugmasi yo'q — Telegramdagidek
                        // qatorning istalgan joyi bosilsa chat ochiladi.
                        onTap: () => onOpenChat(user),
                      );
                    }),
                  const SizedBox(height: 24),
                ];
                return ListView.builder(
                  // Ro'yxat kalta bo'lsa ham yuqoridan tortib yangilash
                  // ishlashi uchun har doim skroll qilinadigan fizika.
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, index) => items[index],
                );
              }),
            ),
          )
        else ...[
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
                            backgroundImage: imageUrl.isNotEmpty ? avatarImage(imageUrl) : null,
                            child: imageUrl.isEmpty ? Text(user.fullName.substring(0, 1).toUpperCase()) : null,
                          ),
                          title: Text(user.fullName),
                          subtitle: Text('@${user.username}'),
                          onTap: () => onOpenChat(user),
                        );
                      },
                    ),
        ),
        ],
      ],
    );
  }
}

/// Gujumda bo'lmagan telefon kontaktlari — SMS orqali taklif qilish uchun.
///
/// Telegramda ham bu ro'yxat asosiy kontaktlar ostida emas, alohida
/// "Do'stlarni taklif qilish" ekranida turadi.
class _InviteFriendsPage extends StatelessWidget {
  const _InviteFriendsPage({
    required this.candidates,
    required this.onInvite,
    required this.settings,
  });

  final List<_InviteCandidate> candidates;
  final ValueChanged<_InviteCandidate> onInvite;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    return Scaffold(
      appBar: AppBar(title: Text(t('invite_friends'))),
      body: candidates.isEmpty
          ? Center(child: Text(t('contacts_empty_gujum')))
          : ListView.separated(
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final candidate = candidates[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      candidate.name.isNotEmpty
                          ? candidate.name.substring(0, 1).toUpperCase()
                          : '#',
                    ),
                  ),
                  title: Text(candidate.name),
                  subtitle: Text(candidate.phone),
                  onTap: () => onInvite(candidate),
                  trailing: TextButton(
                    onPressed: () => onInvite(candidate),
                    child: Text(t('invite')),
                  ),
                );
              },
            ),
    );
  }
}
