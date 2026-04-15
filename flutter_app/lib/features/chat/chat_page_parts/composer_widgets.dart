part of '../chat_page.dart';

class _ComposerActionButton extends StatelessWidget {
  const _ComposerActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.compact = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      onPressed: onPressed,
      iconSize: compact ? 20 : 24,
      splashRadius: compact ? 18 : 22,
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints.tightFor(
          width: compact ? 32 : 40, height: compact ? 32 : 40),
      color: color ?? theme.colorScheme.onSurfaceVariant,
      icon: Icon(icon),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      onPressed: onPressed,
      iconSize: 22,
      splashRadius: 20,
      visualDensity: VisualDensity.compact,
      color: theme.colorScheme.onSurfaceVariant,
      icon: Icon(icon),
    );
  }
}

class _ComposerContextBanner extends StatelessWidget {
  const _ComposerContextBanner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.settings,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final SettingsController settings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: settings.isDarkMode
            ? Colors.white.withAlpha(12)
            : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: settings.isDarkMode
              ? Colors.white.withAlpha(12)
              : const Color(0xFFD9DEE6),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF419FD9)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
