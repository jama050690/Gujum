import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'session_store.dart';

class ApiClient {
  ApiClient({
    required SessionStore sessionStore,
    required String Function() baseUrlProvider,
  })  : _sessionStore = sessionStore,
        _baseUrlProvider = baseUrlProvider;

  final SessionStore _sessionStore;
  final String Function() _baseUrlProvider;

  String get baseUrl => AppConfig.normalizeBaseUrl(_baseUrlProvider());

  Future<dynamic> getJson(
    String path, {
    Map<String, String>? query,
    bool authenticated = false,
  }) async {
    final request = http.Request('GET', _buildUri(path, query));
    _applyHeaders(request.headers, authenticated: authenticated);
    final response = await request.send();
    return _decode(response);
  }

  Future<dynamic> postJson(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    final request = http.Request('POST', _buildUri(path));
    _applyHeaders(
      request.headers,
      authenticated: authenticated,
      json: true,
    );
    request.body = jsonEncode(body ?? <String, dynamic>{});
    final response = await request.send();
    return _decode(response);
  }

  Future<dynamic> putJson(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    final request = http.Request('PUT', _buildUri(path));
    _applyHeaders(
      request.headers,
      authenticated: authenticated,
      json: true,
    );
    request.body = jsonEncode(body ?? <String, dynamic>{});
    final response = await request.send();
    return _decode(response);
  }

  Future<dynamic> deleteJson(
    String path, {
    bool authenticated = false,
  }) async {
    final request = http.Request('DELETE', _buildUri(path));
    _applyHeaders(request.headers, authenticated: authenticated);
    final response = await request.send();
    return _decode(response);
  }

  Future<dynamic> multipartPost(
    String path, {
    Map<String, String>? fields,
    List<http.MultipartFile>? files,
    bool authenticated = false,
  }) async {
    final request = http.MultipartRequest('POST', _buildUri(path));
    _applyHeaders(request.headers, authenticated: authenticated);
    request.fields.addAll(fields ?? const <String, String>{});
    request.files.addAll(files ?? const <http.MultipartFile>[]);
    final response = await request.send();
    return _decode(response);
  }

  Future<dynamic> multipartPut(
    String path, {
    Map<String, String>? fields,
    List<http.MultipartFile>? files,
    bool authenticated = false,
  }) async {
    final request = http.MultipartRequest('PUT', _buildUri(path));
    _applyHeaders(request.headers, authenticated: authenticated);
    request.fields.addAll(fields ?? const <String, String>{});
    request.files.addAll(files ?? const <http.MultipartFile>[]);
    final response = await request.send();
    return _decode(response);
  }

  Uri _buildUri(String path, [Map<String, String>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalizedPath');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  void _applyHeaders(
    Map<String, String> headers, {
    required bool authenticated,
    bool json = false,
  }) {
    headers['Accept'] = 'application/json';
    if (json) {
      headers['Content-Type'] = 'application/json';
    }

    if (authenticated && (_sessionStore.cookie?.isNotEmpty ?? false)) {
      headers['Cookie'] = _sessionStore.cookie!;
    }
  }

  Future<dynamic> _decode(http.StreamedResponse response) async {
    final rawBody = await response.stream.bytesToString();
    await _persistCookie(response.headers);

    final dynamic decoded = rawBody.isEmpty ? null : _tryDecode(rawBody);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final message = switch (decoded) {
      Map<String, dynamic> map when map['message'] is String => map['message'] as String,
      _ => response.reasonPhrase ?? 'Request failed',
    };

    throw ApiException(
      message: message,
      statusCode: response.statusCode,
      payload: decoded,
    );
  }

  dynamic _tryDecode(String rawBody) {
    try {
      return jsonDecode(rawBody);
    } catch (_) {
      return rawBody;
    }
  }

  Future<void> _persistCookie(Map<String, String> headers) async {
    final rawCookie = headers['set-cookie'];
    if (rawCookie == null || rawCookie.isEmpty) {
      return;
    }

    final match = RegExp(r'access_token=[^;]+').firstMatch(rawCookie);
    final sessionCookie = match?.group(0) ?? rawCookie.split(';').first.trim();
    await _sessionStore.saveCookie(sessionCookie);
  }
}

class ApiException implements Exception {
  ApiException({
    required this.message,
    required this.statusCode,
    this.payload,
  });

  final String message;
  final int statusCode;
  final dynamic payload;

  @override
  String toString() => message;
}
