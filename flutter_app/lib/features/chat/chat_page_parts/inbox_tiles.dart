part of '../chat_page.dart';

class _InboxTile extends StatelessWidget {
  const _InboxTile({
    required this.settings,
    required this.item,
    required this.isOnline,
    required this.lastActive,
    required this.isPinned,
    required this.isMuted,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
    this.currentUsername,
  });

  final SettingsController settings;
  final InboxItem item;
  final bool isOnline;
  final DateTime? lastActive;
  final bool isPinned;
  final bool isMuted;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  /// "Siz:" prefiksini qo'yish uchun kerak.
  final String? currentUsername;

  @override
  Widget build(BuildContext context) {
    final t = (String key) => AppStrings.text(settings.localeCode, key);
    final isDark = settings.isDarkMode;
    final activeColor =
        isDark ? const Color(0xFF253444) : const Color(0xFFE8F2FD);
    final titleColor =
        isDark ? Colors.white : const Color(0xFF17212B);
    final previewColor =
        isDark ? const Color(0xFF8FA3B6) : const Color(0xFF6A7C8F);
    final dividerColor =
        isDark ? const Color(0xFF223140) : const Color(0xFFE4EBF3);
    final timeColor = item.unreadCount > 0
        ? const Color(0xFF2EA6FF)
        : (isDark ? const Color(0xFF8FA3B6) : const Color(0xFF91A0AE));
    final badgeColor = isMuted
        ? (isDark ? const Color(0xFF5C7084) : const Color(0xFFB8C5D1))
        : const Color(0xFF2EA6FF);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: isActive ? activeColor : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(
              label: item.fullName,
              imageUrl:
                  AppConfig.resolveMediaUrl(item.avatar, settings.baseUrl),
              radius: 28,
              online: isOnline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive
                          ? Colors.transparent
                          : dividerColor,
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
                                  color: titleColor,
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
                                    color: timeColor,
                                    fontWeight: item.unreadCount > 0
                                        ? FontWeight.w600
                                        : FontWeight.w500,
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
                                  height: 1.2,
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
                                  ? const Color(0xFF7FBFFF)
                                  : badgeColor,
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
                          Icon(
                            Icons.push_pin_rounded,
                            size: 16,
                            color: isDark
                                ? const Color(0xFF62788D)
                                : const Color(0xFF9AAAB8),
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
    final mine = item.lastSender != null && item.lastSender == currentUsername;

    final callInfo = _parseCallMessage(item.lastMessage);
    if (callInfo != null) {
      // Ilgari faqat "Ovozli qo'ng'iroq" deb turardi — kim qilgani ham,
      // qancha davom etgani ham ko'rinmasdi.
      if (callInfo.isMissed) {
        return '${mine ? '↗' : '↙'} ${t('call_missed')}';
      }
      final label = t(callInfo.isVideo ? 'call_video' : 'call_audio');
      final duration = _formatCallDuration(callInfo.durationSeconds);
      return '${mine ? '↗' : '↙'} $label · $duration';
    }

    // Media va fayllar uchun ham "Siz:" prefiksi qo'yiladi.
    String withSender(String text) => mine ? '${t('you')}: $text' : text;

    switch (item.lastMessage) {
      case '[image]':
        return withSender('${String.fromCharCode(0x1F5BC)} ${t('chat_photo')}');
      case '[video]':
        return withSender('${String.fromCharCode(0x1F3AC)} ${t('chat_video')}');
      case '[audio]':
        return withSender(
            '${String.fromCharCode(0x1F399)} ${t('chat_voice_message')}');
      case '[file]':
        return withSender('${String.fromCharCode(0x1F4CE)} ${t('chat_file')}');
      case '[location]':
        return withSender('${String.fromCharCode(0x1F4CD)} ${t('chat_location')}');
      default:
        // Xabar bo'lmasa bo'sh qoldiramiz. Ilgari bu yerda onlayn holati
        // ko'rsatilardi va u oxirgi xabar bilan chalkashib ketardi.
        return item.lastMessage.isEmpty ? '' : withSender(item.lastMessage);
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

    // Telegram qo'ng'iroq yozuvini alohida kartaga o'ramaydi — u pufakcha
    // ichida oddiy qator bo'lib turadi, shuning uchun fon ham, ichki
    // padding ham olib tashlandi.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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
