import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const _contactsChannel = MethodChannel('gujum/contacts');

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

  // Oxirgi muvaffaqiyatli sinxronizatsiya natijasi. Sahifa har ochilganda
  // qurilma kitobini o'qish + serverga so'rov bir necha soniya ketardi va
  // shu vaqt davomida ekran bo'sh spinner bo'lib turardi. Endi eski ro'yxat
  // darhol ko'rsatiladi, yangilanish esa fonda ketadi.
  //
  // Kesh kimga tegishli ekani ham saqlanadi: aks holda bir qurilmada A chiqib
  // B kirganda B ning ekranida A ning kontaktlari va ular orasidagi telefon
  // raqamlari ko'rinib qolardi. Egasini tekshirish chiqishdagi tozalashdan
  // ishonchliroq — logout ni chetlab o'tadigan yo'llar ham bor (sessiya
  // eskirishi, akkauntni o'chirish).
  static String? _cacheOwner;
  static List<_PhoneContactMatch>? _cachedMatches;
  static List<_InviteCandidate>? _cachedInvites;

  /// Kesh diskda ham saqlanadi. Xotiradagi nusxa faqat ilova ishlab turgan
  /// vaqtda yashaydi, ya'ni har ishga tushirishdan keyin birinchi ochilishda
  /// yana butun manzillar kitobi o'qilardi — bu qurilmada ~1500 kontakt
  /// uchun bir necha soniya, va shu vaqt davomida ekranda aylanma turardi.
  /// Serverga so'rov bunga aloqador emas: u 5 ms da qaytadi.
  static const _cacheKey = 'contacts_cache_v1';

  String? _currentUsername() =>
      context.read<AuthController>().user?.username;

  @override
  void initState() {
    super.initState();
    if (_showPhoneContactsSection) {
      if (_cacheOwner != null && _cacheOwner == _currentUsername()) {
        _phoneMatches = _cachedMatches ?? const [];
        _inviteCandidates = _cachedInvites ?? const [];
      } else {
        _cacheOwner = null;
        _cachedMatches = null;
        _cachedInvites = null;
      }
      unawaited(_bootstrapContacts());
    }
  }

  /// Avval diskdagi keshni ko'rsatamiz, keyin yangilaymiz. Tartib muhim:
  /// sinxronizatsiya oldin boshlansa, kesh yetib kelguncha ekranda aylanma
  /// paydo bo'lib ulguradi.
  Future<void> _bootstrapContacts() async {
    await _restoreCachedContacts();
    await _loadPhoneContactMatches();
  }

  Future<void> _restoreCachedContacts() async {
    if (_cachedMatches != null) return; // xotiradagi nusxa yangiroq
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      final owner = _currentUsername();
      // Boshqa akkauntning ro'yxati ko'rinmasligi kerak — o'chirib yuboramiz.
      if (owner == null || data['owner'] != owner) {
        await prefs.remove(_cacheKey);
        return;
      }
      final matches = (data['matches'] as List<dynamic>? ?? const [])
          .map((item) => _matchFromJson(item as Map<String, dynamic>))
          .toList(growable: false);
      final invites = (data['invites'] as List<dynamic>? ?? const [])
          .map((item) => _inviteFromJson(item as Map<String, dynamic>))
          .toList(growable: false);
      _cacheOwner = owner;
      _cachedMatches = matches;
      _cachedInvites = invites;
      // Sinxronizatsiya allaqachon tugagan bo'lsa uni bosib o'tmaymiz.
      if (!mounted || _phoneMatches.isNotEmpty) return;
      setState(() {
        _phoneMatches = matches;
        _inviteCandidates = invites;
      });
    } catch (error) {
      debugPrint('Kontakt keshi o\'qilmadi: $error');
    }
  }

  Future<void> _persistCache() async {
    final owner = _cacheOwner;
    if (owner == null) return;
    final matches = _cachedMatches ?? const <_PhoneContactMatch>[];
    final invites = _cachedInvites ?? const <_InviteCandidate>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'owner': owner,
          'matches': matches.map(_matchToJson).toList(),
          'invites': invites.map(_inviteToJson).toList(),
        }),
      );
    } catch (error) {
      debugPrint('Kontakt keshi saqlanmadi: $error');
    }
  }

  static Map<String, dynamic> _matchToJson(_PhoneContactMatch match) => {
        'username': match.user.username,
        'full_name': match.user.fullName,
        'avatar': match.user.avatar,
        'matched_phone': match.user.matchedPhone,
        'contact_name': match.contactName,
      };

  static _PhoneContactMatch _matchFromJson(Map<String, dynamic> json) {
    final user = SimpleUser.fromJson(json);
    final name = (json['contact_name'] ?? '').toString();
    return _PhoneContactMatch(
      user: user,
      // Bo'sh nom qatorda bosh harf olishda xatoga olib keladi.
      contactName: name.isNotEmpty
          ? name
          : (user.fullName.isNotEmpty ? user.fullName : user.username),
    );
  }

  static Map<String, dynamic> _inviteToJson(_InviteCandidate candidate) => {
        'name': candidate.name,
        'phone': candidate.phone,
      };

  static _InviteCandidate _inviteFromJson(Map<String, dynamic> json) =>
      _InviteCandidate(
        name: (json['name'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
      );

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

  /// Manzillar kitobini o'qish qimmat native amal: minglab kontaktda u yuzlab
  /// megabaytgacha xotira oladi. Ikki sinxronizatsiya bir vaqtda ketsa,
  /// Android jarayonni jimgina o'ldiradi — ilova hech qanday xato ko'rsatmay
  /// yo'qoladi. Shu sababli bir vaqtda faqat bittasi ishlaydi; ustma-ust
  /// so'ralgani esa navbatda bitta qayta yurishga aylanadi.
  bool _syncInFlight = false;
  bool _syncQueued = false;

  Future<void> _loadPhoneContactMatches() async {
    if (_syncInFlight) {
      _syncQueued = true;
      return;
    }
    _syncInFlight = true;
    try {
      await _syncPhoneContacts();
    } finally {
      _syncInFlight = false;
      if (_syncQueued && mounted) {
        _syncQueued = false;
        await _loadPhoneContactMatches();
      } else {
        _syncQueued = false;
      }
    }
  }

  Future<void> _syncPhoneContacts() async {
    if (!mounted) return;
    setState(() {
      // Keshdan ro'yxat bor bo'lsa spinner ko'rsatmaymiz — ro'yxat joyida
      // qoladi va jimgina yangilanadi.
      _loadingContacts = _phoneMatches.isEmpty;
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
      for (final contact in deviceContacts) {
        final displayName = contact.displayName.trim();
        for (final phone in contact.phones) {
          final normalized = _normalizePhone(phone.number);
          if (normalized.length < 7) continue;
          phoneToName.putIfAbsent(
            normalized,
            () => displayName.isNotEmpty ? displayName : phone.number,
          );
          phoneToOriginal.putIfAbsent(normalized, () => phone.number);
        }
      }

      // Faqat takrorlanmas normallashgan raqamlar yuboriladi. Ilgari har bir
      // yozuvning asl ko'rinishi yuborilardi — bitta odam uch xil formatda
      // saqlangan bo'lsa uch marta, va katta kitobda so'rov tanasi bir necha
      // yuz kilobaytga chiqib sekin uzatilardi.
      final phones = phoneToOriginal.keys.toList(growable: false);
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

      _cacheOwner = currentUser?.username;
      _cachedMatches = matches;
      _cachedInvites = inviteList;
      unawaited(_persistCache());
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
    // Avval raqam Gujumda bormi — bu tez va hech qanday ruxsat talab
    // qilmaydi. Qurilma kitobiga yozish esa oxirida, tizim oynasi orqali:
    // undan qaytilganda ilova allaqachon kerakli holatda turadi.
    try {
      final repository = context.read<SocialRepository>();
      final currentUser = context.read<AuthController>().user;
      final matched = (await repository.fetchPhoneContacts([phone]))
          .where((item) => item.username != currentUser?.username)
          .toList();
      if (!mounted) return;
      if (matched.isNotEmpty) {
        _showMessage(t('contact_found'));
        // Bitta kontakt qo'shilgani uchun butun manzillar kitobini qayta
        // o'qish shart emas — yangi qatorni ro'yxatga qo'shib qo'yamiz.
        _addMatchLocally(_PhoneContactMatch(
          user: matched.first,
          contactName: name.isNotEmpty ? name : matched.first.fullName,
        ));
        await _openDeviceContactInsert(name: name, phone: phone, t: t);
        if (!mounted) return;
        await _openChat(matched.first);
        return;
      }
    } catch (error) {
      _showError(error);
      return;
    }

    if (!mounted) return;
    // Ro'yxatdan o'tmagan — taklif qilamiz.
    final candidate = _InviteCandidate(
      name: name.isNotEmpty ? name : phone,
      phone: phone,
    );
    _addInviteLocally(candidate);
    await _openDeviceContactInsert(name: name, phone: phone, t: t);

    if (!mounted) return;
    // Bu yerda SnackBar ishlamaydi: uning ustiga darhol tizimning kontakt
    // oynasi ochiladi va foydalanuvchi qaytguncha SnackBar o'z vaqtini
    // to'ldirib yo'qoladi — "Taklif qilish" tugmasi hech qachon bosilmasdi.
    // Dialog esa qaytganda joyida turadi.
    final wantsInvite = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(t('contact_not_registered')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t('invite')),
          ),
        ],
      ),
    );
    if (wantsInvite == true) {
      await _invite(candidate);
    }
  }

  /// Raqamni qurilma kitobiga yozish uchun tizimning "yangi kontakt" oynasini
  /// ochadi. Ilgari bu yerda FlutterContacts.insertContact chaqirilardi: u
  /// qurilmaning asosiy hisobi bulutli bo'lganda fon oqimida ushlab
  /// bo'lmaydigan xato berardi va ilova butunlay yopilib ketardi.
  Future<void> _openDeviceContactInsert({
    required String name,
    required String phone,
    required String Function(String key) t,
  }) async {
    var opened = false;
    try {
      opened = await _contactsChannel.invokeMethod<bool>(
            'openInsert',
            {'name': name, 'phone': phone},
          ) ??
          false;
    } catch (error) {
      debugPrint('Kontakt oynasi ochilmadi: $error');
    }
    if (!opened) {
      _showMessage(t('contact_write_denied'));
    }
  }

  /// Yangi saqlangan kontaktni ro'yxatga qo'shadi. Kitobni qayta o'qimaydi —
  /// bitta qator uchun minglab kontaktni o'qish ilovani sekinlashtiradi.
  ///
  /// Qo'shish paytida sinxronizatsiya ketayotgan bo'lsa, u eski ro'yxat bilan
  /// tugaydi va yangi qator jimgina yo'qoladi. Shuning uchun bunday holatda
  /// tugagach yana bir marta yangilanadi — endi qurilma kitobida yangi kontakt
  /// ham bor.
  void _addMatchLocally(_PhoneContactMatch match) {
    // _currentUsername() context ga tegadi — vidjet yo'q bo'lsa umuman
    // kirishmaymiz.
    if (!mounted) return;
    if (_phoneMatches.any((item) => item.user.username == match.user.username)) {
      return;
    }
    final updated = [..._phoneMatches, match];
    _cacheOwner = _currentUsername();
    _cachedMatches = updated;
    unawaited(_persistCache());
    if (_syncInFlight) _syncQueued = true;
    setState(() => _phoneMatches = updated);
  }

  void _addInviteLocally(_InviteCandidate candidate) {
    if (!mounted) return;
    final key = _normalizePhone(candidate.phone);
    if (_inviteCandidates.any((item) => _normalizePhone(item.phone) == key)) {
      return;
    }
    final updated = [..._inviteCandidates, candidate]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _cacheOwner = _currentUsername();
    _cachedInvites = updated;
    unawaited(_persistCache());
    if (_syncInFlight) _syncQueued = true;
    setState(() => _inviteCandidates = updated);
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
                // Faqat sarlavha qismi oldindan quriladi — kontaktlar
                // qatorlari indeks bo'yicha, ekranga tushganda quriladi.
                // Ilgari butun ro'yxat shu yerda ro'yxatga yig'ilardi, ya'ni
                // ListView.builder dangasaligi bekor bo'lib, har build da
                // minglab ListTile qurilardi.
                final header = <Widget>[
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
                  // "Gujumdagi kontaktlarim" sarlavhasi ham olib tashlandi —
                  // ro'yxat nimaligi shundoq ham ko'rinib turibdi.
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
                    ),
                ];
                return ListView.builder(
                  // Ro'yxat kalta bo'lsa ham yuqoridan tortib yangilash
                  // ishlashi uchun har doim skroll qilinadigan fizika.
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: header.length + phoneMatches.length + 1,
                  itemBuilder: (context, index) {
                    if (index < header.length) return header[index];
                    if (index == header.length + phoneMatches.length) {
                      return const SizedBox(height: 24);
                    }
                    final match = phoneMatches[index - header.length];
                    final user = match.user;
                    final imageUrl =
                        AppConfig.resolveMediaUrl(user.avatar, settings.baseUrl);
                    final fallbackLetter = (match.contactName.isNotEmpty
                            ? match.contactName
                            : user.fullName)
                        .substring(0, 1)
                        .toUpperCase();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            imageUrl.isNotEmpty ? avatarImage(imageUrl) : null,
                        child: imageUrl.isEmpty ? Text(fallbackLetter) : null,
                      ),
                      title: Text(match.contactName),
                      subtitle: Text('@${user.username}'),
                      // Alohida "Chatni ochish" tugmasi yo'q — Telegramdagidek
                      // qatorning istalgan joyi bosilsa chat ochiladi.
                      onTap: () => onOpenChat(user),
                    );
                  },
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
