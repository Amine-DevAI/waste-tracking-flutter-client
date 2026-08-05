import 'dart:convert';
import 'package:waste_tracking/ffi/models/model_helpers.dart';

// ============================================================================
// PENDING ITEM MODEL
//
// Covers items from three endpoints:
//   GET /api/reco/pending     → reco_id, status, original{net/gross/tare},
//                               captured_at, type, product, lot, qr,
//                               is_flagged, weighing_id
//   GET /api/ship/pending     → shipment_id, zone, qr_code, ...
//   GET /api/denat/pending    → denat_id, weight_net_before, ...
//
// The fromJson factory is intentionally liberal — it accepts every known
// field name variant across all three endpoints so the UI can use one model.
// ============================================================================

class PendingItem {
  final int    id;
  final String qrCode;

  // Material & classification
  final String material;   // server: "type" (reco) | "material" (ship/denat)
  final String product;
  final String lot;

  // Weights — net is always present; gross/tare only from reco/pending
  final double weight;       // original net
  final double originalGross;
  final double originalTare;

  final String status;
  final String createdAt;    // server: "captured_at" (reco) | "created_at" (others)

  final String? assignedTo;  // validator_name / shipper_name / coordinator_name
  final bool   isFlagged;
  final String? zone;        // shipments only
  final int?   weighingId;   // reco only — needed to match active workflow

  const PendingItem({
    required this.id,
    required this.qrCode,
    required this.material,
    required this.product,
    required this.lot,
    required this.weight,
    this.originalGross = 0.0,
    this.originalTare  = 0.0,
    required this.status,
    required this.createdAt,
    this.assignedTo,
    required this.isFlagged,
    this.zone,
    this.weighingId,
  });

  factory PendingItem.fromJson(Map<String, dynamic> json) {
    // ── ID ─────────────────────────────────────────────────────────────────
    // Check root OR inside the new 'ids' block from Mega Join
    final id = parseInt(
      json['denat_id'] ??
      json['reco_id'] ??
      json['shipment_id'] ??
      json['id'] ??
      (json['ids'] != null ? json['ids']['shipment_id'] : null),
    );

    // ── QR ─────────────────────────────────────────────────────────────────
    final qr = json['qr'] as String?
        ?? json['qr_code'] as String?
        ?? json['qr_code_data'] as String?
        ?? '';

    // ── Material & Product — Digging into the 'material' block ──────────────
    final materialMap = json['material'] as Map<String, dynamic>?;

    final material = (materialMap != null ? materialMap['name'] : null)
        ?? json['type'] as String?
        ?? json['material_type'] as String?
        ?? json['material'] as String? // Fallback for old flat ship list
        ?? '';

    final product = (materialMap != null ? materialMap['product_brand'] : null)
        ?? json['product'] as String?
        ?? json['product_name'] as String?
        ?? '';

    // ── Origin & Lot — Digging into 'origin' block ──────────────────────────
    final originMap = json['origin'] as Map<String, dynamic>?;

    final lot = (originMap != null ? originMap['lot'] : null)
        ?? json['lot'] as String?
        ?? json['lot_number'] as String?
        ?? '';

    final zone = (originMap != null ? originMap['zone'] : null)
        ?? json['zone'] as String?;

    final operatorName = (originMap != null ? originMap['operator'] : null);

    // ── Weights — Digging into 'physics' block ──────────────────────────────
    final physicsMap = json['physics'] as Map<String, dynamic>?;
    final weightsMap = json['weights'] as Map<String, dynamic>?;
    final origMap    = json['original'] as Map<String, dynamic>?;

    double net   = 0.0;
    double gross = 0.0;
    double tare  = 0.0;

    if (physicsMap != null) {
      // NEW: Mega Join Denat format
      net   = parseDouble(physicsMap['weight_before']);
      gross = parseDouble(physicsMap['reco_variance']); // Tactical mapping for coordinators
    } else if (origMap != null) {
      net   = parseDouble(origMap['net']);
      gross = parseDouble(origMap['gross']);
      tare  = parseDouble(origMap['tare']);
    } else if (weightsMap != null) {
      net   = parseDouble(weightsMap['net']);
      gross = parseDouble(weightsMap['gross']);
      tare  = parseDouble(weightsMap['tare']);
    } else {
      net   = parseDouble(json['weight'] ?? json['weight_net'] ?? json['weight_net_before'] ?? 0.0);
    }

    // ── Status & Timestamp ──────────────────────────────────────────────────
    final status = json['status'] as String? ?? '';

    // Check root OR inside 'ids' block for timestamp
    final createdAt = (json['ids'] != null ? json['ids']['timestamp'] : null)
        ?? json['captured_at'] as String?
        ?? json['created_at'] as String?
        ?? json['timestamp'] as String?
        ?? '';

    // ── Assigned-to ─────────────────────────────────────────────────────────
    final assignedTo = operatorName
        ?? json['validator_name'] as String?
        ?? json['shipper_name'] as String?
        ?? json['coordinator_name'] as String?;

    return PendingItem(
      id:            id,
      qrCode:        qr,
      material:      material,
      product:       product,
      lot:           lot,
      weight:        net,
      originalGross: gross,
      originalTare:  tare,
      status:        status,
      createdAt:     createdAt,
      assignedTo:    assignedTo,
      isFlagged:     parseBool(json['is_flagged'] ?? false),
      zone:          zone,
      weighingId:    json['weighing_id'] != null ? parseInt(json['weighing_id']) : null,
    );
  }

  static List<PendingItem> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => PendingItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<PendingItem> fromShipJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => PendingItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  String toString() =>
      'PendingItem(id:$id, qr:$qrCode, material:$material, '
      'net:$weight, gross:$originalGross, tare:$originalTare, status:$status)';
}