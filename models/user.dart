import 'dart:convert';
import 'model_helpers.dart';
import '../bindings/types.dart';

// ============================================================================
// USER MODEL
// ============================================================================

class User {
  final int    id;
  final String username;
  final String fullName;
  final String role;
  final bool   isActive;
  final String createdAt;
  final String lastLogin;
  final int?   zoneId;

  const User({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.lastLogin,
    this.zoneId,
  });

  int get roleCode {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'administrator': return UserRole.admin;
      case 'operator':      return UserRole.operator_;
      case 'validator':
      case 'technician':    return UserRole.validator;
      case 'coordinateur':
      case 'coordonnateur':
        return UserRole.coordinateur;
      default:              return UserRole.viewer;
    }
  }

  bool get isAdmin        => roleCode == UserRole.admin;
  bool get isOperator     => roleCode == UserRole.operator_;
  bool get isValidator    => roleCode == UserRole.validator;
  bool get isCoordinateur => roleCode == UserRole.coordinateur;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id:        parseInt(json['id']),
        username:  json['username']   as String? ?? '',
        fullName:  json['full_name']  as String? ?? '',
        role:      json['role']       as String? ?? 'viewer',
        isActive:  parseBool(json['is_active'] ?? json['active']),
        createdAt: json['created_at'] as String? ?? '',
        lastLogin: json['last_login'] as String? ?? '',
        zoneId:    json['id_zone'] != null ? parseInt(json['id_zone']) : null,
      );

  static List<User> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => User.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> toJson() => {
        'id':         id,
        'username':   username,
        'full_name':  fullName,
        'role':       role,
        'is_active':  isActive,
        'created_at': createdAt,
        'last_login': lastLogin,
        'id_zone':    zoneId,
      };

  @override
  String toString() => 'User($id: $username [$role])';
}

// ============================================================================
// ACTIVE SESSION MODEL
// ============================================================================

class ActiveSession {
  final int    userId;
  final String username;
  final String ip;
  final String lastActive;
  final String version;

  const ActiveSession({
    required this.userId,
    required this.username,
    required this.ip,
    required this.lastActive,
    required this.version,
  });

  factory ActiveSession.fromJson(Map<String, dynamic> json) => ActiveSession(
        userId:     parseInt(json['user_id']),
        username:   json['username']    as String? ?? '',
        ip:         json['ip']          as String? ?? '',
        lastActive: json['last_active'] as String? ?? '',
        version:    json['version']     as String? ?? '',
      );

  static List<ActiveSession> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => ActiveSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  String toString() => 'ActiveSession($username @ $ip)';
}