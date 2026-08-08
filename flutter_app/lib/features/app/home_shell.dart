import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import 'home_shell_scope.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_page.dart';
import '../settings/settings_controller.dart';
import '../social/friends_page.dart';
import '../social/profile_page.dart';
import '../social/settings_page.dart';

/// Pastdagi navigatsiya paneli va uning bo'limlari.
///
/// Ilgari ChatPage ning o'zi bosh ekran edi, qolgan bo'limlar esa yon
/// menyudan alohida sahifa sifatida ochilardi — ochilishi bilan navigatsiya
/// ko'rinmay qolar va qaytib, menyuni qayta ochish kerak bo'lardi. Panel esa
/// har bir bo'limda joyida turadi.
///
/// Bo'limlar IndexedStack da saqlanadi: bo'lim almashganda ular qayta
/// qurilmaydi, ya'ni suhbatlar ro'yxati, qidiruv matni va varaqlash holati
/// joyida qoladi.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _selectTab(int value) {
    // Suhbat ochiq bo'lsa yopamiz: aks holda boshqa bo'limdan qaytganda
    // ro'yxat emas, o'sha suhbat ko'rinardi.
    if (value != HomeTab.chats && _index == HomeTab.chats) {
      context.read<ChatController>().closeChat();
    }
    setState(() => _index = value);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final chat = context.watch<ChatController>();
    String t(String key) => AppStrings.text(settings.localeCode, key);

    // Suhbat ochiq bo'lganda panel yashiriladi — Telegramda ham shunday:
    // panel faqat yuqori darajadagi bo'limlarda turadi, suhbat esa uni
    // butunlay qoplaydi. Aks holda pastda yozish maydoni va panel yonma-yon
    // turib, ikkalasi ham joy egallardi.
    final inConversation =
        _index == HomeTab.chats && chat.activeChat != null;

    return PopScope(
      // ChatPage ham PopScope ishlatadi va u shu marshrutda qoladi. Ikkalasi
      // ham chaqiriladi, shuning uchun har biri faqat o'z holatida ish
      // qiladi: bu yerda — boshqa bo'limdan suhbatlarga qaytish, u yerda —
      // suhbatni yopish va chiqish.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _index == 0) return;
        setState(() => _index = 0);
      },
      child: Scaffold(
        body: HomeShellScope(
          selectTab: _selectTab,
          child: IndexedStack(
          index: _index,
          children: [
            ChatPage(active: _index == 0),
            const FriendsPage(titleKey: 'contacts'),
            const SettingsPage(),
            const ProfilePage(),
            ],
          ),
        ),
        bottomNavigationBar: inConversation
            ? null
            : NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _selectTab,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: const Icon(Icons.chat_bubble_rounded),
              label: t('chats'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.contact_page_outlined),
              selectedIcon: const Icon(Icons.contact_page_rounded),
              label: t('contacts'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded),
              label: t('settings'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded),
              label: t('profile_my'),
            ),
          ],
              ),
      ),
    );
  }
}
