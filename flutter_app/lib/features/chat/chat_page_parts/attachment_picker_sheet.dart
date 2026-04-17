part of '../chat_page.dart';

class _AttachmentPickerSheet extends StatelessWidget {
  const _AttachmentPickerSheet({
    required this.settings,
    required this.t,
    required this.onSelectAction,
  });

  final SettingsController settings;
  final String Function(String) t;
  final ValueChanged<_AttachmentType> onSelectAction;

  @override
  Widget build(BuildContext context) {
    final background = settings.isDarkMode
        ? const Color(0xFF162434)
        : const Color(0xFF1D2F45);
    final card = settings.isDarkMode
        ? const Color(0xFF24384B)
        : const Color(0xFF27425E);

    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.28,
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(55),
              blurRadius: 18,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 56,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              color: card,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 0.95,
                children: [
                  _AttachmentActionTile(
                    icon: Icons.photo_library_outlined,
                    label: t('chat_gallery'),
                    onTap: () => onSelectAction(_AttachmentType.image),
                  ),
                  _AttachmentActionTile(
                    icon: Icons.videocam_outlined,
                    label: t('chat_video'),
                    onTap: () => onSelectAction(_AttachmentType.video),
                  ),
                  _AttachmentActionTile(
                    icon: Icons.audio_file_outlined,
                    label: t('chat_audio'),
                    onTap: () => onSelectAction(_AttachmentType.audio),
                  ),
                  _AttachmentActionTile(
                    icon: Icons.insert_drive_file_outlined,
                    label: t('chat_document'),
                    onTap: () => onSelectAction(_AttachmentType.file),
                  ),
                  _AttachmentActionTile(
                    icon: Icons.location_on_outlined,
                    label: t('chat_location'),
                    onTap: () => onSelectAction(_AttachmentType.location),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentActionTile extends StatelessWidget {
  const _AttachmentActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
