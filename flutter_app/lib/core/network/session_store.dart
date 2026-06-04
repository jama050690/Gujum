import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

class SessionStore {
  SessionStore._(this._prefs);

  static const _cookieKey = 'bootchat.cookie';
  static const _userKey = 'bootchat.user';
  static const _localeKey = 'bootchat.locale';
  static const _darkModeKey = 'bootchat.dark_mode';
  static const _baseUrlKey = 'bootchat.base_url';
  static const _lastLoginUsernameKey = 'bootchat.last_login_username';
  static const _lastActiveChatKey = 'bootchat.last_active_chat';

  final SharedPreferences _prefs;

  static Future<SessionStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SessionStore._(prefs);
  }

  String? get cookie => _prefs.getString(_cookieKey);

  Future<void> saveCookie(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_cookieKey);
      return;
    }
    await _prefs.setString(_cookieKey, value);
  }

  Map<String, dynamic>? get savedUser {
    final raw = _prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUser(Map<String, dynamic>? user) async {
    if (user == null) {
      await _prefs.remove(_userKey);
      return;
    }
    await _prefs.setString(_userKey, jsonEncode(user));
  }

  String get localeCode => _prefs.getString(_localeKey) ?? AppConfig.defaultLocale;

  Future<void> saveLocaleCode(String code) => _prefs.setString(_localeKey, code);

  bool get isDarkMode => _prefs.getBool(_darkModeKey) ?? false;

  Future<void> saveDarkMode(bool value) => _prefs.setBool(_darkModeKey, value);

  String get baseUrl {
    final stored = _prefs.getString(_baseUrlKey);
    if (stored == null || stored.isEmpty) {
      return AppConfig.defaultBaseUrl();
    }

    if (AppConfig.shouldUpgradeStoredBaseUrl(stored)) {
      return AppConfig.defaultBaseUrl();
    }

    return AppConfig.normalizeBaseUrl(stored);
  }

  Future<void> saveBaseUrl(String value) =>
      _prefs.setString(_baseUrlKey, AppConfig.normalizeBaseUrl(value));

  String? get lastLoginUsername => _prefs.getString(_lastLoginUsernameKey);

  Future<void> saveLastLoginUsername(String? value) async {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      await _prefs.remove(_lastLoginUsernameKey);
      return;
    }
    await _prefs.setString(_lastLoginUsernameKey, normalized);
  }

  String? get lastActiveChatUsername => _prefs.getString(_lastActiveChatKey);

  Future<void> saveLastActiveChatUsername(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_lastActiveChatKey);
      return;
    }
    await _prefs.setString(_lastActiveChatKey, value);
  }

  Future<void> clearSession() async {
    await _prefs.remove(_cookieKey);
    await _prefs.remove(_userKey);
  }
}
