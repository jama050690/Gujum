part of '../chat_page.dart';

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.label,
    required this.imageUrl,
    this.radius = 24,
    this.online = false,
  });

  final String label;
  final String imageUrl;
  final double radius;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final parts = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .take(2)
        .toList();
    final initials =
        parts.map((item) => item.substring(0, 1).toUpperCase()).join();
    final palette = <Color>[
      const Color(0xFF52B9C0),
      const Color(0xFF7FB5E7),
      const Color(0xFFE7C957),
      const Color(0xFF83C7A4),
      const Color(0xFFC58DD8),
      const Color(0xFFE59C67),
    ];
    final hash = label.runes.fold<int>(0, (value, rune) => value + rune);
    final background = palette[hash % palette.length];
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: radius * 0.6,
      fontWeight: FontWeight.w700,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: background,
          foregroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
          child: Text(initials.isEmpty ? '?' : initials, style: textStyle),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: radius * 0.46,
              height: radius * 0.46,
              decoration: BoxDecoration(
                color: const Color(0xFF41D481),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF17212B),
                  width: radius * 0.1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _formatClock(DateTime? value) {
  if (value == null) {
    return '';
  }

  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatAudioDuration(Duration value) {
  final totalSeconds = value.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _formatInboxTime(DateTime? value, String localeCode) {
  if (value == null) {
    return '';
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(value.year, value.month, value.day);

  if (target == today) {
    return _formatClock(value);
  }

  if (target == today.subtract(const Duration(days: 1))) {
    return AppStrings.text(localeCode, 'yesterday');
  }

  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

// Inbox uchun: doim aniq vaqt — bugun HH:mm da, kecha, yoki DD.MM.YYYY
String _formatLastSeenClock(DateTime? value, String localeCode) {
  if (value == null) return AppStrings.text(localeCode, 'offline');

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(value.year, value.month, value.day);

  // Bugun: aniq soat "21:37 da"
  if (target == today) {
    final clock = _formatClock(value);
    return AppStrings.text(localeCode, 'time_at').replaceAll('{time}', clock);
  }

  // Kecha
  if (target == today.subtract(const Duration(days: 1))) {
    return AppStrings.text(localeCode, 'time_yesterday');
  }

  // 30 kundan kam
  final diff = now.difference(value);
  if (diff.inDays < 30) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  // 30 kundan ortiq
  final months = (diff.inDays / 30).floor();
  if (months < 12) {
    return AppStrings.text(localeCode, 'time_months_ago')
        .replaceAll('{n}', '$months');
  }
  final years = (diff.inDays / 365).floor();
  return AppStrings.text(localeCode, 'time_years_ago')
      .replaceAll('{n}', '$years');
}

// Chat header uchun: X daqiqa/soat oldin, kecha, yoki DD.MM.YYYY
String _formatLastSeenStatus(DateTime? value, String localeCode) {
  if (value == null) {
    return AppStrings.text(localeCode, 'offline');
  }

  final prefix = AppStrings.text(localeCode, 'last_seen_prefix');
  return '$prefix${_formatRelativeTime(value, localeCode)}';
}

String _formatRelativeTime(DateTime value, String localeCode) {
  final now = DateTime.now();
  final difference = now.difference(value);

  if (difference.inMinutes < 1) {
    return AppStrings.text(localeCode, 'time_just_now');
  }

  if (difference.inHours < 1) {
    final minutes = difference.inMinutes;
    return AppStrings.text(localeCode, 'time_minutes_ago')
        .replaceAll('{n}', '$minutes');
  }

  if (difference.inDays < 1) {
    final hours = difference.inHours;
    return AppStrings.text(localeCode, 'time_hours_ago')
        .replaceAll('{n}', '$hours');
  }

  if (difference.inDays < 2) {
    return AppStrings.text(localeCode, 'time_yesterday');
  }

  if (difference.inDays < 30) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  final months = (difference.inDays / 30).floor();
  if (months < 12) {
    return AppStrings.text(localeCode, 'time_months_ago')
        .replaceAll('{n}', '$months');
  }

  final years = (difference.inDays / 365).floor();
  return AppStrings.text(localeCode, 'time_years_ago')
      .replaceAll('{n}', '$years');
}
