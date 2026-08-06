part of '../chat_page.dart';

extension _ConversationPaneRecording on _ConversationPaneState {
bool _matchesAllowedExtension(
  PlatformFile file,
  Set<String> allowedExtensions,
) {
  final extension =
      file.extension?.trim().toLowerCase() ?? _fileExtension(file.name);
  return extension != null && allowedExtensions.contains(extension);
}

bool _matchesAllowedPath(String filePath, Set<String> allowedExtensions) {
  final extension = _fileExtension(filePath);
  return extension != null && allowedExtensions.contains(extension);
}

bool _matchesAllowedXFile(XFile file, Set<String> allowedExtensions) {
  final primary = file.name.trim().isNotEmpty ? file.name : file.path;
  return _matchesAllowedPath(primary, allowedExtensions);
}

String? _fileExtension(String value) {
  final dotIndex = value.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == value.length - 1) {
    return null;
  }
  return value.substring(dotIndex + 1).trim().toLowerCase();
}

Future<void> _toggleVoiceRecording(
  ChatController chat,
  String Function(String) t,
) async {
  if (_uploadingAttachment) {
    return;
  }
  if (_editingMessage != null) {
    _showInfoSnackBar(t('message_edit_attachment_unavailable'));
    return;
  }

  if (_isRecordingVoice) {
    await _stopAndSendVoiceRecording(chat, t);
    return;
  }

  try {
    final allowed = await _audioRecorder.hasPermission();
    if (!allowed) {
      _showInfoSnackBar(t('chat_voice_permission_denied'));
      return;
    }

    final tempFile = await createRecordingPath(kIsWeb ? 'wav' : 'm4a');
    await _audioRecorder.start(
      RecordConfig(
        encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: tempFile,
    );

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _recordingSeconds += 1);
    });

    setState(() {
      _isRecordingVoice = true;
      _recordingSeconds = 0;
    });
  } catch (_) {
    _showInfoSnackBar(t('chat_voice_record_failed'));
  }
}

Future<void> _cancelVoiceRecording() async {
  _recordingTimer?.cancel();
  await _audioRecorder.cancel();
  if (!mounted) {
    return;
  }
  setState(() {
    _isRecordingVoice = false;
    _recordingSeconds = 0;
  });
}

Future<void> _stopAndSendVoiceRecording(
  ChatController chat,
  String Function(String) t,
) async {
  _recordingTimer?.cancel();

  String? filePath;
  try {
    filePath = await _audioRecorder.stop();
    if (filePath == null || filePath.isEmpty) {
      throw StateError('Recorded file path is empty');
    }

    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingSeconds = 0;
        _uploadingAttachment = true;
      });
    }

    final uploadedPath = kIsWeb
        ? await chat.uploadXFileAudio(
            XFile(
              filePath,
              name:
                  'gujum_voice_${DateTime.now().millisecondsSinceEpoch}.wav',
            ),
          )
        : await chat.uploadAudio(filePath);
    final sent = await chat.sendMessage(
      audio: uploadedPath,
      replyTo: _replyPayloadForMessage(_replyingTo, t),
    );
    if (sent) {
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
  } catch (_) {
    if (mounted) {
      _showInfoSnackBar(t('chat_voice_record_failed'));
    }
  } finally {
    if (filePath != null) {
      await deleteRecordingFile(filePath);
    }
    if (mounted) {
      setState(() {
        _uploadingAttachment = false;
        _isRecordingVoice = false;
        _recordingSeconds = 0;
      });
    }
  }
}
}
