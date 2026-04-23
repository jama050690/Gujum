part of '../chat_page.dart';

class _SearchResultsSection extends StatelessWidget {
  const _SearchResultsSection({
    required this.settings,
    required this.title,
    required this.subtitle,
    required this.results,
    required this.onlineUsers,
    required this.lastActiveFor,
    required this.onTap,
  });

  final SettingsController settings;
  final String title;
  final String subtitle;
  final List<SearchUser> results;
  final Set<String> onlineUsers;
  final DateTime? Function(String username) lastActiveFor;
  final Future<void> Function(SearchUser user) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          color: const Color(0xFF1D2A39),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF8FA3B6),
                ),
          ),
        ),
        ...results.map(
          (user) => InkWell(
            onTap: () => onTap(user),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  _Avatar(
                    label: user.fullName,
                    imageUrl: AppConfig.resolveMediaUrl(
                        user.avatar, settings.baseUrl),
                    radius: 23,
                    online: onlineUsers.contains(user.username),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          onlineUsers.contains(user.username)
                              ? AppStrings.text(settings.localeCode, 'online')
                              : _formatLastSeenStatus(
                                  lastActiveFor(user.username),
                                  settings.localeCode,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: onlineUsers.contains(user.username)
                                        ? const Color(0xFF41D481)
                                        : const Color(0xFF8FA3B6),
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArchiveEmptyState extends StatelessWidget {
  const _ArchiveEmptyState({
    required this.settings,
    required this.title,
  });

  final SettingsController settings;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppStrings.text(settings.localeCode, key);

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 56, 32, 32),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF223140),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.archive_rounded,
              color: const Color(0xFF8FA3B6),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            t('archive_empty'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF8FA3B6),
                ),
          ),
        ],
      ),
    );
  }
}
