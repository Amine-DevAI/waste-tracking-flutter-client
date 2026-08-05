import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/models/login_attempt.dart';
import 'package:waste_tracking/ffi/models/user.dart';
import 'package:waste_tracking/ffi/models/reconciliation.dart';
import 'package:waste_tracking/ffi/models/flag.dart';
import 'package:waste_tracking/ffi/models/correction.dart';
import 'package:waste_tracking/ffi/models/shipment.dart';
import 'package:waste_tracking/ffi/models/weighing.dart';
import 'package:waste_tracking/ffi/models/denaturation.dart';
import 'package:waste_tracking/ffi/models/export_record.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';

class AdminService {
  static final AdminService instance = AdminService._();
  AdminService._();

  WasteEngine get _e => WasteEngine.instance;
  get _ctx => _e.handle;
  get _usr => AuthService.instance.session!.handle;

  Future<List<Weighing>> listWeighings({String filters = '{}'}) async {
    final json = _e.admin.weighList(_ctx, _usr, filters: filters);
    return Weighing.fromJsonArray(json);
  }

  Future<List<Reconciliation>> listReconciliations({String filters = '{}'}) async {
    final json = _e.admin.recoList(_ctx, _usr, filters: filters);
    return Reconciliation.fromJsonArray(json);
  }

  Future<List<Reconciliation>> listReconciliationsFiltered(
      {String statusFilter = ''}) async {
    final filters =
        statusFilter.isNotEmpty ? jsonEncode({'status': statusFilter}) : '{}';
    return listReconciliations(filters: filters);
  }

  Future<List<Shipment>> listShipments({String filters = '{}'}) async {
    final json = _e.admin.shipList(_ctx, _usr, filters: filters);
    return Shipment.fromJsonArray(json);
  }

  Future<List<Shipment>> listShipmentsFiltered(
      {String statusFilter = 'all'}) async {
    final filters = jsonEncode({
      'filter': statusFilter,
    });
    return listShipments(filters: filters);
  }

  // "Pending weighings" is unsupported by the backend endpoint.
  // Keep the API method for compatibility but return an empty list.
  Future<List<Weighing>> listPendingWeighings() async {
    return [];
  }

  Future<List<Shipment>> listPendingShipments() async {
    return listShipmentsFiltered(statusFilter: 'pending');
  }

  Future<List<Denaturation>> listDenaturations({String filters = '{}'}) async {
    final json = _e.admin.denatList(_ctx, _usr, filters: filters);
    return Denaturation.fromJsonArray(json);
  }

  Future<List<Denaturation>> listDenaturationsFiltered(
      {String statusFilter = ''}) async {
    final filters =
        statusFilter.isNotEmpty ? jsonEncode({'status': statusFilter}) : '{}';
    return listDenaturations(filters: filters);
  }

  /// Current native binding returns unresolved flags only (no filters).
  /// These optional parameters exist for compatibility with the UI.
  Future<List<Flag>> listFlags({String status = '', String tableName = ''}) async {
    final json = _e.admin.flagsList(_ctx, _usr);
    var list = Flag.fromJsonArray(json);
    if (status.isNotEmpty) {
      final s = status.toLowerCase();
      list = list.where((f) => f.status.toLowerCase() == s).toList();
    }
    if (tableName.isNotEmpty) {
      final t = tableName.toLowerCase();
      list = list.where((f) => f.tableName.toLowerCase() == t).toList();
    }
    return list;
  }

  Future<int> markFlagRead(int flagId) async =>
      _e.admin.flagMarkRead(_ctx, _usr, flagId);

  // Compatibility wrappers for older UI naming.
  // Backend currently supports "mark read" (resolve) only.
  Future<int> approveFlag(int flagId) async => markFlagRead(flagId);
  Future<int> rejectFlag(int flagId, String reason) async =>
      markFlagRead(flagId);

  Future<FlagDetails?> flagDetails(int flagId) async {
    // Not exposed by current native bindings. UI can still compile.
    return null;
  }

  Future<List<Correction>> listCorrections({String filters = '{}'}) async {
    final json = _e.admin.correctionsList(_ctx, _usr, filters: filters);
    return Correction.fromJsonArray(json);
  }

  Future<List<ActiveSession>> listSessions() async {
    final json = _e.admin.sessionsList(_ctx, _usr);
    return ActiveSession.fromJsonArray(json);
  }

  Future<int> deactivateSession(int targetUserId) async =>
      _e.admin.sessionDeactivate(_ctx, _usr, targetUserId);

  Future<List<LoginAttempt>> listLogs() async {
    final json = _e.admin.logsList(_ctx, _usr);
    return LoginAttempt.fromJsonArray(json);
  }

  /// Fetches all records from the traceability master view.
  /// Returns an empty list on failure.
  Future<List<ExportRecord>> fetchExportRecords() async {
    final raw = _e.admin.exportAll(_ctx, _usr);
    if (raw.isEmpty) return [];
    return ExportRecord.fromJsonArray(raw);
  }

  /// Columns always come from the model — never hardcoded per source.
  List<String> getExportColumns(int source) => ExportRecord.allColumns;

  /// Writes the export file in the requested format.
  /// Returns 0 on success, negative on failure.
  Future<int> export({
    required int source,
    required int format,
    required String filePath,
    String startDate = '',
    String endDate = '',
    List<String> columns = const [],
  }) async {
    try {
      final records = await fetchExportRecords();
      if (records.isEmpty) return -2; // no data

      final filtered = _applyDateFilter(records, startDate, endDate);
      if (filtered.isEmpty) return -3; // empty after filter

      final cols = columns.isEmpty ? ExportRecord.allColumns : columns;

      final content = switch (format) {
        ExportFormat.csv => _buildCsv(filtered, cols),
        ExportFormat.txt => _buildTxt(filtered, cols),
        _ => _buildCsv(filtered, cols),
      };

      final file = File(filePath);
      await file.writeAsString(content, flush: true);
      return 0;
    } on FileSystemException {
      return -7; // IO error
    } catch (_) {
      return -1;
    }
  }

  List<ExportRecord> _applyDateFilter(
      List<ExportRecord> records, String start, String end) {
    if (start.isEmpty && end.isEmpty) return records;
    return records.where((r) {
      if (r.date.isEmpty) return true;
      final d = r.date.length >= 10 ? r.date.substring(0, 10) : r.date;
      if (start.isNotEmpty && d.compareTo(start) < 0) return false;
      if (end.isNotEmpty && d.compareTo(end) > 0) return false;
      return true;
    }).toList();
  }

  String _buildCsv(List<ExportRecord> records, List<String> cols) {
    final buf = StringBuffer();
    buf.writeln(cols.map(_csvEscape).join(','));
    for (final r in records) {
      buf.writeln(r.toRow(cols).map(_csvEscape).join(','));
    }
    return buf.toString();
  }

  String _buildTxt(List<ExportRecord> records, List<String> cols) {
    final buf = StringBuffer();
    buf.writeln(cols.join('\t'));
    buf.writeln('-' * (cols.length * 16));
    for (final r in records) {
      buf.writeln(r.toRow(cols).join('\t'));
    }
    return buf.toString();
  }

  String _csvEscape(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
