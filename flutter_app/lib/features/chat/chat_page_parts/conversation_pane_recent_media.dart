part of '../chat_page.dart';

extension _ConversationPaneRecentMedia on _ConversationPaneState {
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
      final pickedFiles = await _pickAudioAttachments();
      for (final file in pickedFiles) {
        await _uploadAndSendAttachment(chat, t, _AttachmentType.audio,
            platformFile: file);
      }
      return;
    }

    if (type == _AttachmentType.file) {
      final pickedFiles = await _pickGenericAttachments();
      for (final file in pickedFiles) {
        await _uploadAndSendAttachment(
          chat,
          t,
          _AttachmentType.file,
          platformFile: file,
        );
      }
      return;
    }

    if (type == _AttachmentType.video) {
      final pickedVideos = await _pickVideoAttachments();
      for (final video in pickedVideos) {
        await _uploadAndSendAttachment(chat, t, _AttachmentType.video,
            platformFile: video);
      }
      return;
    }

    final pickedImages = await _pickMultipleImages();
    if (pickedImages.isEmpty) {
      return;
    }
    for (final image in pickedImages) {
      await _uploadAndSendAttachment(chat, t, _AttachmentType.image,
          xFile: image);
    }
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
