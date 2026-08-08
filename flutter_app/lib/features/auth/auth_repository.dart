import '../../core/network/api_client.dart';
import '../../models/session_user.dart';

class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
  }) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<SessionUser> login({
    required String username,
    required String password,
  }) async {
    final response = await _apiClient.multipartPost(
      '/api/login',
      fields: {
        'username': username,
        'password': password,
      },
    );

    final userJson =
        (response as Map<String, dynamic>)['user'] as Map<String, dynamic>;
    return SessionUser.fromJson(userJson);
  }

  /// Google hisobi yo'q qurilmalar uchun: raqam + ism.
  ///
  /// Raqam tasdiqlanmaydi — server ham shu holatda ishlaydi. Bu vaqtinchalik
  /// yechim, SMS kodi keyinroq qo'shiladi.
  Future<SessionUser> loginWithPhone({
    required String phone,
    required String fullName,
  }) async {
    final response = await _apiClient.postJson(
      '/api/login/phone',
      body: {
        'phone': phone,
        'fullName': fullName,
      },
    );

    final userJson =
        (response as Map<String, dynamic>)['user'] as Map<String, dynamic>;
    return SessionUser.fromJson(userJson);
  }

  Future<SessionUser> loginWithGoogle({
    required String credential,
  }) async {
    final response = await _apiClient.postJson(
      '/api/login/google',
      body: {
        'credential': credential,
      },
    );

    final userJson =
        (response as Map<String, dynamic>)['user'] as Map<String, dynamic>;
    return SessionUser.fromJson(userJson);
  }

  Future<SessionUser> fetchMe() async {
    final response = await _apiClient.getJson('/api/me', authenticated: true);
    final userJson =
        (response as Map<String, dynamic>)['user'] as Map<String, dynamic>;
    return SessionUser.fromJson(userJson);
  }

  Future<OtpResponse> sendSignupOtp(SignupDraft draft) async {
    final response =
        await _apiClient.postJson('/api/send-otp', body: draft.toJson());
    return OtpResponse.fromJson(response as Map<String, dynamic>);
  }

  Future<void> verifySignupOtp({
    required String email,
    required String code,
  }) async {
    await _apiClient.postJson(
      '/api/verify-otp',
      body: {
        'email': email,
        'code': code,
      },
    );
  }

  Future<OtpResponse> resendSignupOtp(String email) async {
    final response = await _apiClient.postJson(
      '/api/resend-otp',
      body: {'email': email},
    );
    return OtpResponse.fromJson(response as Map<String, dynamic>);
  }

  Future<OtpResponse> requestPasswordReset(String email) async {
    final response = await _apiClient.postJson(
      '/api/forgot-password',
      body: {'email': email},
    );
    return OtpResponse.fromJson(response as Map<String, dynamic>);
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _apiClient.postJson(
      '/api/reset-password',
      body: {
        'email': email,
        'code': code,
        'newPassword': newPassword,
      },
    );
  }

}

class SignupDraft {
  SignupDraft({
    required this.fullName,
    required this.username,
    required this.phone,
    required this.email,
    required this.password,
    required this.age,
    required this.gender,
  });

  final String fullName;
  final String username;
  final String phone;
  final String email;
  final String password;
  final int age;
  final bool gender;

  Map<String, String> toJson() => {
        'fullName': fullName,
        'username': username,
        'phone': phone,
        'email': email,
        'password': password,
        'age': age.toString(),
        'gender': gender.toString(),
      };
}

class OtpResponse {
  const OtpResponse({
    required this.message,
    this.devOtp,
  });

  final String message;
  final String? devOtp;

  factory OtpResponse.fromJson(Map<String, dynamic> json) {
    return OtpResponse(
      message: (json['message'] ?? '').toString(),
      devOtp: json['devOtp']?.toString(),
    );
  }
}
