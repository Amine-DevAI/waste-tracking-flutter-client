import 'package:waste_tracking/ffi/models/model_helpers.dart';

class ExportRecord {
  final int    id;
  final String date;
  final String operator_;
  final String material;
  final String nature;
  final String product;
  final String lot;
  final double initialGross;
  final double initialTare;
  final double initialNet;
  final double verifiedGross;
  final double verifiedNet;
  final double variance;
  final String statusWeighing;
  final String statusReco;
  final String statusShipment;
  final String statusDenat;
  final String validator;
  final String approvedAt;

  const ExportRecord({
    required this.id,
    required this.date,
    required this.operator_,
    required this.material,
    required this.nature,
    required this.product,
    required this.lot,
    required this.initialGross,
    required this.initialTare,
    required this.initialNet,
    required this.verifiedGross,
    required this.verifiedNet,
    required this.variance,
    required this.statusWeighing,
    required this.statusReco,
    required this.statusShipment,
    required this.statusDenat,
    required this.validator,
    required this.approvedAt,
  });

  factory ExportRecord.fromJson(Map<String, dynamic> j) => ExportRecord(
    id:             parseInt(j['id']),
    date:           j['date']            as String? ?? '',
    operator_:      j['operator']        as String? ?? '',
    material:       j['material']        as String? ?? '',
    nature:         j['nature']          as String? ?? '',
    product:        j['product']         as String? ?? '',
    lot:            j['lot']             as String? ?? '',
    initialGross:   parseDouble(j['initial_gross']),
    initialTare:    parseDouble(j['initial_tare']),
    initialNet:     parseDouble(j['initial_net']),
    verifiedGross:  parseDouble(j['verified_gross']),
    verifiedNet:    parseDouble(j['verified_net']),
    variance:       parseDouble(j['variance']),
    statusWeighing: j['status_weighing'] as String? ?? '',
    statusReco:     j['status_reco']     as String? ?? '',
    statusShipment: j['status_shipment'] as String? ?? '',
    statusDenat:    j['status_denat']    as String? ?? '',
    validator:      j['validator']       as String? ?? '',
    approvedAt:     j['approved_at']     as String? ?? '',
  );

  static List<ExportRecord> fromJsonArray(String jsonStr) =>
      unwrapJsonList(jsonStr)
          .map((e) => ExportRecord.fromJson(e as Map<String, dynamic>))
          .toList();

  static const List<String> allColumns = [
    'ID', 'Date', 'Operator', 'Material', 'Nature', 'Product', 'Lot',
    'Initial Gross', 'Initial Tare', 'Initial Net',
    'Verified Gross', 'Verified Net', 'Variance',
    'Status Weighing', 'Status Reco', 'Status Shipment', 'Status Denat',
    'Validator', 'Approved At',
  ];

  List<String> toRow(List<String> columns) {
    final map = {
      'ID':              id.toString(),
      'Date':            date,
      'Operator':        operator_,
      'Material':        material,
      'Nature':          nature,
      'Product':         product,
      'Lot':             lot,
      'Initial Gross':   initialGross.toStringAsFixed(3),
      'Initial Tare':    initialTare.toStringAsFixed(3),
      'Initial Net':     initialNet.toStringAsFixed(3),
      'Verified Gross':  verifiedGross.toStringAsFixed(3),
      'Verified Net':    verifiedNet.toStringAsFixed(3),
      'Variance':        variance.toStringAsFixed(3),
      'Status Weighing': statusWeighing,
      'Status Reco':     statusReco,
      'Status Shipment': statusShipment,
      'Status Denat':    statusDenat,
      'Validator':       validator,
      'Approved At':     approvedAt,
    };
    return columns.map((c) => map[c] ?? '').toList();
  }
}
