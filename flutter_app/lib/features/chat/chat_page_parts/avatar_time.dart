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

  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$day.$month';
}

// Inbox uchun: bugun HH:mm, kecha, yoki DD.MM.YYYY
String _formatLastSeenClock(DateTime? value, String localeCode) {
  if (value == null) return AppStrings.text(localeCode, 'offline');

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(value.year, value.month, value.day);

  if (target == today) return _formatClock(value);

  if (target == today.subtract(const Duration(days: 1))) {
    return switch (localeCode) {
      'ru' => 'вчера',
      'en' => 'yesterday',
      _ => 'kecha',
    };
  }

  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

// Chat header uchun: X daqiqa/soat oldin, kecha, yoki DD.MM.YYYY
String _formatLastSeenStatus(DateTime? value, String localeCode) {
  if (value == null) {
    return AppStrings.text(localeCode, 'offline');
  }

  final prefix = switch (localeCode) {
    'ru' => 'Был(а) в сети ',
    'en' => 'last seen ',
    _ => 'Oxirgi marta ',
  };
  return '$prefix${_formatRelativeTime(value, localeCode)}';
}

String _formatRelativeTime(DateTime value, String localeCode) {
  final now = DateTime.now();
  final difference = now.difference(value);

  if (difference.inMinutes < 1) {
    return switch (localeCode) {
      'ru' => 'только что',
      'en' => 'just now',
      _ => 'hozirgina',
    };
  }

  if (difference.inHours < 1) {
    final minutes = difference.inMinutes;
    return switch (localeCode) {
      'ru' => '$minutes мин назад',
      'en' => '$minutes minutes ago',
      _ => '$minutes daqiqa oldin',
    };
  }

  if (difference.inDays < 1) {
    final hours = difference.inHours;
    return switch (localeCode) {
      'ru' => '$hours ч назад',
      'en' => '$hours hours ago',
      _ => '$hours soat oldin',
    };
  }

  if (difference.inDays < 2) {
    return switch (localeCode) {
      'ru' => 'вчера',
      'en' => 'yesterday',
      _ => 'kecha',
    };
  }

  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year;
  return '$day.$month.$year';
}
