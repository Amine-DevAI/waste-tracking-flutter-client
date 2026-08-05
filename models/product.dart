import 'dart:convert';
import 'package:waste_tracking/ffi/models/model_helpers.dart';

class Product {
  final int    id;
  final String name;

  const Product({
    required this.id,
    required this.name,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id:   parseInt(json['id']),
    name: json['name'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id':   id,
    'name': name,
  };

  static List<Product> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  String toString() => 'Product($id: $name)';
}