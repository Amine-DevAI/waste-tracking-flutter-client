import 'model_helpers.dart';

// ============================================================================
// WEIGHT TRIO — used for both verified and original weights
// ============================================================================
class WeightTrio {
  final double net;
  final double gross;
  final double tare;

  const WeightTrio({
    required this.net,
    required this.gross,
    required this.tare,
  });

  factory WeightTrio.fromJson(Map<String, dynamic> json) {
    return WeightTrio(
      net: parseDouble(json['net']),
      gross: parseDouble(json['gross']),
      tare: parseDouble(json['tare']),
    );
  }

  static WeightTrio zero() => const WeightTrio(net: 0, gross: 0, tare: 0);
}

// ============================================================================
// SHIPMENT MODEL — matches exact server field names per endpoint
// ============================================================================
class Shipment {
  final int id;
  final String qrCode; // only from /api/ship/pending
  final int reconciliationId;
  final String status;
  final String createdAt;
  final String shippedAt;
  final String note;
  final bool isFlagged;
  final String material;
  final String product;
  final String lot;
  final String zone;
  final String weighedAt; // only from /api/ship/by_qr
  final bool wasDenatured;
  final String denatStatus;
  final String shipper; // only from /api/ship/list
  final WeightTrio verifiedWeights;
  final WeightTrio originalWeights;

  const Shipment({
    required this.id,
    required this.qrCode,
    required this.reconciliationId,
    required this.status,
    required this.createdAt,
    required this.shippedAt,
    required this.note,
    required this.isFlagged,
    required this.material,
    required this.product,
    required this.lot,
    required this.zone,
    required this.weighedAt,
    required this.wasDenatured,
    required this.denatStatus,
    required this.shipper,
    required this.verifiedWeights,
    required this.originalWeights,
  });

  bool get isPending => status == 'pending';
  bool get isShipped => status == 'shipped';
  bool get isCancelled => status == 'cancelled';

  // Use verified net weight as the primary weight — falls back to original
  double get weight =>
      verifiedWeights.net > 0 ? verifiedWeights.net : originalWeights.net;
  double get netWeight => weight;
  String get productName => product;

  // Field mapping by endpoint (EXACT server keys):
  // /api/ship/by_qr:     shipment_id, verified_weights{net,gross,tare}, original_weights{net,gross,tare}, material, product, lot, zone, weighed_at, is_flagged
  // /api/ship/pending:  shipment_id, reco_id, material, product, weights{net,gross,tare}, lot, zone, is_flagged, timestamp, qr_code_data
  // /api/ship/list:      id, status, shipped_at, approved_at, shipper, material, product, lot, weights{original,verified,drift}, zone, is_flagged, denaturation{required,status,final_weight}
  // /api/my_shipments:  id, status, shipped_at, note, is_flagged, material, product, weight, meta{was_denatured,denat_status}
  factory Shipment.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>? ?? {};
    final denat = json['denaturation'] as Map<String, dynamic>? ?? {};
    final weightsTrio = json['weights'] as Map<String, dynamic>?;

    // ── weights ──────────────────────────────────────────────────────────────
    final verifiedRaw = json['verified_weights'] as Map<String, dynamic>?;
    final originalRaw = json['original_weights'] as Map<String, dynamic>?;

    WeightTrio verified;
    WeightTrio original;

    if (verifiedRaw != null) {
      // ship/by_qr: verified_weights + original_weights
      verified = WeightTrio.fromJson(verifiedRaw);
      original = originalRaw != null
          ? WeightTrio.fromJson(originalRaw)
          : WeightTrio.zero();
    } else if (weightsTrio != null && weightsTrio.containsKey('net')) {
      // ship/pending: weights{net,gross,tare}
      verified = WeightTrio.fromJson(weightsTrio);
      original = WeightTrio.zero();
    } else if (weightsTrio != null && weightsTrio.containsKey('original')) {
      // ship/list: weights{original,verified,drift} flat doubles
      verified = WeightTrio(
        net: parseDouble(weightsTrio['verified']),
        gross: 0,
        tare: 0,
      );
      original = WeightTrio(
        net: parseDouble(weightsTrio['original']),
        gross: 0,
        tare: 0,
      );
    } else if (json.containsKey('weight')) {
      // my_Shipments: single 'weight' field
      final w = parseDouble(json['weight'] ?? 0);
      verified = WeightTrio(net: w, gross: 0, tare: 0);
      original = WeightTrio.zero();
    } else {
      verified = WeightTrio.zero();
      original = WeightTrio.zero();
    }

    // ── shipped_at ─────────────────────────────────────────────────────────
    final shippedAt =
        json['shipped_at'] as String? ?? json['exit_time'] as String? ?? '';
    final shippedAtClean = (shippedAt == 'Pending') ? '' : shippedAt;

    // ── denaturation metadata ─────────────────────────────────────────────────
    final wasDenatured =
        parseBool(denat['required']) || parseBool(meta['was_denatured']);
    final denatStatus =
        denat['status'] as String? ?? meta['denat_status'] as String? ?? '';

    return Shipment(
      id: parseInt(json['shipment_id'] ?? json['id'] ?? 0),
      qrCode: json['qr_code_data'] as String? ?? '',
      reconciliationId:
          parseInt(json['reco_id'] ?? json['reconciliation_id'] ?? 0),
      status: json['status'] as String? ?? '',
      createdAt: json['approved_at'] as String? ??
          json['timestamp'] as String? ??
          json['created_at'] as String? ??
          '',
      shippedAt: shippedAtClean,
      note: json['note'] as String? ?? json['shipping_note'] as String? ?? '',
      isFlagged: parseBool(json['is_flagged']),
      material: json['material'] as String? ?? '',
      product: json['product'] as String? ?? '',
      lot: json['lot'] as String? ?? '',
      zone: json['zone'] as String? ?? '',
      weighedAt: json['weighed_at'] as String? ?? '',
      wasDenatured: wasDenatured,
      denatStatus: denatStatus,
      shipper: json['shipper'] as String? ?? '',
      verifiedWeights: verified,
      originalWeights: original,
    );
  }

  static List<Shipment> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => Shipment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Shipment? fromJsonObject(String jsonStr) {
    final data = unwrapJsonObject(jsonStr);
    return data != null ? Shipment.fromJson(data) : null;
  }

  @override
  String toString() => 'Shipment($id: ${weight}kg [$status])';
}
