part of '../chat_page.dart';

final RegExp _callMessagePattern =
    RegExp(r'^__CALL:(audio|video):(missed|\d+)__$');

_ParsedCallMessage? _parseCallMessage(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  final match = _callMessagePattern.firstMatch(value);
  if (match == null) {
    return null;
  }

  final durationToken = match.group(2) ?? 'missed';
  return _ParsedCallMessage(
    isVideo: match.group(1) == 'video',
    isMissed: durationToken == 'missed',
    durationSeconds:
        durationToken == 'missed' ? 0 : int.tryParse(durationToken) ?? 0,
  );
}

const String _locationMessagePrefix = '__LOCATION__:';
final RegExp _locationMessagePattern =
    RegExp(r'^__LOCATION__:(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$');

class _ParsedLocationMessage {
  const _ParsedLocationMessage({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

String _encodeLocationPayload(double latitude, double longitude) {
  return '$_locationMessagePrefix${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
}

_ParsedLocationMessage? _parseLocationMessage(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  final match = _locationMessagePattern.firstMatch(value.trim());
  if (match == null) {
    return null;
  }

  final lat = double.tryParse(match.group(1) ?? '');
  final lng = double.tryParse(match.group(2) ?? '');
  if (lat == null || lng == null) {
    return null;
  }
  return _ParsedLocationMessage(latitude: lat, longitude: lng);
}

String _formatCallDuration(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _fileNameFromPath(String value) {
  final sanitized = value.split('?').first;
  final parts = sanitized.split(RegExp(r'[\\/]'));
  for (final part in parts.reversed) {
    if (part.isNotEmpty) {
      return part;
    }
  }
  return value;
}
