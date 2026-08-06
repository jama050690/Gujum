import 'dart:io';

Future<String> createRecordingPath(String extension) async {
  final normalizedExtension = extension.trim().replaceFirst('.', '');
  return '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'gujum_voice_${DateTime.now().millisecondsSinceEpoch}.'
      '$normalizedExtension';
}

Future<void> deleteRecordingFile(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
