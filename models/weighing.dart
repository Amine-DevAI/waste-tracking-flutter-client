import 'model_helpers.dart';
import 'package:intl/intl.dart';

// ============================================================================
// WEIGHING MODEL (STRICT, SOURCE OF TRUTH)
//
// This model enforces a single, exact JSON contract expected from the
// backend (PostgreSQL/Crow) and avoids fallback picking across legacy keys.
// It is immutable and parses `created_at` into a non-nullable DateTime.
// ============================================================================
class Weighing {
  final int id;
  final int? typeId;
  final int? productId;
  final int? storageZoneId;
  final int operatorId;
  final double weightNet;
  final double weightGross;
  final double weightTare;
  final String lotNumber;
  final String qrCodeData;
  final String status;
  final DateTime createdAt;
  final bool isFlagged;
  final String? flagReason;

  // Joined/enriched fields (optional in /api/my_weighings + details endpoints)
  final String material;
  final String typeCode;
  final String product;
  final String operatorName;
  final String zoneName;

  const Weighing({
    required this.id,
    this.typeId,
    this.productId,
    this.storageZoneId,
    required this.operatorId,
    required this.weightNet,
    required this.weightGross,
    required this.weightTare,
    required this.lotNumber,
    required this.qrCodeData,
    required this.status,
    required this.createdAt,
    required this.isFlagged,
    this.flagReason,
    this.material = '',
    this.typeCode = '',
    this.product = '',
    this.operatorName = '',
    this.zoneName = '',
  });

  bool get isPending => status == 'pending';
  bool get isReconciled => status == 'reconciled';
  bool get isShipped => status == 'shipped';

  double get grossWeight => weightGross;
  double get tareWeight => weightTare;
  double get netWeight => weightNet;
  String get typeName => material;
  String get productName => product;

  DateTime get createdAtDate => createdAt;
  String get createdAtFormatted =>
      DateFormat('yyyy-MM-dd HH:mm').format(createdAt);

  /// Parse strict `created_at` as non-nullable DateTime.
  static DateTime _parseCreatedAt(String value) {
    if (value.isEmpty) {
      throw FormatException('created_at cannot be empty');
    }

    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;

    const formats = [
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-ddTHH:mm:ss',
      'yyyy-MM-dd HH:mm',
      'yyyy-MM-ddTHH:mm',
    ];

    for (final f in formats) {
      try {
        return DateFormat(f).parseStrict(value);
      } catch (_) {}
    }

    throw FormatException('Unsupported created_at format: $value');
  }

  factory Weighing.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('id') && !json.containsKey('internal_id'))
      throw FormatException('id required');
    // operator_id is optional in some server responses (e.g. my_weighings list with only operator_name).
    // Default to 0 for UI-only list records.
    if (!json.containsKey('weight_net'))
      throw FormatException('weight_net required');
    if (!json.containsKey('weight_gross'))
      throw FormatException('weight_gross required');
    if (!json.containsKey('weight_tare'))
      throw FormatException('weight_tare required');
    if (!json.containsKey('lot_number') && !json.containsKey('lot'))
      throw FormatException('lot_number required');
    if (!json.containsKey('qr_code_data') && !json.containsKey('uuid'))
      throw FormatException('qr_code_data required');
    if (!json.containsKey('status')) throw FormatException('status required');
    if (!json.containsKey('created_at') &&
        !json.containsKey('timestamp') &&
        !json.containsKey('date')) throw FormatException('created_at required');
    if (!json.containsKey('is_flagged'))
      throw FormatException('is_flagged required');

    final createdAtValue = json['created_at']?.toString() ??
        json['timestamp']?.toString() ??
        json['date']?.toString() ??
        '';
    final createdAt = _parseCreatedAt(createdAtValue);

    return Weighing(
      id: parseInt(json['id'] ?? json['internal_id']),
      typeId: json['type_id'] != null ? parseInt(json['type_id']) : null,
      productId:
          json['product_id'] != null ? parseInt(json['product_id']) : null,
      storageZoneId: json['storage_zone_id'] != null
          ? parseInt(json['storage_zone_id'])
          : null,
      operatorId:
          json.containsKey('operator_id') ? parseInt(json['operator_id']) : 0,
      weightNet: parseDouble(json['weight_net']),
      weightGross: parseDouble(json['weight_gross']),
      weightTare: parseDouble(json['weight_tare']),
      lotNumber:
          json['lot_number']?.toString() ?? json['lot']?.toString() ?? '',
      qrCodeData:
          json['qr_code_data']?.toString() ?? json['uuid']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: createdAt,
      isFlagged: parseBool(json['is_flagged']),
      flagReason: json['flag_reason']?.toString(),
      material: json['material']?.toString() ?? '',
      typeCode: json['type_code']?.toString() ?? '',
      product: json['product']?.toString() ?? '',
      operatorName: json['operator_name']?.toString() ??
          json['operator']?.toString() ??
          '',
      zoneName: json['zone_name']?.toString() ?? '',
    );
  }

  static List<Weighing> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => Weighing.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Weighing? fromJsonObject(String jsonStr) {
    final data = unwrapJsonObject(jsonStr);
    return data != null ? Weighing.fromJson(data) : null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type_id': typeId,
        'product_id': productId,
        'storage_zone_id': storageZoneId,
        'operator_id': operatorId,
        'weight_net': weightNet,
        'weight_gross': weightGross,
        'weight_tare': weightTare,
        'lot_number': lotNumber,
        'qr_code_data': qrCodeData,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'is_flagged': isFlagged,
        'flag_reason': flagReason,
        'material': material,
        'type_code': typeCode,
        'product': product,
        'operator_name': operatorName,
        'zone_name': zoneName,
      };

  @override
  String toString() => 'Weighing($id: ${weightNet}kg [$status])';
}
