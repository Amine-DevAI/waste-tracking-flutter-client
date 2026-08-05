import 'dart:convert';

/// Safely parses a dynamic value to an int. Returns 0 if parsing fails.
int parseInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

/// Safely parses a dynamic value to a double. Returns 0.0 if parsing fails.
double parseDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) {
    return double.tryParse(value) ?? 0.0;
  }
  return 0.0;
}

/// Safely parses a dynamic value to a bool.
bool parseBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is String) {
    final v = value.toLowerCase().trim();
    return v == 'true' || v == '1' || v == 't' || v == 'yes';
  }
  return false;
}

/// Robust JSON unwrapper for list responses.
/// Handles both raw arrays `[...]` and wrapped objects `{"success": true, "data": [...]}`.
List<dynamic> unwrapJsonList(String jsonStr) {
  if (jsonStr.isEmpty || jsonStr == '[]') return [];
  try {
    final decoded = jsonDecode(jsonStr);
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['data'] is List) {
      return decoded['data'] as List<dynamic>;
    }
    return [];
  } catch (_) {
    return [];
  }
}

/// Robust JSON unwrapper for object responses.
/// Handles both raw objects `{...}` and wrapped objects `{"success": true, "data": {...}}`.
Map<String, dynamic>? unwrapJsonObject(String jsonStr) {
  if (jsonStr.isEmpty) return null;
  try {
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map && decoded.containsKey('success') && decoded.containsKey('data')) {
      return decoded['data'] as Map<String, dynamic>?;
    }
    return decoded is Map ? decoded as Map<String, dynamic> : null;
  } catch (_) {
    return null;
  }
}