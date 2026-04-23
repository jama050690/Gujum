import '../../core/network/api_client.dart';
import '../../models/session_user.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
  }) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<SessionUser> login({
    required String username,
    required String password,
    XFile? profilePic,
  }) async {
    final response = await _apiClient.multipartPost(
      '/api/login',
      fields: {
        'username': username,
        'password': password,
      },
      files: profilePic == null
          ? null
          : <http.MultipartFile>[
              await _multipartFileFromXFile(
                field: 'profilePic',
                file: profilePic,
              ),
            ],
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
    final response = await _apiClient.multipartPost(
      '/api/send-otp',
      fields: draft.toJson(),
      files: draft.profilePic == null
          ? null
          : <http.MultipartFile>[
              await _multipartFileFromXFile(
                field: 'profilePic',
                file: draft.profilePic!,
              ),
            ],
    );
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

  Future<http.MultipartFile> _multipartFileFromXFile({
    required String field,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    final filename = file.name.isEmpty ? 'upload.jpg' : file.name;
    return http.MultipartFile.fromBytes(
      field,
      bytes,
      filename: filename,
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
    this.profilePic,
  });

  final String fullName;
  final String username;
  final String phone;
  final String email;
  final String password;
  final int age;
  final bool gender;
  final XFile? profilePic;

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
