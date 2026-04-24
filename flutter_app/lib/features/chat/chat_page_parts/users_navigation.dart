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
    final t = (String key) => AppStrings.text(settings.localeCode, key);
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

class _ArchivedChatsTile extends StatelessWidget {
  const _ArchivedChatsTile({
    required this.settings,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final SettingsController settings;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFF2EB6A4), width: 2),
                    ),
                  ),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFF2F9ED8), width: 3),
                    ),
                  ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFBFBFBF),
                    ),
                    child: const Icon(
                      Icons.archive_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF8FA3B6),
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: const Color(0xFF8FA3B6),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedMessagesTile extends StatelessWidget {
  const _SavedMessagesTile({
    required this.settings,
    required this.selected,
    required this.title,
    required this.onTap,
  });

  final SettingsController settings;
  final bool selected;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF253444);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? activeColor : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                color: Color(0xFF6C9FD2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bookmark_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
