import 'package:flutter/foundation.dart';

class AppConfig {
  static const defaultSocketPath = '/api/bootchat/socket.io/';
  static const defaultLocale = 'uz';
  static const defaultPort = 4000;
  static const productionBaseUrl = 'https://gujum.jamshiddin.uz';
  static const androidUsbBaseUrl = 'http://127.0.0.1:4000';
  static const androidLanBaseUrl = 'http://10.10.3.180:4000';
  static const desktopLoopbackBaseUrl = 'http://127.0.0.1:4000';
  static const webLoopbackBaseUrl = 'http://localhost:4000';
  /// Haqiqiy versiya build vaqtida beriladi (CI --dart-define orqali
  /// pubspec dagi qiymatni uzatadi). Ilgari yon panelda qo'lda yozilgan
  /// "Gujum v2.0" turardi va u hech qachon o'zgarmasdi.
  static const appVersion = String.fromEnvironment(
    'GUJUM_VERSION',
    defaultValue: 'dev',
  );

  static const googleServerClientId = String.fromEnvironment(
    'GUJUM_GOOGLE_CLIENT_ID',
    defaultValue:
        '1096233590187-csb14eqr9q8mml0vdvlqiektakpcvbgq.apps.googleusercontent.com',
  );

  static String defaultBaseUrl() {
    const fromDefine = String.fromEnvironment('GUJUM_API_BASE_URL');
    if (fromDefine.isNotEmpty) {
      return _normalizeBaseUrl(fromDefine);
    }

    if (kIsWeb) {
      final uri = Uri.base;
      final isLocalHost = uri.host == 'localhost' || uri.host == '127.0.0.1';
      if (isLocalHost) {
        return webLoopbackBaseUrl;
      }

      return _originFromUri(uri) ?? productionBaseUrl;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return productionBaseUrl;
    }
  }

  static bool shouldUpgradeStoredBaseUrl(String value) {
    final normalized = _normalizeBaseUrl(value);
    return normalized == 'http://10.0.2.2:3003' ||
        normalized == 'http://10.0.2.2:4000' ||
        normalized == 'http://127.0.0.1:3003' ||
        normalized == 'http://localhost:3003' ||
        normalized == androidLanBaseUrl ||
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

    return _originFromUri(uri) ?? normalized;
  }

  static String socketPath(String value) {
    final rawValue = value.trim();
    final uri = Uri.tryParse(rawValue);
    if (uri == null) {
      return defaultSocketPath;
    }

    final normalizedPath = _normalizePath(uri.path);
    if (normalizedPath.isEmpty ||
        normalizedPath == '/api' ||
        normalizedPath == '/api/bootchat' ||
        normalizedPath == '/bootchat') {
      return defaultSocketPath;
    }

    return '$normalizedPath${defaultSocketPath.startsWith('/') ? defaultSocketPath : '/$defaultSocketPath'}';
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
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return normalized;
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return normalized.replaceFirst(RegExp(r'/$'), '');
    }

    return _originFromUri(uri) ?? normalized.replaceFirst(RegExp(r'/$'), '');
  }

  static String _joinUrl(String base, String path) {
    final normalizedBase = _normalizeBaseUrl(base);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.encodeFull('$normalizedBase$normalizedPath');
  }

  static String _normalizePath(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty || normalized == '/') {
      return '';
    }

    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }

    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    return normalized;
  }

  static String? _originFromUri(Uri uri) {
    if (!uri.hasScheme || uri.host.isEmpty) {
      return null;
    }

    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString().replaceFirst(RegExp(r'/$'), '');
  }
}
