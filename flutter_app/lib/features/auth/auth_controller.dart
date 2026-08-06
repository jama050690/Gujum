import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/network/session_store.dart';
import '../../models/session_user.dart';
import 'auth_repository.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository authRepository,
    required SessionStore sessionStore,
  })  : _authRepository = authRepository,
        _sessionStore = sessionStore;

  final AuthRepository _authRepository;
  final SessionStore _sessionStore;

  SessionUser? _user;
  bool _loading = false;
  bool _phonePromptSkipped = false;

  SessionUser? get user => _user;
  bool get isLoading => _loading;
  bool get isAuthenticated => _user != null;

  /// Google orqali kirgan akkauntlarda telefon raqami bo'lmaydi — usiz esa
  /// foydalanuvchi tanishlarining kontaktlarida ko'rinmaydi. Shuning uchun
  /// kirgandan keyin bir ekran so'raymiz. "Keyinroq" bosilsa shu seans uchun
  /// yashiriladi, keyingi ochilishda yana chiqadi.
  bool get needsPhoneNumber =>
      isAuthenticated &&
      !_phonePromptSkipped &&
      (_user?.phone == null || _user!.phone!.trim().isEmpty);

  void skipPhonePrompt() {
    _phonePromptSkipped = true;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    debugPrint(
      'AUTH_DEBUG bootstrap() storedUser=${_sessionStore.savedUser != null} hasCookie=${_sessionStore.cookie?.isNotEmpty == true}',
    );
    final stored = _sessionStore.savedUser;
    if (stored != null) {
      _user = SessionUser.fromJson(stored);
      debugPrint('AUTH_DEBUG restored saved user username=${_user?.username}');
    }

    if ((_sessionStore.cookie?.isNotEmpty ?? false) == false) {
      debugPrint('AUTH_DEBUG bootstrap skipped refreshSession: no cookie');
      return;
    }

    try {
      debugPrint('AUTH_DEBUG bootstrap calling refreshSession()');
      await refreshSession();
    } catch (_) {
      debugPrint('AUTH_DEBUG bootstrap refreshSession failed, logging out');
      await logout();
    }
  }

  Future<void> refreshSession() async {
    debugPrint('AUTH_DEBUG refreshSession() start');
    final result = await _authRepository.fetchMe();
    if (result.username.isEmpty) {
      debugPrint('AUTH_DEBUG refreshSession() empty username');
      return;
    }
    debugPrint('AUTH_DEBUG refreshSession() success username=${result.username}');

    if (_user == null) {
      _user = result;
      await _sessionStore.saveUser(result.toJson());
      notifyListeners();
      return;
    }

    _user = SessionUser(
      username: _user!.username,
      fullName: _user!.fullName ?? result.fullName,
      phone: _user!.phone ?? result.phone,
      birthday: _user!.birthday ?? result.birthday,
      bio: _user!.bio ?? result.bio,
      avatar: _user!.avatar ?? result.avatar,
    );
    await _sessionStore.saveUser(_user!.toJson());
    notifyListeners();
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    debugPrint('AUTH_DEBUG login() username=$username');
    await _runGuarded(() async {
      final user =
          await _authRepository.login(username: username, password: password);
      _user = user;
      await _sessionStore.saveUser(user.toJson());
      await _sessionStore.saveLastLoginUsername(user.username);
      debugPrint('AUTH_DEBUG login() success username=${user.username}');
    });
  }

  Future<void> loginWithGoogle({
    required String credential,
  }) async {
    debugPrint('AUTH_DEBUG loginWithGoogle() start');
    await _runGuarded(() async {
      final user =
          await _authRepository.loginWithGoogle(credential: credential);
      _user = user;
      await _sessionStore.saveUser(user.toJson());
      await _sessionStore.saveLastLoginUsername(user.username);
      debugPrint('AUTH_DEBUG loginWithGoogle() success username=${user.username}');
    });
  }

  Future<OtpResponse> sendSignupOtp(SignupDraft draft) async {
    return _authRepository.sendSignupOtp(draft);
  }

  Future<void> verifySignupOtp({
    required String email,
    required String code,
  }) async {
    await _authRepository.verifySignupOtp(email: email, code: code);
  }

  Future<OtpResponse> resendSignupOtp(String email) {
    return _authRepository.resendSignupOtp(email);
  }

  Future<OtpResponse> requestPasswordReset(String email) {
    return _authRepository.requestPasswordReset(email);
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return _authRepository.resetPassword(
      email: email,
      code: code,
      newPassword: newPassword,
    );
  }

  Future<void> logout() async {
    debugPrint('AUTH_DEBUG logout() username=${_user?.username}');
    _user = null;
    await _sessionStore.clearSession();
    notifyListeners();
  }

  Future<void> updateLocalProfile({
    String? fullName,
    String? phone,
    String? birthday,
    String? bio,
    String? avatar,
  }) async {
    final current = _user;
    if (current == null) {
      return;
    }

    _user = SessionUser(
      username: current.username,
      fullName: fullName ?? current.fullName,
      phone: phone ?? current.phone,
      birthday: birthday ?? current.birthday,
      bio: bio ?? current.bio,
      avatar: avatar ?? current.avatar,
    );
    await _sessionStore.saveUser(_user!.toJson());
    notifyListeners();
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    _loading = true;
    notifyListeners();
    try {
      await action();
    } on ApiException {
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
