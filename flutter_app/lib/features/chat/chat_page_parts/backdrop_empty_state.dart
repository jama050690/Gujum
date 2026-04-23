part of '../chat_page.dart';

class _ChatBackdrop extends StatelessWidget {
  const _ChatBackdrop({
    required this.settings,
    required this.child,
  });

  final SettingsController settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ChatPatternPainter(
        backgroundColor: settings.isDarkMode
            ? const Color(0xFF10202B)
            : const Color(0xFFE8F4FB),
        accentColor: settings.isDarkMode
            ? const Color(0xFF173344)
            : const Color(0xFFD2E8F5),
      ),
      child: SizedBox.expand(child: child),
    );
  }
}

class _ChatPatternPainter extends CustomPainter {
  const _ChatPatternPainter({
    required this.backgroundColor,
    required this.accentColor,
  });

  final Color backgroundColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = backgroundColor;
    final dotPaint = Paint()..color = accentColor.withAlpha(120);
    final trianglePaint = Paint()..color = accentColor.withAlpha(95);

    canvas.drawRect(Offset.zero & size, background);

    for (double y = 18; y < size.height + 32; y += 42) {
      for (double x = 22; x < size.width + 32; x += 58) {
        canvas.drawCircle(Offset(x, y), 2, dotPaint);
        final triangle = Path()
          ..moveTo(x + 14, y + 10)
          ..lineTo(x + 20, y + 10)
          ..lineTo(x + 17, y + 15)
          ..close();
        canvas.drawPath(triangle, trianglePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChatPatternPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.accentColor != accentColor;
  }
}

class _BrandEmptyState extends StatelessWidget {
  const _BrandEmptyState({
    required this.settings,
    required this.title,
    required this.subtitle,
  });

  final SettingsController settings;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 144,
              height: 144,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: settings.isDarkMode
                    ? Colors.white.withAlpha(10)
                    : Colors.white.withAlpha(105),
                borderRadius: BorderRadius.circular(34),
              ),
              child: Opacity(
                opacity: settings.isDarkMode ? 0.85 : 0.92,
                child: Image.asset(
                  'assets/images/bootchat_logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: settings.isDarkMode ? Colors.white70 : Colors.white,
                  ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color:
                          settings.isDarkMode ? Colors.white54 : Colors.white70,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
