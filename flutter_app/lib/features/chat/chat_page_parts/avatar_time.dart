part of '../chat_page.dart';

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.label,
    required this.imageUrl,
    this.radius = 24,
  });

  final String label;
  final String imageUrl;
  final double radius;

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

    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      foregroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
      child: Text(initials.isEmpty ? '?' : initials, style: textStyle),
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

  final year = (value.year % 100).toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
