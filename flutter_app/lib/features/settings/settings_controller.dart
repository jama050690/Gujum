import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/network/session_store.dart';
import '../../l10n/app_strings.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._sessionStore);

  final SessionStore _sessionStore;

  late String _localeCode;
  late bool _isDarkMode;
  late String _baseUrl;

  String get localeCode => _localeCode;
  bool get isDarkMode => _isDarkMode;
  String get baseUrl => _baseUrl;
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;
  Locale get locale => Locale(_localeCode);

  void load() {
    _localeCode = _sessionStore.localeCode;
    _isDarkMode = _sessionStore.isDarkMode;
    _baseUrl = _sessionStore.baseUrl;
  }

  String currentBaseUrl() => _baseUrl;

  Future<void> setLocaleCode(String code) async {
    if (!AppStrings.supportedLocales.contains(code)) {
      return;
    }

    _localeCode = code;
    await _sessionStore.saveLocaleCode(code);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    await _sessionStore.saveDarkMode(value);
    notifyListeners();
  }

  Future<void> setBaseUrl(String value) async {
    _baseUrl = AppConfig.normalizeBaseUrl(value);
    await _sessionStore.saveBaseUrl(_baseUrl);
    notifyListeners();
  }
}
