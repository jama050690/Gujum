import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/app_config.dart';

class GoogleAuthService {
  GoogleAuthService()
      : _googleSignIn = GoogleSignIn(
          scopes: const ['email'],
          serverClientId: AppConfig.googleServerClientId.isEmpty
              ? null
              : AppConfig.googleServerClientId,
        );

  final GoogleSignIn _googleSignIn;

  bool get isConfigured => AppConfig.googleServerClientId.isNotEmpty;

  Future<String> signInForCredential() async {
    if (!isConfigured) {
      throw const GoogleAuthException(GoogleAuthErrorCode.notConfigured);
    }

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        throw const GoogleAuthException(GoogleAuthErrorCode.cancelled);
      }

      final authentication = await account.authentication;
      final idToken = authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const GoogleAuthException(GoogleAuthErrorCode.missingIdToken);
      }

      return idToken;
    } on PlatformException catch (error) {
      final details = [
        error.code,
        error.message,
        if (error.details != null) error.details.toString(),
      ].where((value) => value != null && value.trim().isNotEmpty).join(' | ');

      final normalized = details.toLowerCase();
      if (normalized.contains('developer_error') ||
          normalized.contains('apiexception: 10') ||
          normalized.contains(' 10 ') ||
          normalized.contains('12500')) {
        throw GoogleAuthException(
          GoogleAuthErrorCode.androidClientMismatch,
          details: details,
        );
      }

      throw GoogleAuthException(
        GoogleAuthErrorCode.failed,
        details: details,
      );
    } catch (error) {
      if (error is GoogleAuthException) {
        rethrow;
      }

      throw GoogleAuthException(
        GoogleAuthErrorCode.failed,
        details: error.toString(),
      );
    }
  }
}

enum GoogleAuthErrorCode {
  notConfigured,
  androidClientMismatch,
  cancelled,
  missingIdToken,
  failed,
}

class GoogleAuthException implements Exception {
  const GoogleAuthException(
    this.code, {
    this.details,
  });

  final GoogleAuthErrorCode code;
  final String? details;
}
