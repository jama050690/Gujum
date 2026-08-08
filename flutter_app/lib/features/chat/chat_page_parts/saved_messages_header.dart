part of '../chat_page.dart';

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.settings,
    required this.title,
    required this.subtitle,
    required this.label,
    required this.imageUrl,
    required this.showBack,
    required this.onBack,
    this.isSaved = false,
    this.trailing,
    this.compact = false,
    this.onAvatarTap,
    this.onTitleTap,
    this.searchField,
  });

  final SettingsController settings;
  final String title;
  final String subtitle;
  final String label;
  final String imageUrl;
  final bool showBack;
  final VoidCallback onBack;
  final bool isSaved;
  final Widget? trailing;
  final bool compact;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onTitleTap;

  /// Qidiruv ochilganda sarlavha (ism/holat) va o'ng tugmalar o'rniga shu
  /// maydon ko'rsatiladi — Telegramdagidek, panelning o'zida.
  final Widget? searchField;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: settings.isDarkMode ? const Color(0xFF1A232D) : Colors.white,
      elevation: 1,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8,
            vertical: compact ? 2 : 6,
          ),
          child: Row(
            children: [
              if (showBack)
                IconButton(
                  onPressed: onBack,
                  iconSize: compact ? 22 : 24,
                  splashRadius: compact ? 18 : 22,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              if (!showBack) SizedBox(width: compact ? 4 : 8),
              if (searchField == null && isSaved)
                Container(
                  width: compact ? 34 : 42,
                  height: compact ? 34 : 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6C9FD2),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.bookmark_rounded, color: Colors.white),
                )
              else if (searchField == null)
                GestureDetector(
                  onTap: onAvatarTap,
                  child: _Avatar(
                    label: label,
                    imageUrl: imageUrl,
                    radius: compact ? 17 : 21,
                  ),
                ),
              SizedBox(width: compact ? 8 : 12),
              if (searchField != null)
                Expanded(child: searchField!)
              else
              Expanded(
                child: GestureDetector(
                  onTap: onTitleTap,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (compact
                                ? Theme.of(context).textTheme.titleSmall
                                : Theme.of(context).textTheme.titleMedium)
                            ?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: settings.isDarkMode
                                    ? Colors.white70
                                    : Colors.black54,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (searchField == null && trailing != null) ...[
                const SizedBox(width: 4),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
