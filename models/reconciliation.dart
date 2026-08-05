import 'dart:convert';
import 'model_helpers.dart';

class Reconciliation {
  final int id;
  final int weighingId;
  final double originalWeight; // Net
  final double originalGross;
  final double originalTare;
  final String uuid;
  final String status;
  final String material;
  final String product;
  final String lot;
  final bool isFlagged;
  final double? newWeight;
  final String? validatorName;
  final double? serverDiff;
  final String? rejectionReason;

  const Reconciliation({
    required this.id,
    required this.weighingId,
    required this.originalWeight,
    required this.originalGross,
    required this.originalTare,
    required this.uuid,
    required this.status,
    required this.material,
    required this.product,
    required this.lot,
    required this.isFlagged,
    this.newWeight,
    this.validatorName,
    this.serverDiff,
    this.rejectionReason,
  });

  double get weightDifference =>
      serverDiff ?? (newWeight ?? 0.0) - originalWeight;

  factory Reconciliation.fromJson(Map<String, dynamic> json) {
    // Handle nested weights object from /api/reco/list
    final weights = json['weights'] as Map<String, dynamic>?;
    final orig = weights?['original'] as Map<String, dynamic>?;
    final after = weights?['new'] as Map<String, dynamic>?;
    final diffs = weights?['diffs'] as Map<String, dynamic>?;

    // Also check old shapes (before/after at top level)
    final before = json['before'] as Map<String, dynamic>?;
    final origFlat = json['original'] as Map<String, dynamic>?;

    return Reconciliation(
      id: parseInt(json['id'] ?? json['reco_id']),
      weighingId: parseInt(json['weighing_id']),

      // Original weight — check nested weights first, then fall back to old shapes
      originalWeight: parseDouble(orig?['net'] ??
          origFlat?['net'] ??
          before?['net'] ??
          json['original_net'] ??
          0),
      originalGross: parseDouble(orig?['gross'] ??
          origFlat?['gross'] ??
          before?['gross'] ??
          json['original_gross'] ??
          0),
      originalTare: parseDouble(orig?['tare'] ??
          origFlat?['tare'] ??
          before?['tare'] ??
          json['original_tare'] ??
          0),

      uuid: json['uuid'] as String? ?? '',
      status: json['current_status'] ?? json['status'] as String? ?? '',
      material: json['material'] as String? ??
          (json['label'] as String?)?.split(' - ').first ??
          '',
      product: json['product'] as String? ??
          (json['label'] as String?)?.split(' - ').last ??
          '',
      lot: json['lot'] as String? ?? '',
      isFlagged: parseBool(json['is_flagged']),

      // New weight — check nested new first, then fall back to old shapes
      newWeight: after?['net'] != null
          ? parseDouble(after!['net'])
          : json['new_weight'] != null
              ? parseDouble(json['new_weight'])
              : null,

      // Validator — server sends 'validator', not 'validator_name'
      validatorName:
          json['validator'] as String? ?? json['validator_name'] as String?,
      serverDiff: diffs?['net'] != null
          ? parseDouble(diffs!['net'])
          : json['diff'] != null
              ? parseDouble(json['diff'])
              : json['net_diff'] != null
                  ? parseDouble(json['net_diff'])
                  : null,
      rejectionReason:
          json['reason'] as String? ?? json['rejection_reason'] as String?,
    );
  }

  static List<Reconciliation> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => Reconciliation.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Result of a reco_submit call
class RecoResult {
  final int reconciliationId;
  final double originalWeight;
  final double newWeight;
  final double difference;
  final String status;

  const RecoResult({
    required this.reconciliationId,
    required this.originalWeight,
    required this.newWeight,
    required this.difference,
    required this.status,
  });

  factory RecoResult.fromJson(Map<String, dynamic> json, double original) =>
      RecoResult(
        reconciliationId: parseInt(json['reco_id']),
        originalWeight: original,
        newWeight: parseDouble(json['new_weight']),
        difference: parseDouble(json['net_diff']),
        status: json['status'] as String? ?? '',
      );
}
