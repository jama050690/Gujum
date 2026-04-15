part of '../chat_page.dart';

class _AttachmentPickerSheet extends StatelessWidget {
  const _AttachmentPickerSheet({
    required this.settings,
    required this.t,
    required this.loadRecentMedia,
    required this.onSelectAsset,
    required this.onSelectAction,
  });

  final SettingsController settings;
  final String Function(String) t;
  final Future<List<AssetEntity>> Function() loadRecentMedia;
  final ValueChanged<AssetEntity> onSelectAsset;
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
        height: MediaQuery.of(context).size.height * 0.44,
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
            Expanded(
              child: FutureBuilder<List<AssetEntity>>(
                future: loadRecentMedia(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final assets = snapshot.data ?? const <AssetEntity>[];
                  if (assets.isEmpty) {
                    return Center(
                      child: Text(
                        t('chat_recent_media_empty'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: assets.length,
                    itemBuilder: (context, index) {
                      final asset = assets[index];
                      return _RecentMediaTile(
                        asset: asset,
                        onTap: () => onSelectAsset(asset),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              color: card,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
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

class _RecentMediaTile extends StatelessWidget {
  const _RecentMediaTile({
    required this.asset,
    required this.onTap,
  });

  final AssetEntity asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(
        const ThumbnailSize(320, 320),
        quality: 85,
      ),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: bytes == null ? null : onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFF30485F),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.memory(bytes, fit: BoxFit.cover),
                    )
                  else
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (asset.type == AssetType.video)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(145),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Icon(
                          Icons.videocam_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
