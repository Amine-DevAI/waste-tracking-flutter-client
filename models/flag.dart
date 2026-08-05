import 'dart:convert';
import 'model_helpers.dart';

class Flag {
  final int    id;
  final String tableName;
  final int    recordId;
  final String reason;
  final bool   isResolved;
  final String createdAt;
  final String userName;
  final String hint;

  const Flag({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.reason,
    required this.isResolved,
    required this.createdAt,
    this.userName = '',
    this.hint     = '',
  });

  // Backward-compatible getters used by admin UI
  String get flaggedBy => userName;
  String get reviewedBy => ''; // not provided by current backend payload
  bool get isPending => !isResolved;
  String get status => isResolved ? 'resolved' : 'pending';

  factory Flag.fromJson(Map<String, dynamic> json) => Flag(
    id:         parseInt(json['id']),
    tableName:  json['table']      as String? ?? '',
    recordId:   parseInt(json['record_id']),
    reason:     json['reason']     as String? ?? '',
    isResolved: parseBool(json['is_resolved']),
    createdAt:  json['created_at'] as String? ?? '',
    userName:   json['user_name']  as String? ?? '',
    hint:       json['hint']       as String? ?? '',
  );

  static List<Flag> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => Flag.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Flag? fromJsonObject(String jsonStr) {
    final data = unwrapJsonObject(jsonStr);
    return data != null ? Flag.fromJson(data) : null;
  }

  @override
  String toString() => 'Flag($id: $tableName#$recordId [resolved: $isResolved])';
}

/// Minimal placeholder for UI compilation.
/// The current native bindings do not expose a flag-details endpoint yet.
class FlagDetails {
  final int flagId;
  final Map<String, dynamic>? record;
  const FlagDetails({required this.flagId, this.record});
}