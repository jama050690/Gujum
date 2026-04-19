part of '../chat_page.dart';

class _InboxTile extends StatelessWidget {
  const _InboxTile({
    required this.settings,
    required this.item,
    required this.isPinned,
    required this.isMuted,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
  });

  final SettingsController settings;
  final InboxItem item;
  final bool isPinned;
  final bool isMuted;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    const activeColor = Color(0xFF253444);
    const previewColor = Color(0xFF8FA3B6);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: isActive ? activeColor : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 8, 14, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(
              label: item.fullName,
              imageUrl:
                  AppConfig.resolveMediaUrl(item.avatar, settings.baseUrl),
              radius: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(top: 6, bottom: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive
                          ? Colors.transparent
                          : const Color(0xFF223140),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                          ),
                        ),
                        if (isMuted) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.volume_off_rounded,
                            size: 15,
                            color: Color(0xFF62788D),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          _formatInboxTime(
                              item.lastMessageAt, settings.localeCode),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: item.unreadCount > 0
                                        ? const Color(0xFF79C1FF)
                                        : previewColor,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _previewText(item, t),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: previewColor,
                                ),
                          ),
                        ),
                        if (item.unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                            color: isActive
                                ? Colors.white24
                                : isMuted
                                    ? const Color(0xFF5C7084)
                                    : const Color(0xFF2EA6FF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              item.unreadCount > 99
                                  ? '99+'
                                  : '${item.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        if (isPinned) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.push_pin_rounded,
                            size: 16,
                            color: Color(0xFF62788D),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _previewText(InboxItem item, String Function(String key) t) {
    final callInfo = _parseCallMessage(item.lastMessage);
    if (callInfo != null) {
      return callInfo.isMissed
          ? t('call_missed')
          : t(callInfo.isVideo ? 'call_video' : 'call_audio');
    }

    switch (item.lastMessage) {
      case '[image]':
        return '${String.fromCharCode(0x1F5BC)} ${t('chat_photo')}';
      case '[video]':
        return '${String.fromCharCode(0x1F3AC)} ${t('chat_video')}';
      case '[audio]':
        return '${String.fromCharCode(0x1F399)} ${t('chat_voice_message')}';
      default:
        return item.lastMessage.isEmpty
            ? '@${item.username}'
            : item.lastMessage;
    }
  }
}

class _ParsedCallMessage {
  const _ParsedCallMessage({
    required this.isVideo,
    required this.isMissed,
    required this.durationSeconds,
  });

  final bool isVideo;
  final bool isMissed;
  final int durationSeconds;
}

class _CallMessageTile extends StatelessWidget {
  const _CallMessageTile({
    required this.info,
    required this.isMine,
    required this.settings,
  });

  final _ParsedCallMessage info;
  final bool isMine;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    final color = info.isMissed
        ? const Color(0xFFD95555)
        : const Color(0xFF3FA66A);

    final title = info.isMissed
        ? t('call_missed')
        : t(info.isVideo ? 'call_video' : 'call_audio');

    final subtitle =
        info.isMissed ? null : _formatCallDuration(info.durationSeconds);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(settings.isDarkMode ? 28 : 10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            info.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: info.isMissed ? color : null,
                      ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isMine
                              ? Colors.black54
                              : settings.isDarkMode
                                  ? Colors.white70
                                  : Colors.black54,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
