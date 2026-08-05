import 'package:waste_tracking/ffi/models/model_helpers.dart';

// ============================================================================
// DENATURATION MODEL
//
// Represents a denaturation operation, either pending or completed.
// Handles multiple server response shapes:
//   - denat_scan_by_qr: {id, qr, material, weight_before, ...}
//   - denat_my_list: {id, qr, material, weight_initial, weight_final, agent_mass, timestamp, note}
//   - denat_list_all: {id, qr, material_name, weight_before, weight_net_after, weight_brut_after, status, created_at, finished_at, note, coordinator_name}
// ============================================================================

class Denaturation {
  final int id;
  final String qrCode;
  final String material;
  final double weightBefore;
  final double? weightBrutAfter;
  final double? weightNetAfter;
  final double? agentMass; // weight_final - weight_initial (from my_list)
  final String status;
  final String createdAt; // 'timestamp' in my_list, 'created_at' in list_all
  final String? completedAt; // 'finished_at' in list_all, none in my_list
  final String? note;
  final String? coordinatorName; // only in list_all

  const Denaturation({
    required this.id,
    required this.qrCode,
    required this.material,
    required this.weightBefore,
    this.weightBrutAfter,
    this.weightNetAfter,
    this.agentMass,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.note,
    this.coordinatorName,
  });

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';

  factory Denaturation.fromJson(Map<String, dynamic> json) {
    // weight_before: my_list uses 'weight_initial', scan uses 'weight_before', pending uses 'weight_net_before'
    final weightBefore = parseDouble(
      json['weight_before'] ??
          json['weight_initial'] ??
          json['weight_net_before'] ??
          0,
    );

    // weight net after: my_list uses 'weight_final', list_all uses 'weight_net_after'
    final rawNetAfter = json['weight_net_after'] ?? json['weight_final'];
    final weightNetAfter =
        rawNetAfter != null ? parseDouble(rawNetAfter) : null;

    // weight brut after: only in list_all
    final rawBrutAfter = json['weight_brut_after'];
    final weightBrutAfter =
        rawBrutAfter != null ? parseDouble(rawBrutAfter) : null;

    // agent mass (chemical added): my_list provides this directly
    final rawAgent = json['agent_mass'];
    final agentMass = rawAgent != null ? parseDouble(rawAgent) : null;

    // status: my_list doesn't send it (all rows are completed), default to completed if timestamp exists
    final status = json['status'] as String? ??
        (json['timestamp'] != null ? 'completed' : '');

    // created_at: 'timestamp' in my_list, 'created_at' in list_all/scan
    final createdAt =
        json['created_at'] as String? ?? json['timestamp'] as String? ?? '';

    // completed_at: 'finished_at' in list_all alias, none in my_list
    final completedAt =
        json['completed_at'] as String? ?? json['finished_at'] as String?;
    // 'In Progress' is a server placeholder string — treat as null
    final completedAtClean = (completedAt == 'In Progress' || completedAt == '')
        ? null
        : completedAt;

    // note: server hardcodes 'Chemical stabilization complete' as default
    final note = json['note'] as String? ?? json['comment'] as String?;
    // Don't show the server default, treat as null
    final noteClean = (note == 'Chemical stabilization complete') ? null : note;

    // coordinator_name: only in list_all
    final coordinatorName =
        json['coordinator_name'] as String? ?? json['operator'] as String?;
    final coordinatorClean =
        (coordinatorName == 'Unassigned' || coordinatorName == '')
            ? null
            : coordinatorName;

    return Denaturation(
      id: parseInt(json['id'] ?? json['denat_id']),
      qrCode: json['qr'] as String? ?? json['qr_code_data'] as String? ?? '',
      material: json['material'] as String? ??
          json['material_name'] as String? ?? // list_all uses 'material_name'
          '',
      weightBefore: weightBefore,
      weightBrutAfter: weightBrutAfter,
      weightNetAfter: weightNetAfter,
      agentMass: agentMass,
      status: status,
      createdAt: createdAt,
      completedAt: completedAtClean,
      note: noteClean,
      coordinatorName: coordinatorClean,
    );
  }

  static List<Denaturation> fromJsonArray(String jsonStr) {
    return unwrapJsonList(jsonStr)
        .map((e) => Denaturation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  String toString() =>
      'Denaturation(id: $id, qr: $qrCode, material: $material, status: $status)';
}
