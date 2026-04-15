import 'package:flutter/foundation.dart';

class AppConfig {
  static const defaultSocketPath = '/socket.io';
  static const defaultLocale = 'uz';
  static const defaultPort = 4000;
  static const productionBaseUrl = 'https://www.jamshiddin.uz/api/bootchat';
  static const androidUsbBaseUrl = 'http://127.0.0.1:4000';
  static const androidLanBaseUrl = 'http://10.10.3.180:4000';
  static const desktopLoopbackBaseUrl = 'http://127.0.0.1:4000';
  static const webLoopbackBaseUrl = 'http://localhost:4000';
  static const googleServerClientId = String.fromEnvironment(
    'BOOTCHAT_GOOGLE_CLIENT_ID',
    defaultValue:
        '850901436789-c3al966j46tt4cfn0pqu42obr0guc790.apps.googleusercontent.com',
  );

  static String defaultBaseUrl() {
    const fromDefine = String.fromEnvironment('BOOTCHAT_API_BASE_URL');
    if (fromDefine.isNotEmpty) {
      return _normalizeBaseUrl(fromDefine);
    }

    if (kIsWeb) {
      final uri = Uri.base;
      final isLocalHost = uri.host == 'localhost' || uri.host == '127.0.0.1';
      if (isLocalHost) {
        return webLoopbackBaseUrl;
      }

      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/api/bootchat',
      ).toString().replaceFirst(RegExp(r'/$'), '');
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return productionBaseUrl;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return desktopLoopbackBaseUrl;
    }
  }

  static bool shouldUpgradeStoredBaseUrl(String value) {
    final normalized = _normalizeBaseUrl(value);
    return normalized == 'http://10.0.2.2:3003' ||
        normalized == 'http://127.0.0.1:3003' ||
        normalized == 'http://localhost:3003' ||
        normalized == androidLanBaseUrl ||
        normalized == '$androidLanBaseUrl/api' ||
        normalized == 'http://127.0.0.1:4000' ||
        normalized == 'http://localhost:4000';
  }

  static String normalizeBaseUrl(String value) => _normalizeBaseUrl(value);

  static String socketBaseUrl(String value) {
    final normalized = _normalizeBaseUrl(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return normalized;
    }

    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString().replaceFirst(RegExp(r'/$'), '');
  }

  static String socketPath(String value) {
    final normalized = _normalizeBaseUrl(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return defaultSocketPath;
    }

    final normalizedPath = _normalizeBaseUrl(uri.path);
    if (normalizedPath.isEmpty || normalizedPath == '/api') {
      return defaultSocketPath;
    }

    return '$normalizedPath$defaultSocketPath';
  }

  static String resolveMediaUrl(String? path, String baseUrl) {
    if (path == null || path.trim().isEmpty) {
      return '';
    }

    final trimmed = path.trim().replaceAll('\\', '/');
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Uri.encodeFull(trimmed);
    }

    final normalizedBase = _normalizeBaseUrl(baseUrl);
    final baseUri = Uri.tryParse(normalizedBase);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      return trimmed;
    }

    final origin = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
    ).toString().replaceFirst(RegExp(r'/$'), '');

    final uploadsIndex = trimmed.indexOf('uploads/');
    if (uploadsIndex >= 0) {
      return _joinUrl(origin, trimmed.substring(uploadsIndex));
    }

    if (trimmed.startsWith('/')) {
      return _joinUrl(origin, trimmed);
    }

    return _joinUrl(normalizedBase, trimmed);
  }

  static String _normalizeBaseUrl(String value) {
    var normalized = value.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static String _joinUrl(String base, String path) {
    final normalizedBase = _normalizeBaseUrl(base);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.encodeFull('$normalizedBase$normalizedPath');
  }
}
