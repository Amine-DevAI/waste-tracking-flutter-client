import 'dart:convert';
import 'model_helpers.dart';

class MaterialType {
  final int    id;
  final String code;
  final String name;
  final String nature;
  final String forme;
  final int    tagCode;
  final bool   requiresLot;
  final bool   requiresName;
  final bool   requiresProduct;
  final bool   requiresDenaturation;

  const MaterialType({
    required this.id,
    required this.code,
    required this.name,
    required this.nature,
    required this.forme,
    required this.tagCode,
    required this.requiresLot,
    required this.requiresName,
    required this.requiresProduct,
    required this.requiresDenaturation,
  });

  factory MaterialType.fromJson(Map<String, dynamic> json) => MaterialType(
    id:                   parseInt(json['id']),
    code:                 json['code'] as String? ?? '',
    name:                 json['name'] as String? ?? '',
    nature:               json['nature'] as String? ?? '',
    forme:                json['forme'] as String? ?? '',
    tagCode:              parseInt(json['tag_code']),
    requiresLot:          parseBool(json['requires_lot']),
    requiresName:         parseBool(json['requires_name']),
    requiresProduct:      parseBool(json['requires_product']),
    requiresDenaturation: parseBool(json['requires_denaturation']),
  );

  static List<MaterialType> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => MaterialType.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static MaterialType? fromJsonObject(String jsonStr) {
    final data = unwrapJsonObject(jsonStr);
    return data != null ? MaterialType.fromJson(data) : null;
  }

  Map<String, dynamic> toJson() => {
    'id':                    id,
    'code':                  code,
    'name':                  name,
    'nature':                nature,
    'forme':                 forme,
    'tag_code':              tagCode,
    'requires_lot':          requiresLot,
    'requires_name':         requiresName,
    'requires_product':      requiresProduct,
    'requires_denaturation': requiresDenaturation,
  };
}