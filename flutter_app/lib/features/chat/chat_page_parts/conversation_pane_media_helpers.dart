part of '../chat_page.dart';

extension _ConversationPaneMediaHelpers on _ConversationPaneState {
Widget _buildMediaTimeBadge(
  String label,
  bool isMine,
  bool isRead,
) {
  return Positioned(
    right: 8,
    bottom: 8,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isMine) ...[
            const SizedBox(width: 4),
            Icon(
              isRead ? Icons.done_all_rounded : Icons.done_rounded,
              size: 12,
              color: const Color(0xFF6DB870),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _buildImageAttachment(
  String imagePath, {
  bool showTimeOverlay = false,
  String? timeLabel,
  bool isMine = false,
  bool isRead = false,
}) {
  final imageUrl =
      AppConfig.resolveMediaUrl(imagePath, widget.settings.baseUrl);
  final heroTag = 'image-$imagePath';

  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openImageViewer(imageUrl, heroTag),
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 360),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                Hero(
                  tag: heroTag,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }

                      return Container(
                        color: Colors.black.withAlpha(12),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        color: Colors.black.withAlpha(12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_outlined, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _fileNameFromPath(imagePath),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (showTimeOverlay && timeLabel != null)
                  _buildMediaTimeBadge(timeLabel, isMine, isRead),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildVideoAttachment(
  String videoPath,
  String Function(String) t, {
  bool showTimeOverlay = false,
  String? timeLabel,
  bool isMine = false,
  bool isRead = false,
}) {
  final videoUrl =
      AppConfig.resolveMediaUrl(videoPath, widget.settings.baseUrl);
  final preview = _InlineVideoPreview(
    videoUrl: videoUrl,
    label: _fileNameFromPath(videoPath),
    onTap: () => _openVideoViewer(videoPath, t),
  );
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: showTimeOverlay && timeLabel != null
        ? Stack(
            alignment: Alignment.bottomRight,
            children: [
              preview,
              _buildMediaTimeBadge(timeLabel, isMine, isRead),
            ],
          )
        : preview,
  );
}

Widget _buildAudioAttachment(String audioPath, bool isMine) {
  final audioUrl =
      AppConfig.resolveMediaUrl(audioPath, widget.settings.baseUrl);
  final safeAudioUrl = Uri.encodeFull(audioUrl);
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: _InlineAudioMessage(
      audioUrl: safeAudioUrl,
      isMine: isMine,
      label: _fileNameFromPath(audioPath),
    ),
  );
}

Widget _buildLocationChip(
  _ParsedLocationMessage location,
  String Function(String) t,
) {
  final label = t('chat_location');
  final coords =
      '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
  return _buildFileChip(
    icon: Icons.location_on_outlined,
    label: '$label: $coords',
    onTap: () => _openLocation(location, t),
  );
}

Widget _buildFileChip({
  required IconData icon,
  required String label,
  VoidCallback? onTap,
}) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _openLocation(
  _ParsedLocationMessage location,
  String Function(String) t,
) async {
  final url =
      'https://www.google.com/maps?q=${location.latitude},${location.longitude}';
  final uri = Uri.tryParse(url);
  if (uri == null) {
    _showInfoSnackBar(t('chat_open_file_failed'));
    return;
  }

  final opened = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
  if (!opened && mounted) {
    _showInfoSnackBar(t('chat_open_file_failed'));
  }
}

Future<void> _openRemoteFile(
  String path,
  String Function(String) t,
) async {
  final url = AppConfig.resolveMediaUrl(path, widget.settings.baseUrl);
  final uri = Uri.tryParse(url);
  if (uri == null) {
    _showInfoSnackBar(t('chat_open_file_failed'));
    return;
  }

  final opened = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
  if (!opened && mounted) {
    _showInfoSnackBar(t('chat_open_file_failed'));
  }
}

void _openImageViewer(String imageUrl, String heroTag) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ImageViewerPage(
        imageUrl: imageUrl,
        heroTag: heroTag,
      ),
    ),
  );
}

void _openVideoViewer(
  String path,
  String Function(String) t,
) {
  final videoUrl = AppConfig.resolveMediaUrl(path, widget.settings.baseUrl);
  final uri = Uri.tryParse(videoUrl);
  if (uri == null) {
    _showInfoSnackBar(t('chat_open_file_failed'));
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => VideoViewerPage(
        videoUrl: uri.toString(),
        title: _fileNameFromPath(path),
      ),
    ),
  );
}
}
