import 'dart:isolate';
import 'package:waste_tracking/ffi/engine.dart';
import 'dart:convert';
import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/ffi/models/shipment.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/ffi/services/pending_service.dart';

class ShipmentService {
  static final ShipmentService instance = ShipmentService._();
  ShipmentService._();

  // ── getByQR ───────────────────────────────────────────────────────────────
  Future<Shipment?> getByQR(String qrData) async {
    final session = AuthService.instance.session;
    if (session == null) return null;
    final json = WasteEngine.instance.shipment.getByQR(
        WasteEngine.instance.handle, session.handle, qrData);
    return Shipment.fromJsonObject(json);
  }

  // ── dispatch ──────────────────────────────────────────────────────────────
  Future<bool> dispatch(int shipmentId, {String note = ''}) async {
    final session = AuthService.instance.session;
    if (session == null) return false;
    print('[DEBUG] ShipmentService.dispatch called — shipment_id=$shipmentId');
    final json = WasteEngine.instance.shipment.dispatch(
        WasteEngine.instance.handle, session.handle, shipmentId, note: note);
    print('[DEBUG] dispatch raw response: $json');
    if (json.isEmpty) return false;
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── myList ────────────────────────────────────────────────────────────────
  Future<List<Shipment>> myList({String status = 'all'}) async {
    final session = AuthService.instance.session;
    if (session == null) return [];
    final json = WasteEngine.instance.shipment.myList(
        WasteEngine.instance.handle, session.handle, status: status);
    return Shipment.fromJsonArray(json);
  }

  // ── correctStatus ─────────────────────────────────────────────────────────
  Future<int> correctStatus(int shipmentId, String newStatus, String reason) async {
    final session = AuthService.instance.session;
    if (session == null) return -6;
    return WasteEngine.instance.shipment.correctStatus(
        WasteEngine.instance.handle, session.handle,
        shipmentId, newStatus, reason);
  }

  // ── notify ────────────────────────────────────────────────────────────────
  void init(UserSession session) {
    WasteEngine.instance.shipment.setNotifyCallback(session.handle, (String signal) {
      if (signal == 'SHIPMENT_READY' || signal == 'SHIPMENT_DISPATCHED') {
        PendingService.instance.refreshShipQueue();
      }
    });
  }
}