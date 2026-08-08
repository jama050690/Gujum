part of '../chat_page.dart';

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.settings,
    required this.user,
    required this.onOpenProfile,
    required this.onOpenContacts,
    required this.onOpenCalls,
    required this.onOpenSavedMessages,
    required this.onOpenSettings,
  });

  final SettingsController settings;
  final SessionUser? user;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenContacts;
  final VoidCallback onOpenCalls;
  final VoidCallback onOpenSavedMessages;
  final VoidCallback onOpenSettings;

  void _handleTap(BuildContext context, VoidCallback action) {
    // Yon menyuni Navigator.pop() bilan yopib bo'lmaydi: ChatPage butun
    // sahifani PopScope(canPop: false) ga o'rab qo'ygan, u esa menyuning
    // ichki "orqaga" yozuvidan (LocalHistoryEntry) ustun turadi. Natijada
    // pop to'xtatilar va uning o'rniga ChatPage ning ishlovchisi ishlab
    // ketardi: ochiq suhbat yopilib ketardi yoki "chiqish uchun yana bir
    // marta bosing" chiqardi — menyu esa ochiqligicha qolardi.
    //
    // closeDrawer() to'g'ridan-to'g'ri Scaffold ga aytadi va marshrutlar
    // tizimiga umuman tegmaydi.
    Scaffold.maybeOf(context)?.closeDrawer();
    action();
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(settings.localeCode, key);
    final appTitle = t('app_title');
    final headerColor =
        settings.isDarkMode ? const Color(0xFF242F3D) : const Color(0xFF517DA2);
    final surfaceColor =
        settings.isDarkMode ? const Color(0xFF1C252E) : const Color(0xFFF3F5FB);
    final modeLabel = settings.isDarkMode ? t('dark_mode') : t('day_mode');

    return Drawer(
      child: ColoredBox(
        color: surfaceColor,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Container(
                      padding: EdgeInsets.fromLTRB(
                          18, MediaQuery.paddingOf(context).top + 18, 18, 18),
                      color: headerColor,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Avatar(
                                  label: user?.displayName ?? appTitle,
                                  imageUrl: user == null
                                      ? ''
                                      : AppConfig.resolveMediaUrl(
                                          user!.avatar, settings.baseUrl),
                                  radius: 34,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  user?.displayName ?? appTitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  t('online'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: Colors.white70,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded,
                              color: Colors.white70, size: 28),
                        ],
                      ),
                    ),
                    _DrawerMenuTile(
                      icon: Icons.person_outline_rounded,
                      label: t('profile_my'),
                      onTap: () => _handleTap(context, onOpenProfile),
                    ),
                    _DrawerMenuTile(
                      icon: Icons.contact_page_outlined,
                      label: t('contacts'),
                      onTap: () => _handleTap(context, onOpenContacts),
                    ),
                    _DrawerMenuTile(
                      icon: Icons.call_outlined,
                      label: t('calls'),
                      onTap: () => _handleTap(context, onOpenCalls),
                    ),
                    _DrawerMenuTile(
                      icon: Icons.bookmark_border_rounded,
                      label: t('chat_saved_messages'),
                      onTap: () => _handleTap(context, onOpenSavedMessages),
                    ),
                    _DrawerMenuTile(
                      icon: Icons.settings_outlined,
                      label: t('settings'),
                      onTap: () => _handleTap(context, onOpenSettings),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: settings.isDarkMode,
                      onChanged: settings.setDarkMode,
                      secondary: Icon(
                        settings.isDarkMode
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        color: settings.isDarkMode
                            ? Colors.white70
                            : Colors.black54,
                      ),
                      title: Text(modeLabel),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout_rounded,
                          color: Colors.redAccent),
                      title: Text(
                        t('logout'),
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      onTap: () async {
                        final shouldLogout = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) {
                            return AlertDialog(
                              title: Text(t('logout_confirm_title')),
                              content: Text(t('logout_confirm_message')),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(false),
                                  child: Text(t('cancel')),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(true),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                  ),
                                  child: Text(t('logout')),
                                ),
                              ],
                            );
                          },
                        );
                        if (shouldLogout != true || !context.mounted) {
                          return;
                        }
                        // Yuqoridagi _handleTap dagi kabi: bu yerdagi maqsad
                        // yon menyuni yopish, Navigator.pop() esa ChatPage
                        // ning PopScope iga tushib qoladi.
                        Scaffold.maybeOf(context)?.closeDrawer();
                        await context.read<AuthController>().logout();
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  '${t('version_label')} ${AppConfig.appVersion}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: settings.isDarkMode
                            ? Colors.white38
                            : Colors.black38,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerMenuTile extends StatelessWidget {
  const _DrawerMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading:
          Icon(icon, color: Theme.of(context).iconTheme.color?.withAlpha(170)),
      title: Text(label),
      onTap: onTap,
    );
  }
}
