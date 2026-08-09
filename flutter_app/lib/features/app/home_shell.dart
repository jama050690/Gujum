import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import 'navigation_controller.dart';
import '../call/call_controller.dart';
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
  NavigationController? _nav;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<NavigationController>();
    if (identical(_nav, next)) return;
    _nav?.removeListener(_onTabChanged);
    _nav = next..addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _nav?.removeListener(_onTabChanged);
    super.dispose();
  }

  /// Suhbatlar bo'limidan chiqilganda ochiq suhbat yopiladi — aks holda
  /// qaytib kelganda ro'yxat emas, o'sha suhbat ko'rinardi.
  void _onTabChanged() {
    if (_nav?.index == HomeTab.chats) return;
    final chat = context.read<ChatController>();
    if (chat.activeChat != null) chat.closeChat();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final chat = context.watch<ChatController>();
    final call = context.watch<CallController>();
    final nav = context.watch<NavigationController>();
    String t(String key) => AppStrings.text(settings.localeCode, key);

    // Suhbat ochiq bo'lganda panel yashiriladi — Telegramda ham shunday:
    // panel faqat yuqori darajadagi bo'limlarda turadi, suhbat esa uni
    // butunlay qoplaydi.
    final inConversation =
        nav.index == HomeTab.chats && chat.activeChat != null;

    Widget tab(int index, Widget Function() build) =>
        nav.isVisited(index) ? build() : const SizedBox.shrink();

    return Scaffold(

        body: IndexedStack(
          index: nav.index,
          children: [
            const ChatPage(),
            tab(HomeTab.contacts, () => const FriendsPage(titleKey: 'contacts')),
            tab(HomeTab.settings, () => const SettingsPage()),
            tab(HomeTab.profile, () => const ProfilePage()),
          ],
        ),
        bottomNavigationBar: inConversation
            ? null
            : _FloatingNavBar(
                index: nav.index,
                onSelect: nav.selectTab,
                unreadChats: chat.inbox
                    .fold<int>(0, (sum, item) => sum + item.unreadCount),
                labels: [
                  t('chats'),
                  t('contacts'),
                  t('settings'),
                  t('profile_my'),
                ],
              ),
    );
  }
}

/// Suzuvchi navigatsiya paneli.
///
/// Material ning odatdagi NavigationBar i ekran kengligi bo'ylab yopishib
/// turadi va kontentni yuqoriga suradi. Bu yerdagisi esa chetlardan
/// ajralgan, yumaloq va kontent ustida suzadi.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.index,
    required this.onSelect,
    required this.unreadChats,
    required this.labels,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final int unreadChats;
  final List<String> labels;

  static const _icons = <IconData>[
    Icons.forum_outlined,
    Icons.person_outline_rounded,
    Icons.settings_outlined,
    Icons.account_circle_outlined,
  ];
  static const _selectedIcons = <IconData>[
    Icons.forum_rounded,
    Icons.person_rounded,
    Icons.settings_rounded,
    Icons.account_circle_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 8,
          shadowColor: Colors.black.withAlpha(60),
          borderRadius: BorderRadius.circular(32),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: _NavItem(
                      icon: i == index ? _selectedIcons[i] : _icons[i],
                      label: labels[i],
                      selected: i == index,
                      // Faqat suhbatlar bo'limida — o'qilmaganlar soni.
                      badge: i == HomeTab.chats ? unreadChats : 0,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withAlpha(28)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              badge > 0
                  ? Badge.count(count: badge, child: Icon(icon, color: color))
                  : Icon(icon, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
