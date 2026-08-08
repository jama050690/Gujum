part of '../chat_page.dart';

class _UsersBottomNav extends StatelessWidget {
  const _UsersBottomNav({
    required this.settings,
    required this.activeColor,
    required this.onOpenContacts,
    required this.onOpenSettings,
    required this.onOpenProfile,
  });

  final SettingsController settings;
  final Color activeColor;
  final VoidCallback onOpenContacts;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(settings.localeCode, key);
    final surfaceColor = settings.isDarkMode
        ? const Color(0xFF1D2A39)
        : Colors.white;
    final shadowColor = settings.isDarkMode
        ? const Color(0x4D000000)
        : const Color(0x140B2239);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: _UsersBottomNavItem(
                label: t('inbox'),
                icon: Icons.chat_bubble_rounded,
                selected: true,
                activeColor: activeColor,
                onTap: () {},
              ),
            ),
            Expanded(
              child: _UsersBottomNavItem(
                label: t('contacts'),
                icon: Icons.people_alt_rounded,
                activeColor: activeColor,
                onTap: onOpenContacts,
              ),
            ),
            Expanded(
              child: _UsersBottomNavItem(
                label: t('settings'),
                icon: Icons.settings_rounded,
                activeColor: activeColor,
                onTap: onOpenSettings,
              ),
            ),
            Expanded(
              child: _UsersBottomNavItem(
                label: t('profile'),
                icon: Icons.person_rounded,
                activeColor: activeColor,
                onTap: onOpenProfile,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsersBottomNavItem extends StatelessWidget {
  const _UsersBottomNavItem({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Colors.white
        : Theme.of(context).textTheme.bodyMedium?.color?.withAlpha(180) ??
            const Color(0xFFA7B7C7);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

