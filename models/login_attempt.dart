import 'dart:convert';
import 'model_helpers.dart';

// ============================================================================
// LOGIN ATTEMPT MODEL
// ============================================================================

class LoginAttempt {
  final String username;
  final bool success;
  final String ipAddress;
  final String timestamp;
  final String errorMessage;

  const LoginAttempt({
    required this.username,
    required this.success,
    required this.ipAddress,
    required this.timestamp,
    required this.errorMessage,
  });

  factory LoginAttempt.fromJson(Map<String, dynamic> json) => LoginAttempt(
        username:     json['username']      as String? ?? '',
        success:      parseBool(json['success']),
        ipAddress:    json['ip_address']    as String? ?? '',
        timestamp:    json['timestamp']     as String? ?? '',
        errorMessage: json['error_message'] as String? ?? '',
      );

  static List<LoginAttempt> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => LoginAttempt.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  String toString() =>
      'LoginAttempt($username, success: $success, ip: $ipAddress, ts: $timestamp)';
}
