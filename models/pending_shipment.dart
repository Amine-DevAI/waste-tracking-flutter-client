import 'model_helpers.dart';

// ============================================================================
// PENDING SHIPMENT MODEL — matches exact server fields from /api/ship/pending
// ============================================================================
class PendingShipment {
  final int id; // "shipment_id"
  final int recoId; // "reco_id"
  final String qrCode; // "qr_code_data"
  final String material; // "material"
  final String product; // "product"
  final double netWeight; // weights.net
  final double grossWeight; // weights.gross
  final double tareWeight; // weights.tare
  final String lot; // "lot"
  final String zone; // "zone"
  final bool isFlagged; // "is_flagged"
  final String approvedAt; // "timestamp"

  const PendingShipment({
    required this.id,
    required this.recoId,
    required this.qrCode,
    required this.material,
    required this.product,
    required this.netWeight,
    required this.grossWeight,
    required this.tareWeight,
    required this.lot,
    required this.zone,
    required this.isFlagged,
    required this.approvedAt,
  });

  factory PendingShipment.fromJson(Map<String, dynamic> json) {
    // weights come as a nested object: {"net":…, "gross":…, "tare":…}
    final weights = json['weights'] as Map<String, dynamic>? ?? {};

    return PendingShipment(
      id: parseInt(json['shipment_id'] ?? 0),
      recoId: parseInt(json['reco_id'] ?? 0),
      qrCode: json['qr_code_data'] as String? ?? '',
      material: json['material'] as String? ?? '',
      product: json['product'] as String? ?? 'N/A',
      netWeight: parseDouble(weights['net']),
      grossWeight: parseDouble(weights['gross']),
      tareWeight: parseDouble(weights['tare']),
      lot: json['lot'] as String? ?? 'N/A',
      zone: json['zone'] as String? ?? 'General',
      isFlagged: parseBool(json['is_flagged']),
      approvedAt: json['timestamp'] as String? ?? '',
    );
  }

  static List<PendingShipment> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => PendingShipment.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
