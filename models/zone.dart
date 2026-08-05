import 'dart:convert';
import 'package:waste_tracking/ffi/models/model_helpers.dart';

class Zone {
  final int    id;
  final String code;
  final String name;
  final bool   active;

  const Zone({
    required this.id,
    required this.code,
    required this.name,
    required this.active,
  });

  factory Zone.fromJson(Map<String, dynamic> json) => Zone(
    id:     parseInt(json['id']),
    code:   json['code'] as String? ?? '',
    name:   json['name'] as String? ?? '',
    active: parseBool(json['active']),
  );

  Map<String, dynamic> toJson() => {
    'id':     id,
    'code':   code,
    'name':   name,
    'active': active,
  };

  static List<Zone> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => Zone.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  String toString() => 'Zone($id: $code — $name, active: $active)';
}