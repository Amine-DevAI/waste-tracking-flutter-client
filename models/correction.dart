import 'dart:convert';
import 'model_helpers.dart';

class Correction {
  final int    id;
  final String tableName;
  final int    recordId;
  final String reason;
  final String createdAt;
  final String userName;
  final String correctedBy;

  const Correction({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.reason,
    required this.createdAt,
    this.userName    = '',
    this.correctedBy = '',
  });

  factory Correction.fromJson(Map<String, dynamic> json) => Correction(
    id:          parseInt(json['id']),
    tableName:   json['table']      as String? ?? '',
    recordId:    parseInt(json['record_id']),
    reason:      json['reason']     as String? ?? '',
    createdAt:   json['created_at'] as String? ?? '',
    userName:    json['user_name']  as String? ?? '',
    correctedBy: json['user_name']  as String? ?? '',
  );

  static List<Correction> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => Correction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  String toString() => 'Correction($id: $tableName#$recordId by $correctedBy)';
}