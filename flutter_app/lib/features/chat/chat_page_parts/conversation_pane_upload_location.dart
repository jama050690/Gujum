part of '../chat_page.dart';

extension _ConversationPaneUploadLocation on _ConversationPaneState {
Future<void> _uploadAndSendAttachment(
  ChatController chat,
  String Function(String) t,
  _AttachmentType type, {
  XFile? xFile,
  PlatformFile? platformFile,
}) async {
  if (_uploadingAttachment) {
    return;
  }

  String uploadedPath;
  setState(() => _uploadingAttachment = true);
  try {
    switch (type) {
      case _AttachmentType.audio:
        final file = platformFile;
        if (file == null || !_matchesAllowedExtension(file, _ConversationPaneState._audioExtensions)) {
          _showInfoSnackBar(t('chat_invalid_file_type'));
          return;
        }
        uploadedPath = await chat.uploadPickedAudio(file);
        break;
      case _AttachmentType.video:
        const _maxVideoBytes = 500 * 1024 * 1024;
        if (platformFile != null) {
          if (!_matchesAllowedExtension(platformFile, _ConversationPaneState._videoExtensions)) {
            _showInfoSnackBar(t('chat_invalid_file_type'));
            return;
          }
          if (platformFile.size > _maxVideoBytes) {
            _showInfoSnackBar('Video hajmi 500MB dan oshmasligi kerak');
            return;
          }
          uploadedPath = await chat.uploadPickedVideo(platformFile);
        } else {
          final file = xFile;
          if (file == null ||
              !_matchesAllowedXFile(
                file,
                _ConversationPaneState._videoExtensions,
              )) {
            _showInfoSnackBar(t('chat_invalid_file_type'));
            return;
          }
          final fileSize = await file.length();
          if (fileSize > _maxVideoBytes) {
            _showInfoSnackBar('Video hajmi 500MB dan oshmasligi kerak');
            return;
          }
          uploadedPath = await chat.uploadXFileVideo(file);
        }
        break;
      case _AttachmentType.image:
        if (platformFile != null) {
          if (!_matchesAllowedExtension(platformFile, _ConversationPaneState._imageExtensions)) {
            _showInfoSnackBar(t('chat_invalid_file_type'));
            return;
          }
          uploadedPath = await chat.uploadPickedMedia(platformFile);
        } else {
          final file = xFile;
          if (file == null ||
              !_matchesAllowedXFile(
                file,
                _ConversationPaneState._imageExtensions,
              )) {
            _showInfoSnackBar(t('chat_invalid_file_type'));
            return;
          }
          uploadedPath = await chat.uploadXFileMedia(file);
        }
        break;
      case _AttachmentType.file:
        final file = platformFile;
        if (file == null) {
          _showInfoSnackBar(t('chat_open_file_failed'));
          return;
        }
        uploadedPath = await chat.uploadPickedMedia(file);
        break;
      case _AttachmentType.location:
        _showInfoSnackBar(t('chat_action_unavailable'));
        return;
    }

    final sent = await chat.sendMessage(
      message: type == _AttachmentType.audio ? '' : _messageController.text,
      image: (type == _AttachmentType.image || type == _AttachmentType.file)
          ? uploadedPath
          : null,
      audio: type == _AttachmentType.audio ? uploadedPath : null,
      video: type == _AttachmentType.video ? uploadedPath : null,
      replyTo: _replyPayloadForMessage(_replyingTo, t),
    );
    if (sent) {
      if (type != _AttachmentType.audio) {
        _messageController.clear();
      }
      if (_replyingTo != null) {
        setState(() => _replyingTo = null);
      }
      _requestScrollToNewest();
      return;
    }
    if (!mounted) {
      return;
    }
    _showInfoSnackBar(t('message_send_failed'));
  } finally {
    if (mounted) {
      setState(() => _uploadingAttachment = false);
    }
  }
}

Future<void> _sendLocation(
  ChatController chat,
  String Function(String) t,
) async {
  if (_locatingLocation || _uploadingAttachment) {
    return;
  }

  setState(() => _locatingLocation = true);
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showInfoSnackBar(t('chat_location_disabled'));
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showInfoSnackBar(t('chat_location_permission_denied'));
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 12),
    );

    final payload = _encodeLocationPayload(
      position.latitude,
      position.longitude,
    );

    final sent = await chat.sendMessage(
      message: payload,
      replyTo: _replyPayloadForMessage(_replyingTo, t),
    );

    if (sent) {
      if (_replyingTo != null) {
        setState(() => _replyingTo = null);
      }
      _messageController.clear();
      _requestScrollToNewest();
      return;
    }
    _showInfoSnackBar(t('message_send_failed'));
  } catch (_) {
    _showInfoSnackBar(t('chat_location_failed'));
  } finally {
    if (mounted) {
      setState(() => _locatingLocation = false);
    }
  }
}

Future<List<XFile>> _pickMultipleImages() async {
  return _imagePicker.pickMultiImage(
    imageQuality: 88,
    maxWidth: 2048,
    maxHeight: 2048,
  );
}

Future<XFile?> _pickVideoAttachment() {
  return _imagePicker.pickVideo(source: ImageSource.gallery);
}

Future<PlatformFile?> _pickGenericAttachment() async {
  final result = await FilePicker.pickFiles(
    type: FileType.any,
    allowMultiple: false,
    withData: kIsWeb,
    withReadStream: !kIsWeb,
  );

  final file = result?.files.single;
  final filePath = file?.path;
  if (file == null ||
      ((filePath == null || filePath.isEmpty) &&
          file.readStream == null &&
          file.bytes == null)) {
    return null;
  }
  return file;
}

Future<PlatformFile?> _pickAudioAttachment() async {
  final result = await FilePicker.pickFiles(
    type: FileType.audio,
    allowMultiple: false,
    withData: kIsWeb,
    withReadStream: !kIsWeb,
  );

  final file = result?.files.single;
  final filePath = file?.path;
  if (file == null ||
      ((filePath == null || filePath.isEmpty) &&
          file.readStream == null &&
          file.bytes == null)) {
    return null;
  }
  return file;
}
}
