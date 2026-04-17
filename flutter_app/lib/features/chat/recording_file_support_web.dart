Future<String> createRecordingPath(String extension) async {
  final normalizedExtension = extension.trim().replaceFirst('.', '');
  return 'bootchat_voice_${DateTime.now().millisecondsSinceEpoch}.'
      '$normalizedExtension';
}

Future<void> deleteRecordingFile(String _) async {}
