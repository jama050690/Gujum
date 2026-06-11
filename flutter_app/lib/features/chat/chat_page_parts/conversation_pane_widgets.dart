part of '../chat_page.dart';

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({
    required this.date,
    required this.localeCode,
    required this.isDark,
  });

  final DateTime date;
  final String localeCode;
  final bool isDark;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    if (target == today) {
      return switch (localeCode) { 'ru' => 'Сегодня', 'en' => 'Today', _ => 'Bugun' };
    }
    if (target == today.subtract(const Duration(days: 1))) {
      return switch (localeCode) { 'ru' => 'Вчера', 'en' => 'Yesterday', _ => 'Kecha' };
    }
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d.$m.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFDCEAF5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _label(),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF8EA3B7) : const Color(0xFF5B7A9A),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
