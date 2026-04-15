part of '../chat_page.dart';

extension _ConversationPaneRecentMedia on _ConversationPaneState {
Future<List<AssetEntity>> _loadRecentMedia() async {
  final permission = await PhotoManager.requestPermissionExtend();
  if (!permission.isAuth) {
    return const <AssetEntity>[];
  }

  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.common,
    onlyAll: true,
  );
  if (paths.isEmpty) {
    return const <AssetEntity>[];
  }

  return paths.first.getAssetListPaged(page: 0, size: 12);
}

Future<void> _sendRecentAsset(
  ChatController chat,
  String Function(String) t,
  AssetEntity asset,
) async {
  if (_uploadingAttachment) {
    return;
  }

  final file = await asset.originFile ?? await asset.file;
  if (file == null) {
    _showInfoSnackBar(t('chat_open_file_failed'));
    return;
  }

  final type = asset.type == AssetType.video
      ? _AttachmentType.video
      : _AttachmentType.image;
  await _uploadAndSendAttachment(
    chat,
    t,
    type,
    xFile: XFile(file.path),
  );
}

Future<void> _pickAndSendAttachment(
  ChatController chat,
  String Function(String) t,
  _AttachmentType type,
) async {
  if (_uploadingAttachment) {
    return;
  }

  try {
    if (type == _AttachmentType.location) {
      await _sendLocation(chat, t);
      return;
    }

    if (type == _AttachmentType.audio) {
      final pickedFile = await _pickAudioAttachment();
      if (pickedFile == null) {
        return;
      }
      await _uploadAndSendAttachment(chat, t, _AttachmentType.audio,
          platformFile: pickedFile);
      return;
    }

    if (type == _AttachmentType.file) {
      final pickedFile = await _pickGenericAttachment();
      if (pickedFile == null) {
        return;
      }
      await _uploadAndSendAttachment(
        chat,
        t,
        _AttachmentType.file,
        platformFile: pickedFile,
      );
      return;
    }

    if (type == _AttachmentType.video) {
      final pickedVideo = await _pickVideoAttachment();
      if (pickedVideo == null) {
        return;
      }
      await _uploadAndSendAttachment(chat, t, _AttachmentType.video,
          xFile: pickedVideo);
      return;
    }

    final pickedImage = await _pickImageAttachment();
    if (pickedImage == null) {
      return;
    }
    await _uploadAndSendAttachment(chat, t, _AttachmentType.image,
        xFile: pickedImage);
  } catch (error, stackTrace) {
    debugPrint('Attachment upload failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (!mounted) {
      return;
    }
    if (error is ApiException) {
      _showInfoSnackBar(error.message);
    } else {
      _showInfoSnackBar(t('chat_upload_failed'));
    }
  }
}
}
